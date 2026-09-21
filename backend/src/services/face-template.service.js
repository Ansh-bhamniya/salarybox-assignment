import { supabase } from '../config/supabase.js';
import { ApiError } from '../utils/ApiError.js';

/**
 * A staff member's active face templates: newest enrolment first, and within
 * one enrolment in capture order (the frontal shot first). The (large)
 * embedding is only fetched when asked for — most callers just need to know
 * whether the person is enrolled and with which model.
 */
export async function getActiveTemplates(staffId, { withEmbedding = false } = {}) {
  const columns = withEmbedding
    ? 'id, embedding, model_version, shot_index, created_at'
    : 'id, model_version, shot_index, created_at';

  const { data, error } = await supabase
    .from('face_templates')
    .select(columns)
    .eq('staff_id', staffId)
    .eq('status', 'active')
    .order('created_at', { ascending: false })
    .order('shot_index', { ascending: true });

  if (error) throw new ApiError(500, error.message);
  return data;
}

/**
 * Other staff whose active faces look like the given embeddings (cosine
 * similarity at or above `threshold`), best match first. The person's own
 * templates are ignored, so re-enrolling yourself is never a "duplicate".
 */
export async function findDuplicateFaces(staffId, embeddings, modelVersion, threshold) {
  const { data, error } = await supabase.rpc('find_duplicate_face', {
    p_staff_id: staffId,
    p_embeddings: embeddings,
    p_model_version: modelVersion,
    p_threshold: threshold,
  });

  if (error) throw new ApiError(500, error.message);
  return data.map((row) => ({
    staffId: row.staff_id,
    employeeId: row.employee_id,
    name: row.name,
    similarity: row.similarity,
  }));
}
