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
│   │   ├── router/app_router.dart     # go_router routes + auth/role redirect guard
│   │   └── theme/
│   │       ├── app_theme.dart     # AppTheme.light() / dark() — the ONLY place colours are defined
│   │       ├── app_spacing.dart   # spacing scale + the 16pt page gutter
│   │       └── app_radius.dart    # corner radii, defined once (cards/buttons 12, tiles 8, sheet 16, chips pill)
│   │
│   ├── models/                    # plain data classes (no Flutter/Bloc imports where possible)
│   │   ├── session.dart   staff.dart   attendance_record.dart   face_match_result.dart
│   │
│   ├── screen/                    # one folder per screen
│   │   ├── login/                 # login_screen.dart
│   │   ├── staff_home/            # staff_home_screen.dart (+ staff_home_widgets.dart)
│   │   ├── mark_attendance/       # camera check-in
│   │   ├── face_enrolment/        # admin: capture + save a face
│   │   ├── staff_list/  add_staff/  staff_profile/      # admin screens
│   │
│   ├── services/                  # one file per domain — it owns everything about that domain
│   │   ├── auth_service.dart          # log in, keep/restore the session, log out
│   │   ├── staff_service.dart         # list, create, profile, enrol a face, attendance history
│   │   ├── attendance_service.dart    # record a check-in
│   │   ├── face_embedding_service.dart    # ML Kit detection + bundled TFLite model + matching
│   │   ├── camera_capture_controller.dart # front camera: open, stream, capture
│   │   └── face_guidance.dart         # live framing hints from the camera stream
│   │
│   ├── utils/                     # infrastructure and helpers the services build on
│   │   ├── http/                  # api_client (dio + interceptors), api_exception
│   │   ├── helpers/               # secure_storage, theme_mode_helper (SharedPreferences)
│   │   ├── go_router_refresh_stream.dart    # re-runs router redirects when auth changes
│   │   └── result.dart
│   │
│   └── widgets/                   # reusable UI, used by more than one screen
│       ├── primary_button  loading_overlay  error_view  status_chip  content_width
│       ├── staff_avatar  theme_toggle
│       └── face_camera_view  camera_status_view          # the shared selfie-camera UI
│
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
