import 'dotenv/config';

function required(name) {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required env var: ${name}`);
  }
  return value;
}

function duplicateFaceThreshold() {
  const value = Number(process.env.DUPLICATE_FACE_THRESHOLD ?? 0.6);
  if (!(value > 0 && value <= 1)) {
    throw new Error('DUPLICATE_FACE_THRESHOLD must be a number in (0, 1]');
  }
  return value;
}

function positiveInt(name, fallback) {
  const value = Number(process.env[name] ?? fallback);
  if (!Number.isInteger(value) || value < 1) {
    throw new Error(`${name} must be a whole number of at least 1`);
  }
  return value;
}

export const env = {
  port: process.env.PORT || 4000,
  supabaseUrl: required('SUPABASE_URL'),
  supabaseServiceRoleKey: required('SUPABASE_SERVICE_ROLE_KEY'),
  jwtSecret: required('JWT_SECRET'),
  // Assignment explicitly allows dummy credentials. Every enrolled staff
  // member shares this one password rather than having individual accounts.
  staffDummyPassword: process.env.STAFF_DUMMY_PASSWORD || 'staff123',
  // Cosine similarity at or above which a face being enrolled is treated as
  // "already enrolled under another staff member".
  duplicateFaceThreshold: duplicateFaceThreshold(),
  // When on, attendance without a passed head-turn check is refused. Off by
  // default so app builds that predate the check keep working; turn it on once
  // everyone has updated. (The server cannot verify the claim: a modified app
  // could forge it. It is an audit trail, not a defence.)
  livenessRequired: process.env.LIVENESS_REQUIRED === 'true',
  // How many failed-check reports one staff member may log per hour.
  attemptsPerHour: positiveInt('ATTEMPTS_PER_HOUR', 60),
};
