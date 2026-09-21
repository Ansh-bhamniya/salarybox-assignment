# Attendance App — PRD

Source: `Android_assignment_SB.pdf` (hiring assignment, 2-day timeline).

## What we're building

A two-role attendance app. Admin enrolls staff faces and reviews attendance.
Staff mark their own attendance by taking a selfie that has to match their
enrolled face. Location and timestamp get captured automatically at the
moment of marking.

Admin and staff use separate physical devices, so attendance data needs to
live somewhere both sides can reach — this isn't a single-device/kiosk app.

## Architecture

```
Flutter app (frontend/)
   │  REST (JSON)
   ▼
Node.js API (backend/)
   │  supabase-js (service role)
   ▼
Supabase
   - Postgres: users, staff, attendance
   - Storage: enrollment photos, attendance selfies
```

Face detection and face matching both happen **on-device**, not on the
server. The backend never receives raw images to "figure out" who someone
is — it just stores what the phone already decided.

- Face detection: Google ML Kit (`google_mlkit_face_detection`) to find and
  crop the face from the camera frame.
- Face matching: a bundled TFLite embedding model (MobileFaceNet-style,
  ~192-d output) run via `tflite_flutter`. Enrollment produces one embedding
  vector per staff member; attendance produces a fresh embedding that gets
  compared to it with cosine/Euclidean distance against a fixed threshold.
  Match = attendance recorded. No match = rejected, nothing is stored.

This means the staff device needs the enrolled embedding available locally
before it can verify a match, so the app fetches it from the backend as part
of login / staff profile load, not on every attendance attempt.

Auth is intentionally light — the assignment explicitly allows dummy
credentials. Login hits `/auth/login`, which checks against a small seeded
`users` table (or hardcoded list to start) and returns a role + a token the
app attaches to subsequent requests. No signup flow, no password reset, no
real security hardening — this is not the point of the assignment.

Supabase will be wired in via the Supabase MCP connection once available;
until then the backend can run against a `.env`-configured Supabase project
directly through `supabase-js`.

## Data model

**users** — id, role (`admin` | `staff`), employee_id (nullable for admin),
username, password (plain for now, flagged as a limitation), created_at.

**staff** — id, employee_id, name, face_embedding (float array),
enrollment_photo_url, enrolled_at, created_at.

**attendance** — id, staff_id (fk), date, time, selfie_url, latitude,
longitude, match_confidence, created_at.

## API (backend/)

- `POST /auth/login` — dummy credential check, returns role + token.
- `GET /staff` — list all staff (admin).
- `POST /staff` — create staff (name, employee_id).
- `POST /staff/:id/enroll` — upload enrollment photo + embedding.
- `GET /staff/:id` — staff profile, includes embedding (needed by the
  staff's own device for local matching) and attendance history.
- `POST /attendance` — record attendance (staff_id, date, time, selfie,
  lat/long, match_confidence). Server does not re-verify the match; it
  trusts the app because verification already happened on-device before
  this call is made.
- `GET /staff/:id/attendance` — attendance history for one staff member
  (used by the admin profile screen).

## Screens (matches the assignment's required list exactly)

1. Login
2. Admin — Staff List (view, add, open profile)
3. Admin — Add Staff (name + employee ID, then routes into enrollment)
4. Admin — Face Enrolment (camera capture → embedding → upload)
5. Staff — Mark Attendance (camera → detect → match → geo/time → record)
6. Admin — Staff Profile / Attendance History (list of past records with
   selfie, date, time, lat/long)

## Flows

**Enrollment (Admin):**
Add staff (name + ID) → staff record created → Face Enrolment screen opens
→ front camera → capture → ML Kit detects the face → crop/align → TFLite
embedding generated → embedding + photo uploaded to backend.

**Marking attendance (Staff):**
Tap "Mark Attendance" → front camera opens → selfie taken → ML Kit detects
face → embedding generated → compared against the staff's own enrolled
embedding (fetched at login) → if within threshold: capture lat/long +
timestamp → POST to `/attendance`. If not within threshold: show a failure
message, nothing gets written.

**Reviewing attendance (Admin):**
Staff list → tap a staff member → profile screen with their attendance
history (selfie, date, time, lat/long per entry), pulled from
`/staff/:id/attendance`.

## Assumptions and limitations

- No liveness/anti-spoofing check — a printed photo could theoretically
  fool the match. Out of scope for this assignment; worth calling out in
  the README as a known limitation.
- Passwords are stored/checked in plain text since credentials are dummy
  by design. Not production-grade auth.
- Attendance marking requires network connectivity to reach the backend
  (no offline queue/retry). If that turns out to be a real problem in
  testing, revisit.
- One enrolled face per staff member. Re-enrollment overwrites the
  previous embedding rather than versioning it.
- Match threshold for the embedding distance will need actual tuning
  against real test photos once the model is wired in — starting with a
  commonly cited default and adjusting from there.

## Out of scope

Editing staff, editing attendance records, multi-admin accounts,
push notifications, offline-first sync, forgot-password, pagination
(staff/attendance lists are assumed small enough to load in full).

## Plan

**Day 1:** backend skeleton (Express + Supabase schema + the endpointare s
above), Flutter project cleanup, login screen wired to `/auth/login`,
admin staff list + add staff, face enrolment flow end-to-end (capture →
embedding → upload).

**Day 2:** staff mark-attendance flow end-to-end (capture → match →
geo/time → upload), admin attendance history screen, error states and
edge cases, README, build and test the release APK.

## Open items

- Confirm Supabase project access once MCP is connected, then finalize
  actual table creation and storage bucket setup.
- Pick and bundle the exact TFLite face embedding model (need one that's
  small enough to ship in the APK and works reasonably on mid-range
  Android hardware).
