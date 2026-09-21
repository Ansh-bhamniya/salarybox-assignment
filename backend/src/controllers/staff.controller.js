import * as staffService from '../services/staff.service.js';
import * as attendanceService from '../services/attendance.service.js';
import { ApiError } from '../utils/ApiError.js';
import { parseEmbedding, parseEmbeddingSet, resolveModelVersion } from '../utils/embedding.js';

export async function list(req, res) {
  const staff = await staffService.listStaff();
  res.json(staff);
}

export async function create(req, res) {
  const { name, employeeId } = req.body;
  if (!name || !employeeId) {
    throw new ApiError(400, 'name and employeeId are required');
  }

  const staff = await staffService.createStaff({ name, employeeId });
  res.status(201).json(staff);
}

export async function getById(req, res) {
  if (req.user.role === 'staff' && req.user.staffId !== req.params.id) {
    throw new ApiError(403, 'Cannot view another staff member');
  }
  const staff = await staffService.getStaffById(req.params.id);
  res.json(staff);
}

export async function remove(req, res) {
  await staffService.deleteStaff(req.params.id, { actorUserId: req.user.userId });
  res.status(204).end();
}

const MAX_REASON_LENGTH = 200;

/**
 * Two request shapes are accepted: the current one (`photos` files + an
 * `embeddings` JSON array, one entry per capture) and the original single
 * capture one (`photo` + `embedding`) that older app builds still send.
 */
export async function enroll(req, res) {
  const files = req.files ?? {};
  const singlePhoto = files.photo ?? [];
  const manyPhotos = files.photos ?? [];
  if (singlePhoto.length > 0 && manyPhotos.length > 0) {
    throw new ApiError(400, 'send either photo or photos, not both');
  }
  const photoFiles = manyPhotos.length > 0 ? manyPhotos : singlePhoto;
  if (photoFiles.length === 0) {
    throw new ApiError(400, 'photo file is required');
  }

  const modelVersion = resolveModelVersion(req.body.modelVersion);
  let embeddings;
  if (req.body.embeddings !== undefined) {
    embeddings = parseEmbeddingSet(req.body.embeddings, modelVersion);
  } else if (req.body.embedding) {
    embeddings = [parseEmbedding(req.body.embedding, modelVersion)];
  } else {
    throw new ApiError(400, 'embeddings is required');
  }
  if (embeddings.length !== photoFiles.length) {
    throw new ApiError(400, 'each embedding needs a matching photo');
  }

  const reason = typeof req.body.reason === 'string' ? req.body.reason.trim() : '';
  if (reason.length > MAX_REASON_LENGTH) {
    throw new ApiError(400, `reason must be at most ${MAX_REASON_LENGTH} characters`);
  }

  const staff = await staffService.enrollFaces(req.params.id, {
    embeddings,
    modelVersion,
    photoFiles,
    actorUserId: req.user.userId,
    reason: reason || undefined,
    allowDuplicate: req.body.allowDuplicate === 'true',
  });
  res.json(staff);
}

export async function attendanceHistory(req, res) {
  if (req.user.role === 'staff' && req.user.staffId !== req.params.id) {
    throw new ApiError(403, 'Cannot view another staff member');
  }
  await staffService.assertStaffExists(req.params.id);
  const records = await attendanceService.listAttendanceForStaff(req.params.id);
  res.json(records);
}
