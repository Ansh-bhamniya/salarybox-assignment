# SalaryBox Attendance App

A two-role attendance app. An **admin** adds staff and enrols their faces; **staff** mark their own attendance with a selfie that must match their enrolled face. Location and time are captured automatically at the moment of marking.

- **Frontend** — Flutter (Android), in `frontend/`
- **Backend** — Node.js + Express API, in `backend/`, deployed on Vercel
- **Data** — Supabase (Postgres for records, Storage for photos)

Face detection (Google ML Kit) and face matching (bundled MobileFaceNet TFLite model) both run **on the phone**. The backend never sees a photo and decides who it is — it stores what the app already decided. See [`PRD.md`](PRD.md) for the full design.

```
Flutter app ──REST/JSON──▶ Express API (Vercel) ──supabase-js──▶ Supabase (Postgres + Storage)
```

## Demo credentials

| Role  | Username                   | Password   |
| ----- | -------------------------- | ---------- |
| Admin | `admin`                    | `admin123` |
| Staff | the staff member's **Employee ID** | `staff123` |

- The admin account is seeded by `backend/db/schema.sql`.
- There is no seeded staff. Log in as admin, add a staff member (name + Employee ID), enrol their face, then log in on the same or another device with that Employee ID and `staff123`.
- Every staff member shares the one password (`STAFF_DUMMY_PASSWORD`, defaults to `staff123`).

## Live backend

`https://salarybox-backend.vercel.app` — check it with `GET /health` (returns `{"ok":true}`).

The app's default API URL (`frontend/lib/config/env.dart`) already points here, so you can run or build the app without running the backend yourself.

## How to run

### Prerequisites

- Flutter 3.41+ (Dart 3.11+) with the Android SDK, and an Android emulator or a physical Android device
- A recent Node.js (developed on v23) — only if you want to run the backend locally
- A Supabase project (only if you want your own backend — see below)

### 1. Run the app against the live backend (fastest)

```bash
cd frontend
flutter pub get
flutter run
```

Log in with the demo credentials above. The camera and location permissions are requested on first use, so use a device or emulator with a working camera (and a location set, on the emulator).

### 2. Build a release APK

```bash
cd frontend
flutter build apk --release
```

Output: `frontend/build/app/outputs/flutter-apk/app-release.apk`. Copy it to a phone and install it. It is signed with the debug key, which is fine for sideloading.

To target a different backend, override the URL at build or run time:

```bash
flutter build apk --release --dart-define=API_BASE_URL=https://your-backend.example.com
```

### 3. Run your own backend (optional)

**a. Set up Supabase**

1. Create a Supabase project.
2. In the SQL editor, run [`backend/db/schema.sql`](backend/db/schema.sql). It enables the `vector` (pgvector) extension, creates the tables (`users`, `staff`, `face_templates`, `attendance`, `attendance_attempts`, `audit_log`) and the enrolment functions, turns on row level security, and seeds the admin user. It is safe to re-run, so run it again to upgrade an existing project — it also backfills existing enrolments into `face_templates`.
3. In Storage, create two **public** buckets: `enrollment-photos` and `attendance-selfies`.

**b. Configure and start the API**

```bash
cd backend
cp .env.example .env      # then fill in the values below
npm install
npm run dev               # http://localhost:4000
```

| Variable                    | Required | Notes                                              |
| --------------------------- | -------- | -------------------------------------------------- |
| `SUPABASE_URL`              | yes      | Project URL from Supabase settings                 |
| `SUPABASE_SERVICE_ROLE_KEY` | yes      | Server-side only — never put this in the app       |
| `JWT_SECRET`                | yes      | Any long random string                             |
| `STAFF_DUMMY_PASSWORD`      | no       | Shared staff password, defaults to `staff123`      |
| `DUPLICATE_FACE_THRESHOLD`  | no       | Cosine similarity (0–1] at which a face being enrolled counts as "already enrolled under someone else"; defaults to `0.6` |
| `LIVENESS_REQUIRED`         | no       | `true` refuses attendance that doesn't carry a passed head-turn check (409 `liveness_required`). Off by default so older app builds keep working |
| `ATTEMPTS_PER_HOUR`         | no       | How many failed-check reports one staff member may log per hour; defaults to `60` |
| `PORT`                      | no       | Defaults to `4000`                                 |

`.env.example` also lists `DATABASE_PASSWORD`; the server does not read it.

**c. Point the app at it**

From the Android emulator, `10.0.2.2` is the host machine's localhost:

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:4000
```

A physical device needs your computer's LAN address instead. Plain `http://` may be blocked by Android's cleartext-traffic policy; if the app can't reach a local backend, either use an `https://` URL or allow cleartext traffic in the debug manifest.

### 4. Deploy the backend to Vercel

The project is set up for Vercel: `backend/api/index.js` exports the Express app as a serverless function and `backend/vercel.json` routes every path to it.

1. Import the repo in Vercel and set **Root Directory** to `backend`.
2. Add `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` and `JWT_SECRET` as environment variables.
3. Deploy. Pushes to `main` redeploy automatically.

Use the project's production domain (`<project>.vercel.app`) in the app, not a per-deployment URL — those can sit behind Vercel's login wall.

### 5. Tests and analysis

```bash
cd frontend
flutter analyze
flutter test

cd ../backend
npm test
```

The backend tests cover input validation and error responses; they don't need a database. The API's database paths (enrolment, the not-enrolled refusal) are not covered by automated tests.

## How it works

