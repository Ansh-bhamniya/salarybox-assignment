import 'dotenv/config';

function required(name) {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required env var: ${name}`);
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
};
