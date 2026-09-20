import * as attendanceService from '../services/attendance.service.js';
import { ApiError } from '../utils/ApiError.js';

export async function record(req, res) {
  if (!req.file) {
    throw new ApiError(400, 'selfie file is required');
  }

  const { staffId, latitude, longitude, matchConfidence, capturedAt } = req.body;
  if (!staffId || latitude === undefined || longitude === undefined) {
    throw new ApiError(400, 'staffId, latitude and longitude are required');
  }

  const lat = Number(latitude);
  const lng = Number(longitude);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
    throw new ApiError(400, 'latitude and longitude must be numbers');
  }
  if (matchConfidence !== undefined && !Number.isFinite(Number(matchConfidence))) {
    throw new ApiError(400, 'matchConfidence must be a number');
  }
  if (capturedAt !== undefined && Number.isNaN(new Date(capturedAt).getTime())) {
    throw new ApiError(400, 'capturedAt must be a valid ISO timestamp');
  }

  // Staff can only ever record attendance for themselves.
  if (req.user.role === 'staff' && req.user.staffId !== staffId) {
    throw new ApiError(403, 'Cannot record attendance for another staff member');
  }

  const record = await attendanceService.recordAttendance({
    staffId,
    latitude: Number(latitude),
    longitude: Number(longitude),
    matchConfidence: matchConfidence !== undefined ? Number(matchConfidence) : null,
    capturedAt,
    selfieFile: req.file,
  });

  res.status(201).json(record);
}