1. **Admin** logs in → **Staff list** → **Add staff** (name + Employee ID).
2. **Face enrolment:** the front camera takes three photos (straight, slightly left, slightly right). For each, ML Kit detects and crops the face and the TFLite model produces an embedding; the photos and embeddings are uploaded together. If the face already belongs to another staff member the server refuses, and the admin can override with a reason that is audited.
3. **Staff** logs in with their Employee ID → **Mark attendance:** there is no shutter. The person turns their head to one side, then the other (in a random order each time), then looks straight, while the live camera is watched. Frames from that check itself are kept — before the turns, at each turn, and at the end. The final straight frame must match the person's enrolled faces (fetched fresh from the backend; best score across their templates), and the other frames must be the same face as it, so whoever did the turns is who gets recorded. Only then are GPS location and time captured and the record uploaded, with the final frame as the photo and a summary of what the check saw. A check that fails can be retried with a new challenge as many times as needed; there is no lockout. Every failed check is reported to the backend.
4. **Admin** opens a staff profile to see their history: selfie, date, time, and latitude/longitude for each record.

### API

| Method | Path                     | Who            | Purpose                                 |
| ------ | ------------------------ | -------------- | --------------------------------------- |
| POST   | `/auth/login`            | anyone         | Returns a JWT (12 h) and the role       |
| GET    | `/staff`                 | admin          | List staff (each with an `enrolled` flag) |
| POST   | `/staff`                 | admin          | Create staff                            |
| GET    | `/staff/:id`             | admin, or self | Profile including the active face templates |
| POST   | `/staff/:id/enroll`      | admin          | Upload 1–5 captures: `photos` + `embeddings` (+ `modelVersion`, `reason`, `allowDuplicate`). 409 `duplicate_face` if the face matches another staff member. The original single `photo` + `embedding` form is still accepted |
| GET    | `/staff/:id/attendance`  | admin, or self | Attendance history                      |
| POST   | `/attendance`            | staff (self)   | Record attendance (multipart selfie, plus an optional `liveness` JSON: what the head-turn check saw). 409 `not_enrolled` if the person has no active face; 409 `liveness_required` if the server requires the check and none was sent |
| POST   | `/attendance/attempts`   | staff (self)   | Report a failed check: `outcome` (`liveness_failed` or `no_match`) and an optional short `reason`. Capped per hour |

## Assumptions and limitations

**Auth and security**

- Login is dummy by design, as the assignment allows. Passwords are stored and compared in plain text, and all staff share one password, so anyone who knows an Employee ID can log in as that person. There is no signup, password reset, or rate limiting.
- Uploaded photos are stored in public Supabase buckets. The URLs are random but not access-controlled.
- The server trusts the app's match decision. It does not re-verify the face, so a modified client could submit a fake record.

**Face matching**

- Attendance needs a **head-turn check** (turn left and right in a random order, then look straight), which a still photo — printed or on another screen — cannot pass, and neither can a photo that is rotated like a head (the nose does not move against the eyes). It does **not** stop a video replay of the person turning, a 3D mask, or a modified app. The check runs on the phone: the server stores what the app says it saw (`attendance.liveness`) and can require it (`LIVENESS_REQUIRED`), but cannot verify the claim. Stopping those needs a passive anti-spoof model and server-side verification with app attestation, which are not built.
- The head-turn check was measured and tuned on an **iPhone only**. The direction rule comes from face geometry so it should carry over, but Android's frame format and mirroring have not been verified on a device. The thresholds are provisional until tested against real attacks.
- The match threshold (`0.55` cosine similarity, in `frontend/lib/config/env.dart`) was calibrated offline on public LFW photos, not on real enrolment/selfie pairs from this app. Expect to tune it. Build with `--dart-define=SHOW_MATCH_SCORE=true` to show the raw score on the result screen while calibrating.
- Each person is enrolled from three photos and matched against all of them (best score wins). Re-enrolling replaces the whole set; the old templates are kept, marked revoked, with a reason and an audit entry. Templates never update themselves from later selfies, and staff are not notified when they are re-enrolled.
- Duplicate-face detection compares a new enrolment with everyone else's active templates (pgvector, same face-model version only). Its threshold (`DUPLICATE_FACE_THRESHOLD`, default 0.6) is a provisional guess until calibrated on real photos, so it can miss a match or flag a lookalike; an admin can override a flag with a reason. Two enrolments of the same face at the very same moment could both slip through.
- Staff can't mark attendance until an admin has enrolled their face. The app disables the button, and the server also refuses the record (409 `not_enrolled`) and logs the attempt.

**Location and time**

- Location is a single GPS reading (high accuracy, 15 s timeout) taken when the face matches. There is no geofence, and mock or spoofed locations are not detected. Location services must be on.
- The date and time saved in the database are the capture moment in **UTC**. The app displays them in the device's local time, but the raw `date` column can differ from the local date near midnight.
- The backend does not limit attendance to once per day; repeated marks create repeated records.

**Platform and infrastructure**

- Attendance marking needs a network connection. There is no offline queue or retry.
- Built and tested for Android. The iOS project exists but has not been verified.
- Vercel rejects request bodies over 4.5 MB (the API itself allows 8 MB). Selfies are JPEG-encoded by the app and should be well below this, but their size hasn't been measured — very large images would fail.
- The release APK is signed with the debug key, not a Play Store signing key.

**Out of scope**

Editing or deleting staff, editing attendance records, multiple admin accounts, push notifications, offline sync, forgot-password, and pagination (lists are loaded in full).
