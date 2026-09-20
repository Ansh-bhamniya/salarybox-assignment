import { supabase } from '../config/supabase.js';
import { ApiError } from '../utils/ApiError.js';
import { uploadAttendanceSelfie } from './storage.service.js';

export async function recordAttendance({ staffId, latitude, longitude, matchConfidence, capturedAt, selfieFile }) {
  const { data: staff, error: staffError } = await supabase
    .from('staff')
    .select('id')
    .eq('id', staffId)
    .maybeSingle();

  if (staffError) throw new ApiError(500, staffError.message);
  if (!staff) throw new ApiError(404, 'Staff not found');

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
