# Backend — file architecture

Express API sitting between the Flutter app and Supabase. Thin layer: routes
parse the request, controllers orchestrate, services do the actual Supabase
work. No ORM — using `@supabase/supabase-js` directly since the schema is
small (3 tables) and doesn't need one.

```
backend/
├── src/
│   ├── config/
│   │   ├── env.js            # reads + validates process.env, exported as one object
│   │   └── supabase.js       # supabase-js client (service role key)
│   │
│   ├── middleware/
│   │   ├── auth.js           # verifies bearer token, attaches req.user
│   │   ├── upload.js         # multer memory storage config for image uploads
│   │   └── errorHandler.js   # catches thrown ApiError / unexpected errors, formats response
│   │
│   ├── routes/
│   │   ├── auth.routes.js        # POST /auth/login
│   │   ├── staff.routes.js       # GET/POST /staff, GET /staff/:id, POST /staff/:id/enroll,
│   │   │                         # GET /staff/:id/attendance
│   │   └── attendance.routes.js  # POST /attendance
│   │
│   ├── controllers/
│   │   ├── auth.controller.js
│   │   ├── staff.controller.js
│   │   └── attendance.controller.js
│   │
│   ├── services/
│   │   ├── auth.service.js       # dummy credential check, token issuing
│   │   ├── staff.service.js      # staff CRUD + embedding read/write against Postgres
│   │   ├── attendance.service.js # insert/list attendance rows
│   │   └── storage.service.js    # uploads selfie/enrollment images to Supabase Storage
│   │
│   ├── utils/
│   │   ├── ApiError.js       # thin error class carrying an http status
│   │   └── asyncHandler.js   # wraps async route handlers so thrown errors reach errorHandler
│   │
│   ├── app.js                 # express app: middleware, route mounting, error handler
│   └── server.js              # entry point — starts http server on PORT
│
├── db/
│   └── schema.sql             # Postgres schema for the 3 tables (run once against Supabase)
│
├── .env.example
├── .gitignore
├── package.json
└── README.md                  # setup + run instructions (written once backend is functional)
```

## Request flow example

`POST /staff/:id/enroll` (multipart: `photo` file + `embedding` JSON field)

1. `routes/staff.routes.js` — matches the route, runs `upload.single('photo')`
   then `staffController.enroll`.
2. `controllers/staff.controller.js` — pulls `id` from params, `embedding`
   from body, `req.file` from multer; calls `staffService.enroll(...)`.
3. `services/staff.service.js` — calls `storageService.uploadEnrollmentPhoto`
   to push the image to Supabase Storage and get back a public URL, then
   updates the `staff` row (`face_embedding`, `enrollment_photo_url`,
   `enrolled_at`) via `supabase-js`.
4. Controller sends the updated staff record back as JSON.
5. Anything thrown along the way (bad id, Supabase error) bubbles up through
   `asyncHandler` to `errorHandler`, which turns it into a consistent
   `{ error: message }` JSON response with the right status code.

## Auth

Login is intentionally dummy per the assignment — no signup, no password
hashing. `auth.service.js` checks username/password against the `users`
table, and on success signs a short-lived JWT containing `{ userId, role,
staffId }`. `middleware/auth.js` verifies that token on every route except
`/auth/login` and attaches the payload to `req.user`. Staff-only routes
check `req.user.role`.

## Env vars (`.env`)

```
PORT=4000
SUPABASE_URL=
SUPABASE_SERVICE_ROLE_KEY=
JWT_SECRET=
```

## Why this shape

- Routes/controllers/services split keeps Supabase calls out of route
  files, so swapping storage/db details later doesn't touch the HTTP layer.
- No repository/DAO layer on top of `services/` — three tables and a
  handful of queries doesn't justify another abstraction layer.
- `storage.service.js` is separate from `staff.service.js` /
  `attendance.service.js` because both enrollment photos and attendance
  selfies go through it — one place to change if the storage provider or
  bucket structure changes later.
