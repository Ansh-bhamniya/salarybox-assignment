-- Run once against the Supabase project's Postgres instance.

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

-- Dummy demo credentials (per assignment: dummy creds are fine).
-- Plain-text password is intentional here — flagged in the PRD as a
-- known limitation, not production auth.
insert into users (role, employee_id, username, password)
values ('admin', null, 'admin', 'admin123')
on conflict (username) do nothing;
