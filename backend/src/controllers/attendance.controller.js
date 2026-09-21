import * as attendanceService from '../services/attendance.service.js';
import { ApiError } from '../utils/ApiError.js';
import { env } from '../config/env.js';
import { parseAttempt, parseLiveness } from '../utils/liveness.js';

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

  // What the app's head-turn check saw. Optional, so builds that predate the
  // check still work, unless the server has been told to require it.
  const liveness = req.body.liveness === undefined ? undefined : parseLiveness(req.body.liveness);
  if (env.livenessRequired && !liveness) {
    throw new ApiError(409, 'A head-turn check is required to mark attendance', 'liveness_required');
  }

  const record = await attendanceService.recordAttendance({
    staffId,
    latitude: Number(latitude),
    longitude: Number(longitude),
    matchConfidence: matchConfidence !== undefined ? Number(matchConfidence) : null,
    capturedAt,
    selfieFile: req.file,
    liveness,
  });

  res.status(201).json(record);
}

/** The app reports a failed head-turn check (or a face that didn't match), so failures can be reviewed. */
export async function reportAttempt(req, res) {
  const { outcome, reason } = parseAttempt(req.body);
  await attendanceService.recordAttempt(req.user.staffId, { outcome, reason });
  res.status(201).json({ ok: true });
}
