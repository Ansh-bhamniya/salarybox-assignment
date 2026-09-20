import { createClient } from '@supabase/supabase-js';
import { env } from './env.js';

export const supabase = createClient(env.supabaseUrl, env.supabaseServiceRoleKey, {
  auth: { persistSession: false },
});

export const STORAGE_BUCKETS = {
  enrollmentPhotos: 'enrollment-photos',
  attendanceSelfies: 'attendance-selfies',
};
