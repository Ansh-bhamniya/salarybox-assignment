import { supabase } from '../config/supabase.js';
import { ApiError } from '../utils/ApiError.js';
import { uploadEnrollmentPhoto } from './storage.service.js';

export async function listStaff() {
  const { data, error } = await supabase
    .from('staff')
    .select('id, employee_id, name, enrollment_photo_url, enrolled_at, created_at')
    .order('created_at', { ascending: false });

  if (error) throw new ApiError(500, error.message);
  return data;
}

export async function createStaff({ name, employeeId }) {
  const { data, error } = await supabase
    .from('staff')
    .insert({ name, employee_id: employeeId })
    .select()
    .single();

  if (error) {
    if (error.code === '23505') {
      throw new ApiError(409, 'Employee ID already exists');
    }
    throw new ApiError(500, error.message);
  }
  return data;
}

export async function getStaffById(id) {
  const { data, error } = await supabase
    .from('staff')
    .select('id, employee_id, name, face_embedding, enrollment_photo_url, enrolled_at, created_at')
    .eq('id', id)
    .maybeSingle();

  if (error) throw new ApiError(500, error.message);
  if (!data) throw new ApiError(404, 'Staff not found');
  return data;
}

export async function enrollFace(id, { embedding, photoFile }) {
  await getStaffById(id); // 404s if missing

  const photoUrl = await uploadEnrollmentPhoto(photoFile);

  const { data, error } = await supabase
    .from('staff')
    .update({
      face_embedding: embedding,
      enrollment_photo_url: photoUrl,
      enrolled_at: new Date().toISOString(),
    })
    .eq('id', id)
    .select()
    .single();

  if (error) throw new ApiError(500, error.message);
  return data;
}
