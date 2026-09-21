# Frontend — file architecture

Layer-first structure: the code is grouped by *what it is* (state, screens,
services, models, reusable widgets), not by feature.

State management: **Bloc / Cubit** (`flutter_bloc`). Most screens are a
simple linear flow (call a service, hold loading/success/error state), so
they use `Cubit`. Theme switching is a real `Bloc` with events
(`HomeThemeBloc`). Dependency injection is `get_it` as a service locator.

```
frontend/
├── lib/
│   ├── main.dart                  # warms SharedPreferences, sets up get_it, runApp
│   ├── app.dart                   # root: providers (AuthCubit, HomeThemeBloc) + MaterialApp.router
│   │
│   ├── bloc/                      # state management — one folder per concern
│   │   ├── auth/                  # auth_cubit, auth_state (app-wide session)
│   │   ├── home_theme/            # home_theme_bloc / _event / _state (light–dark mode)
│   │   ├── staff_home/            # staff's own profile + attendance history
│   │   ├── staff_list/  add_staff/  staff_profile/      # admin screens
│   │   ├── face_capture/  face_enrolment/               # enrolment flow
│   │   └── mark_attendance/                             # staff check-in flow
│   │
│   ├── config/                    # app configuration
│   │   ├── env.dart               # API base URL, face-match threshold, build flags
│   │   ├── di/service_locator.dart    # get_it registrations
│   │   ├── router/app_router.dart     # go_router routes (built from utils/routes.dart) + auth/role redirect guard
│   │   └── theme/
│   │       ├── app_theme.dart     # AppTheme.light() / dark() — the ONLY place colours are defined
│   │       ├── app_spacing.dart   # spacing scale + the 16pt page gutter
│   │       ├── app_radius.dart    # corner radii, defined once (cards/buttons 12, tiles 8, sheet 16, chips pill)
│   │       └── app_icons.dart     # every icon by role — Iconsax (main) + Fluent System Icons; never Icons.x
│   │
│   ├── models/                    # plain data classes (no Flutter/Bloc imports where possible)
│   │   ├── session.dart   staff.dart   attendance_record.dart   face_match_result.dart
│   │
│   ├── screen/                    # one folder per screen
│   │   ├── splash/                # splash_screen.dart: logo for 3 s on every launch, then routes on
│   │   ├── onboarding/            # first-run intro: 3 swipeable pages, shown once
│   │   ├── login/                 # login_screen.dart
│   │   ├── staff_home/            # staff_home_screen.dart (+ staff_home_widgets.dart)
│   │   ├── mark_attendance/       # camera check-in
│   │   ├── face_enrolment/        # admin: 3 auto-captured photos, review, save (re-enrol asks a reason; a duplicate-face warning can be overridden)
│   │   ├── staff_list/  add_staff/  staff_profile/      # admin screens
│   │
│   ├── services/                  # one file per domain — it owns everything about that domain
│   │   ├── auth_service.dart          # log in, keep/restore the session, log out
│   │   ├── staff_service.dart         # list, create, profile, enrol faces (several photos at once), attendance history
│   │   ├── attendance_service.dart    # record a check-in
│   │   ├── face_embedding_service.dart    # ML Kit detection + bundled TFLite model + matching
│   │   ├── camera_capture_controller.dart # front camera: open, stream, capture
│   │   └── face_guidance.dart         # live framing hints from the camera stream
│   │
│   ├── utils/                     # infrastructure and helpers the services build on
│   │   ├── http/                  # api_client (dio + interceptors), api_exception
│   │   ├── helpers/               # secure_storage, theme_mode_helper, onboarding_helper (SharedPreferences)
│   │   ├── go_router_refresh_stream.dart    # re-runs router redirects when auth changes
│   │   ├── routes.dart                      # every screen route path, spelled once (Routes.login, Routes.enrolOf(id)…)
│   │   └── result.dart
│   │
│   └── widgets/                   # reusable UI, used by more than one screen
│       ├── primary_button  loading_overlay  error_view  status_chip  content_width
│       ├── staff_avatar  theme_toggle  app_back_button  app_fab  step_progress
│       └── face_camera_view  camera_status_view          # the shared selfie-camera UI
│
├── assets/images/onboarding_{1,2,3}.png # intro illustrations, shown as supplied (the intro is always light)
├── assets/models/mobilefacenet.tflite   # bundled face-embedding model (see README beside it)
├── test/                          # face matching, theme bloc, widgets
└── pubspec.yaml
```

Dependencies point one way: `screen → bloc → services → models`, with
`widgets`, `config` and `utils` usable from anywhere. Screens read state from
`bloc/`; only `services/` (through `utils/http`) talks to the network, storage or plugins.

## Services: one file per domain

Each domain has one `<domain>_service.dart` that owns everything about it —
the backend calls, turning JSON into models, and the logic around them —
instead of separate api / repository / use-case files. `AuthService`, for
example, logs in, saves and restores the session, and logs out.

Split further only when responsibilities become different enough that
separating them makes the code easier to understand, test and maintain — not
to have "one class per layer". Where that has been true:
`FaceGuidanceAnalyzer` (analysing camera frames) is separate from
`FaceCameraView` (drawing), and the camera plumbing is separate from face
embedding. If a class only forwards to another, merge them.

Services are tested by faking the network with a dio adapter
(`test/helpers/fake_http_adapter.dart`) — no server needed.

## Theme (light / dark)

- **`HomeThemeBloc`** (`bloc/home_theme/`) is the single source of truth. It is
  created once in `app.dart`; `MaterialApp` reads `themeMode` from it and
  rebuilds only when the mode changes
  (`buildWhen: (previous, current) => previous.mode != current.mode`).
