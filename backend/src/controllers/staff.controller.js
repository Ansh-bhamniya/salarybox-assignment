import * as staffService from '../services/staff.service.js';
import * as attendanceService from '../services/attendance.service.js';
import { ApiError } from '../utils/ApiError.js';

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

  let embedding;
  try {
    embedding = JSON.parse(req.body.embedding);
  } catch {
    throw new ApiError(400, 'embedding must be a JSON array of numbers');
  }
  if (!Array.isArray(embedding) || embedding.some((n) => typeof n !== 'number')) {
    throw new ApiError(400, 'embedding must be a JSON array of numbers');
  }

  const staff = await staffService.enrollFace(req.params.id, {
    embedding,
    photoFile: req.file,
  });
  res.json(staff);
}

export async function attendanceHistory(req, res) {
  if (req.user.role === 'staff' && req.user.staffId !== req.params.id) {
    throw new ApiError(403, 'Cannot view another staff member');
  }
  await staffService.getStaffById(req.params.id); // 404s if missing
  const records = await attendanceService.listAttendanceForStaff(req.params.id);
  res.json(records);
}
