import * as staffService from '../services/staff.service.js';
import * as attendanceService from '../services/attendance.service.js';
import { ApiError } from '../utils/ApiError.js';
import { parseEmbedding, resolveModelVersion } from '../utils/embedding.js';

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

export async function enroll(req, res) {
  if (!req.file) {
    throw new ApiError(400, 'photo file is required');
  }
  if (!req.body.embedding) {
    throw new ApiError(400, 'embedding is required');
  }

  const modelVersion = resolveModelVersion(req.body.modelVersion);
  const embedding = parseEmbedding(req.body.embedding, modelVersion);

  const staff = await staffService.enrollFace(req.params.id, {
    embedding,
    modelVersion,
    photoFile: req.file,
    actorUserId: req.user.userId,
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