- On startup it dispatches `LoadHomeThemeEvent`; `ToggleHomeThemeEvent`
  flips the mode and saves it via `ThemeModeHelper` (`SharedPreferences`).
- **Screens never keep theme state and never choose light/dark colours.**
  Colours are defined once, as full `ColorScheme`s in
  `config/theme/app_theme.dart`, and read with
  `Theme.of(context).colorScheme`. To know whether dark mode is on, use
  `Theme.of(context).brightness == Brightness.dark`.
- The camera screens are deliberately dark in both themes (like a camera
  app); their accent comes from the scheme's `primaryFixedDim`, which does
  not change with brightness.
- The router is created once in `app.dart`'s `State`; building it inside
  `build()` would reset navigation every time the theme changes.

## Dependency injection

`config/di/service_locator.dart` registers `ApiClient` → services →
cubits with `get_it`. Services are lazy singletons; per-screen cubits
(e.g. `AddStaffCubit`) are factories so each screen gets a fresh one;
`AuthCubit` is a singleton provided above the router so every screen can
read the session. `HomeThemeBloc` is created directly in `app.dart`.

## Routing and auth guarding

`config/router/app_router.dart` holds one `go_router` with a `redirect` that
reads `AuthCubit.state`: no session → `/login`; role `staff` → kept off the
admin routes and sent to `/home`; role `admin` → kept off `/home` and
`/attendance`. `refreshListenable` follows `AuthCubit`'s stream, so a
login/logout re-runs the redirect immediately.

Splash: `initialLocation` is `/splash`. `SplashScreen` shows the logo for
`SplashScreen.duration` (3 s), then flips a notifier that the router also
listens to. The redirect keeps the user on `/splash` until that has happened
*and* the session restore has finished (so a slow restore holds the splash a
little longer instead of flashing the login screen); after that the normal
rules below pick the destination — intro, login, or the role's home.

First-run intro: while signed out and the intro hasn't been seen, the router
sends everything to `/onboarding` (`OnboardingHelper.seen`, loaded in `main()`);
finishing or skipping it marks it seen and continues to `/login`. Signed-in
users are kept off `/onboarding`.

## Head-turn (liveness) building blocks

`services/liveness/` holds the logic behind "turn your head left and right".

- `face_observation.dart` — what one analysed camera frame says: how many faces,
  the head angle, how far the nose is off the middle of the eyes, and where the
  face sits.
- `pose_estimator.dart` — turns ML Kit faces into observations. **Direction comes
  from the nose, not from ML Kit's head-angle sign** (which is undocumented): in
  an upright un-mirrored frame, turning to your left moves the nose toward the
  frame's right. The same signal is the anti-photo cue, because a rotated flat
  picture doesn't move its nose against its eyes.
- `liveness_session.dart` — a pure state machine (waiting → hold still → the turns
  in random order → look straight → passed/failed). Turns are judged against the
  person's own straight-ahead baseline, with time-based debouncing, timeouts,
  and specific failures (wrong direction, second face, a face that jumped, angle
  and nose disagreeing).
- `liveness_analyzer.dart` — runs ML Kit (accurate mode, landmarks, tracking) on
  the camera stream: about 28 frames a second on an iPhone.
- `direction_test.dart` — a guided check of which way is "left" on a device.

Measured on an iPhone: the stream arrives mirrored, and face boxes are relative to
the upright 720×1280 frame (Android hands over the sideways sensor buffer, so its
width and height swap: `services/camera_input_image.dart`).

## Matching

Attendance matches the fresh selfie against every template of
`Env.faceModelVersion` and takes the best score (`FaceEmbeddingService.
compareToAny`). Templates from another model version are ignored, and a person
who only has those is told to ask their admin to re-enrol them. `Staff` carries all
of a person's active templates, and backend errors carry an optional `code` and
`details` (`ApiException`).

## Enrolment

Nobody presses a shutter. The live stream is analysed and `EnrolmentPoseGuide`
decides when each of the three photos (straight, a little to the left, a little to
the right) is taken: the face in the oval and the pose held steady for 1.5 s
(straight) or 1.2 s (turned), with a short "Photo saved" pause between photos.
`PoseCameraView` shows the oval (a ring fills while holding), the prompt, a turn
line (`TurnMeter`: a bar grows from the middle toward the side the head is turned
to, the green zone is where this photo is taken from) and a one-line message.

`FaceCaptureCubit` takes the photo when told to, checks it again (head angle, and
that the face is inside the oval) and retakes by itself if the person had moved,
then checks each later photo against the first (`Env.enrolmentMinSimilarity`).
`FaceEnrolmentCubit` uploads them together; if the backend answers
`duplicate_face` the screen shows who the face resembles and lets the admin enrol
anyway with a reason. Re-enrolling (`Routes.enrolOf(id, reEnrol: true)`) asks for
a reason first.

## Networking

`utils/http/api_client.dart` wraps `dio` with an interceptor that attaches
`Authorization: Bearer <token>` and one that maps non-2xx responses into
`ApiException`, matching the backend's `{ error: message }` shape.

## Mapping to the assignment's required screens

| Required screen | File |
|---|---|
| Login | `screen/login/login_screen.dart` |
| Admin — Staff List | `screen/staff_list/staff_list_screen.dart` |
| Admin — Add Staff | `screen/add_staff/add_staff_screen.dart` |
| Admin — Face Enrolment | `screen/face_enrolment/face_enrolment_screen.dart` |
| Staff — Mark Attendance | `screen/mark_attendance/mark_attendance_screen.dart` (opened from `screen/staff_home/`) |
| Admin — Staff Profile / Attendance History | `screen/staff_profile/staff_profile_screen.dart` |
