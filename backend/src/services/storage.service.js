import { randomUUID } from 'crypto';
import { supabase, STORAGE_BUCKETS } from '../config/supabase.js';
import { ApiError } from '../utils/ApiError.js';
import { storagePathsByBucket } from '../utils/storage-paths.js';

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

/**
 * Deletes the stored pictures behind these public URLs. Best effort: the records
 * they belonged to are already gone, so a failure here only leaves an orphaned
 * file, and must not turn a successful delete into an error.
 */
export async function removeImagesByUrl(urls) {
  const grouped = storagePathsByBucket(urls, Object.values(STORAGE_BUCKETS));
  for (const [bucket, paths] of Object.entries(grouped)) {
    try {
      const { error } = await supabase.storage.from(bucket).remove(paths);
      if (error) console.error(`Could not remove ${paths.length} file(s) from ${bucket}: ${error.message}`);
    } catch (err) {
      console.error(`Could not remove ${paths.length} file(s) from ${bucket}: ${err.message}`);
    }
  }
}
