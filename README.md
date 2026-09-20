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
2. In the SQL editor, run [`backend/db/schema.sql`](backend/db/schema.sql). It creates the `users`, `staff` and `attendance` tables and seeds the admin user.
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
```

The backend has no automated tests.

## How it works

1. **Admin** logs in → **Staff list** → **Add staff** (name + Employee ID).
2. **Face enrolment:** the front camera captures a face, ML Kit detects and crops it, the TFLite model produces an embedding, and the embedding plus the photo are uploaded.
3. **Staff** logs in with their Employee ID → **Mark attendance:** selfie → face detected → embedding compared (cosine similarity) with the enrolled one, fetched fresh from the backend → if it matches, GPS location and timestamp are captured and the record is uploaded. If it doesn't match, nothing is saved.
4. **Admin** opens a staff profile to see their history: selfie, date, time, and latitude/longitude for each record.

### API

| Method | Path                     | Who            | Purpose                                 |
| ------ | ------------------------ | -------------- | --------------------------------------- |
| POST   | `/auth/login`            | anyone         | Returns a JWT (12 h) and the role       |
| GET    | `/staff`                 | admin          | List staff                              |
| POST   | `/staff`                 | admin          | Create staff                            |
| GET    | `/staff/:id`             | admin, or self | Profile including the face embedding    |
| POST   | `/staff/:id/enroll`      | admin          | Upload enrolment photo + embedding      |
| GET    | `/staff/:id/attendance`  | admin, or self | Attendance history                      |
| POST   | `/attendance`            | staff (self)   | Record attendance (multipart selfie)    |

## Assumptions and limitations

**Auth and security**

- Login is dummy by design, as the assignment allows. Passwords are stored and compared in plain text, and all staff share one password, so anyone who knows an Employee ID can log in as that person. There is no signup, password reset, or rate limiting.
- Uploaded photos are stored in public Supabase buckets. The URLs are random but not access-controlled.
- The server trusts the app's match decision. It does not re-verify the face, so a modified client could submit a fake record.

**Face matching**

- There is **no liveness or anti-spoofing** check. A printed photo or a photo on another screen could pass.
- The match threshold (`0.55` cosine similarity, in `frontend/lib/config/env.dart`) was calibrated offline on public LFW photos, not on real enrolment/selfie pairs from this app. Expect to tune it. Build with `--dart-define=SHOW_MATCH_SCORE=true` to show the raw score on the result screen while calibrating.
- One enrolled face per staff member. Re-enrolling overwrites the previous face.
- Staff can't mark attendance until an admin has enrolled their face.

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
