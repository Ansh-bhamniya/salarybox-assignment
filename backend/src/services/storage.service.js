import { randomUUID } from 'crypto';
import { supabase, STORAGE_BUCKETS } from '../config/supabase.js';
import { ApiError } from '../utils/ApiError.js';

async function uploadImage(bucket, file) {
  const path = `${randomUUID()}.jpg`;

  const { error } = await supabase.storage
    .from(bucket)
    .upload(path, file.buffer, {
      contentType: file.mimetype || 'image/jpeg',
      upsert: false,
    });

  if (error) {
    throw new ApiError(500, `Upload failed: ${error.message}`);
  }

  const { data } = supabase.storage.from(bucket).getPublicUrl(path);
  return data.publicUrl;
}

export function uploadEnrollmentPhoto(file) {
  return uploadImage(STORAGE_BUCKETS.enrollmentPhotos, file);
}

export function uploadAttendanceSelfie(file) {
  return uploadImage(STORAGE_BUCKETS.attendanceSelfies, file);
}
