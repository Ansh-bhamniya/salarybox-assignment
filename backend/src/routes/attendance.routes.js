import { Router } from 'express';
import { asyncHandler } from '../utils/asyncHandler.js';
import { requireAuth } from '../middleware/auth.js';
import { upload } from '../middleware/upload.js';
import * as attendanceController from '../controllers/attendance.controller.js';

export const attendanceRoutes = Router();

attendanceRoutes.post(
  '/',
  requireAuth,
  upload.single('selfie'),
  asyncHandler(attendanceController.record)
);
