import { supabase } from '../config/supabase.js';
import { ApiError } from '../utils/ApiError.js';

/**
 * A staff member's active face templates, newest first. The (large) embedding
 * is only fetched when asked for — most callers just need to know whether the
 * person is enrolled and with which model.
 */
export async function getActiveTemplates(staffId, { withEmbedding = false } = {}) {
  const columns = withEmbedding ? 'id, embedding, model_version, created_at' : 'id, model_version, created_at';

  const { data, error } = await supabase
    .from('face_templates')
    .select(columns)
    .eq('staff_id', staffId)
    .eq('status', 'active')
    .order('created_at', { ascending: false });

  if (error) throw new ApiError(500, error.message);
  return data;
}
