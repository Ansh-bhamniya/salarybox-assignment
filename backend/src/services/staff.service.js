import { supabase } from '../config/supabase.js';
import { ApiError } from '../utils/ApiError.js';
import { uploadEnrollmentPhoto } from './storage.service.js';
import { getActiveTemplates } from './face-template.service.js';

const STAFF_COLUMNS = 'id, employee_id, name, enrollment_photo_url, enrolled_at, created_at';

// "Enrolled" means "has an active face template" — not merely "has a photo".
export async function listStaff() {
  const { data, error } = await supabase
    .from('staff')
    .select(`${STAFF_COLUMNS}, face_templates(id)`)
    .eq('face_templates.status', 'active')
    .order('created_at', { ascending: false });

  if (error) throw new ApiError(500, error.message);
  return data.map(({ face_templates: templates, ...staff }) => ({ ...staff, enrolled: templates.length > 0 }));
}

export async function createStaff({ name, employeeId }) {
  const { data, error } = await supabase
    .from('staff')
    .insert({ name, employee_id: employeeId })
    .select(STAFF_COLUMNS)
    .single();

  if (error) {
    if (error.code === '23505') {
      throw new ApiError(409, 'Employee ID already exists');
    }
    throw new ApiError(500, error.message);
  }
  return { ...data, enrolled: false };
}

/** 404s if there is no such staff member. */
export async function assertStaffExists(id) {
  const { data, error } = await supabase.from('staff').select('id').eq('id', id).maybeSingle();

  if (error) throw new ApiError(500, error.message);
  if (!data) throw new ApiError(404, 'Staff not found');
}

export async function getStaffById(id) {
  const { data, error } = await supabase.from('staff').select(STAFF_COLUMNS).eq('id', id).maybeSingle();

  if (error) throw new ApiError(500, error.message);
  if (!data) throw new ApiError(404, 'Staff not found');

  // The staff member's own device matches faces locally, so it needs the
  // current template's embedding.
  const templates = await getActiveTemplates(id, { withEmbedding: true });
  return { ...data, face_embedding: templates[0]?.embedding ?? null, enrolled: templates.length > 0 };
}

export async function enrollFace(id, { embedding, modelVersion, photoFile, actorUserId }) {
  await assertStaffExists(id);

  const photoUrl = await uploadEnrollmentPhoto(photoFile);

  // One atomic step in Postgres: revoke the previous templates, add this one,
  // and write the audit entry.
  const { data, error } = await supabase.rpc('enrol_face', {
    p_staff_id: id,
    p_embedding: embedding,
    p_model_version: modelVersion,
    p_photo_url: photoUrl,
    p_actor: actorUserId ?? null,
  });

  if (error) {
    if (error.message?.includes('staff_not_found')) throw new ApiError(404, 'Staff not found');
    throw new ApiError(500, error.message);
  }

  const staff = Array.isArray(data) ? data[0] : data;
  return { ...staff, enrolled: true };
}
