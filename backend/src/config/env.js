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

export const env = {
  port: process.env.PORT || 4000,
  supabaseUrl: required('SUPABASE_URL'),
  supabaseServiceRoleKey: required('SUPABASE_SERVICE_ROLE_KEY'),
  jwtSecret: required('JWT_SECRET'),
  // Assignment explicitly allows dummy credentials. Every enrolled staff
  // member shares this one password rather than having individual accounts.
  // Cosine similarity at or above which a face being enrolled is treated as
  // "already enrolled under another staff member".
  duplicateFaceThreshold: duplicateFaceThreshold(),
  staffDummyPassword: process.env.STAFF_DUMMY_PASSWORD || 'staff123',
};
