import { supabase } from '../config/supabase.js';
import { ApiError } from '../utils/ApiError.js';
import { uploadEnrollmentPhoto } from './storage.service.js';
import { env } from '../config/env.js';
import { findDuplicateFaces, getActiveTemplates } from './face-template.service.js';

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

  // The staff member's own device matches faces locally, so it needs every
  // active template. `face_embedding` (the first one) is what app builds that
  // predate multiple templates read.
  const templates = await getActiveTemplates(id, { withEmbedding: true });
  return {
    ...data,
    face_embedding: templates[0]?.embedding ?? null,
    face_templates: templates.map(({ id: templateId, embedding, model_version }) => ({
      id: templateId,
      embedding,
      model_version,
    })),
    enrolled: templates.length > 0,
  };
}

/**
 * Enrol (or re-enrol) a person from one or more captures. Refuses a face that
 * already belongs to another staff member unless the admin explicitly
 * overrides it with a reason, and records the override in the audit log.
 */
export async function enrollFaces(
  id,
  { embeddings, modelVersion, photoFiles, actorUserId, reason, allowDuplicate },
) {
  await assertStaffExists(id);

  const duplicates = await findDuplicateFaces(id, embeddings, modelVersion, env.duplicateFaceThreshold);
  if (duplicates.length > 0) {
    if (!allowDuplicate) {
      throw new ApiError(409, 'This face looks like an already enrolled staff member', 'duplicate_face', {
        matches: duplicates,
      });
    }
    if (!reason) {
      throw new ApiError(400, 'A reason is required to enrol a face that matches another staff member', 'reason_required');
    }
  }

  const photoUrls = await Promise.all(photoFiles.map((file) => uploadEnrollmentPhoto(file)));

  // One atomic step in Postgres: revoke the previous templates, add these, and
  // write the audit entry.
  const { data, error } = await supabase.rpc('enrol_faces', {
    p_staff_id: id,
    p_embeddings: embeddings,
    p_model_version: modelVersion,
    p_photo_urls: photoUrls,
    p_actor: actorUserId ?? null,
    p_reason: reason ?? null,
    p_details: duplicates.length > 0 ? { duplicate_override: duplicates } : {},
  });

  if (error) {
    if (error.message?.includes('staff_not_found')) throw new ApiError(404, 'Staff not found');
    if (error.message?.includes('invalid_templates')) throw new ApiError(400, 'Invalid set of face captures');
    throw new ApiError(500, error.message);
  }

  const staff = Array.isArray(data) ? data[0] : data;
  return { ...staff, enrolled: true, templates: embeddings.length };
}
