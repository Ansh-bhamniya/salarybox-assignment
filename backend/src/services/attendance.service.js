import { supabase } from '../config/supabase.js';
import { ApiError } from '../utils/ApiError.js';
import { uploadAttendanceSelfie } from './storage.service.js';
import { getActiveTemplates } from './face-template.service.js';

// Best effort: a failure to write the log must never change the response.
async function logRefusedAttempt(staffId, outcome) {
  const { error } = await supabase.from('attendance_attempts').insert({ staff_id: staffId, outcome });
  if (error) console.error(`Could not log ${outcome} attempt:`, error.message);
}

export async function recordAttendance({ staffId, latitude, longitude, matchConfidence, capturedAt, selfieFile }) {
  const { data: staff, error: staffError } = await supabase
    .from('staff')
    .select('id')
    .eq('id', staffId)
    .maybeSingle();

  if (staffError) throw new ApiError(500, staffError.message);
  if (!staff) throw new ApiError(404, 'Staff not found');

  // Attendance is a face check, so it can't be recorded for someone with no
  // enrolled face. Refuse before uploading anything.
  const templates = await getActiveTemplates(staffId);
  if (templates.length === 0) {
    await logRefusedAttempt(staffId, 'not_enrolled');
    throw new ApiError(409, 'Your face is not enrolled yet. Ask your admin to enrol it.', 'not_enrolled');
  }

  const selfieUrl = await uploadAttendanceSelfie(selfieFile);
  // Prefer the timestamp the app captured at the moment of the selfie over
  // the time this request happens to land on the server.
  const now = capturedAt ? new Date(capturedAt) : new Date();

  const { data, error } = await supabase
    .from('attendance')
    .insert({
      staff_id: staffId,
      date: now.toISOString().slice(0, 10),
      time: now.toISOString().slice(11, 19),
      selfie_url: selfieUrl,
      latitude,
      longitude,
      match_confidence: matchConfidence,
      model_version: templates[0].model_version,
    })
    .select()
    .single();

  if (error) throw new ApiError(500, error.message);
  return data;
}

export async function listAttendanceForStaff(staffId) {
  const { data, error } = await supabase
    .from('attendance')
    .select('id, date, time, selfie_url, latitude, longitude, match_confidence, created_at')
    .eq('staff_id', staffId)
    .order('created_at', { ascending: false });

  if (error) throw new ApiError(500, error.message);
  return data;
}
