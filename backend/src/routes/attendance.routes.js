import { Router } from 'express';
import { asyncHandler } from '../utils/asyncHandler.js';
import { requireAuth, requireRole } from '../middleware/auth.js';
import { upload } from '../middleware/upload.js';
import * as attendanceController from '../controllers/attendance.controller.js';

export const attendanceRoutes = Router();

attendanceRoutes.post(
  '/',
  requireAuth,
  upload.single('selfie'),
  asyncHandler(attendanceController.record)
);

// Failed checks reported by the app (staff only, about themselves).
attendanceRoutes.post(
  '/attempts',
  requireAuth,
  requireRole('staff'),
  asyncHandler(attendanceController.reportAttempt)
);
