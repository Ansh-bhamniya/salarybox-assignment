-- Run against the Supabase project's Postgres instance (SQL editor). Safe to
-- re-run: every statement is idempotent, so the same file both sets up a fresh
-- project and upgrades an existing one.

create extension if not exists pgcrypto;

create table if not exists users (
  id uuid primary key default gen_random_uuid(),
  role text not null check (role in ('admin', 'staff')),
  employee_id text unique,
  username text not null unique,
  password text not null,
  created_at timestamptz not null default now()
);

create table if not exists staff (
  id uuid primary key default gen_random_uuid(),
  employee_id text not null unique,
  name text not null,
  face_embedding double precision[],
  enrollment_photo_url text,
  enrolled_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists attendance (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid not null references staff(id) on delete cascade,
  date date not null,
  time time not null,
  selfie_url text not null,
  latitude double precision not null,
  longitude double precision not null,
  match_confidence double precision,
  created_at timestamptz not null default now()
);

create index if not exists attendance_staff_id_idx on attendance (staff_id);

-- ---------------------------------------------------------------------------
-- Face templates. One row per enrolled face capture, tagged with the model
-- that produced it. Enrolling never overwrites: the previous active templates
-- are revoked (kept for audit) and the new ones become active. staff.
-- face_embedding / enrollment_photo_url / enrolled_at are kept in step by
-- enrol_face() below only so app builds that predate this table keep working.
-- ---------------------------------------------------------------------------
create table if not exists face_templates (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid not null references staff(id) on delete cascade,
  embedding double precision[] not null,
  model_version text not null,
  photo_url text,
  status text not null default 'active' check (status in ('active', 'revoked')),
  created_by uuid references users(id) on delete set null,
  created_at timestamptz not null default now(),
  revoked_at timestamptz,
  revoked_by uuid references users(id) on delete set null,
  revoke_reason text
);

create index if not exists face_templates_active_idx
  on face_templates (staff_id) where status = 'active';

-- Attendance attempts the server refused. Known outcomes: 'not_enrolled'.
-- (More will land with match calibration and liveness.)
create table if not exists attendance_attempts (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid not null references staff(id) on delete cascade,
  outcome text not null,
  reason text,
  created_at timestamptz not null default now()
);

create index if not exists attendance_attempts_staff_idx
  on attendance_attempts (staff_id, created_at desc);

-- Who did what to whom (enrolments, re-enrolments, ...).
create table if not exists audit_log (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid references users(id) on delete set null,
  action text not null,
  target_type text not null,
  target_id uuid,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists audit_log_target_idx
  on audit_log (target_type, target_id, created_at desc);

-- Which face-model version the matched template came from.
alter table attendance add column if not exists model_version text;

-- Enrol (or re-enrol) a face atomically: revoke the current active templates,
-- add the new one, refresh the compatibility columns on staff and write the
-- audit entry. Locks the staff row so two simultaneous enrolments for the same
-- person can't both end up active.
create or replace function enrol_face(
  p_staff_id uuid,
  p_embedding double precision[],
  p_model_version text,
  p_photo_url text,
  p_actor uuid default null
) returns staff
language plpgsql
as $$
declare
  v_staff staff;
  v_replaced integer;
begin
  perform 1 from staff where id = p_staff_id for update;
  if not found then
    raise exception 'staff_not_found' using errcode = 'P0002';
  end if;

  update face_templates
     set status = 'revoked', revoked_at = now(), revoked_by = p_actor, revoke_reason = 're-enrolled'
   where staff_id = p_staff_id and status = 'active';
  get diagnostics v_replaced = row_count;

  insert into face_templates (staff_id, embedding, model_version, photo_url, created_by)
  values (p_staff_id, p_embedding, p_model_version, p_photo_url, p_actor);

  update staff
     set face_embedding = p_embedding, enrollment_photo_url = p_photo_url, enrolled_at = now()
   where id = p_staff_id
   returning * into v_staff;

  insert into audit_log (actor_user_id, action, target_type, target_id, details)
  values (
    p_actor,
    case when v_replaced > 0 then 'face.re_enrol' else 'face.enrol' end,
    'staff',
    p_staff_id,
    jsonb_build_object('model_version', p_model_version, 'replaced_templates', v_replaced)
  );

  return v_staff;
end;
$$;

-- Backfill: turn each existing valid (192-value) enrolment into an active
-- template. Older shorter embeddings could never match the current model, so
-- those staff simply count as not enrolled until re-enrolled.
insert into face_templates (staff_id, embedding, model_version, photo_url, created_at)
select s.id, s.face_embedding, 'mobilefacenet-192-v1', s.enrollment_photo_url, coalesce(s.enrolled_at, now())
from staff s
where s.face_embedding is not null
  and array_length(s.face_embedding, 1) = 192
  and not exists (select 1 from face_templates t where t.staff_id = s.id);

-- Lock the tables down. The API talks to Postgres with the service role, which
-- bypasses row level security, so enabling it with no policies means nobody
-- holding the project's public (anon) key can read or write these tables
-- through Supabase's auto-generated REST API.
alter table users enable row level security;
alter table staff enable row level security;
alter table attendance enable row level security;
alter table face_templates enable row level security;
alter table attendance_attempts enable row level security;
alter table audit_log enable row level security;

-- Functions are executable by everyone by default; only the API should call this.
revoke all on function enrol_face(uuid, double precision[], text, text, uuid) from public, anon, authenticated;
grant execute on function enrol_face(uuid, double precision[], text, text, uuid) to service_role;

-- Dummy demo credentials (per assignment: dummy creds are fine).
-- Plain-text password is intentional here — flagged in the PRD as a
-- known limitation, not production auth.
insert into users (role, employee_id, username, password)
values ('admin', null, 'admin', 'admin123')
on conflict (username) do nothing;

-- Make Supabase's REST layer pick up the new tables/functions straight away.
notify pgrst, 'reload schema';
