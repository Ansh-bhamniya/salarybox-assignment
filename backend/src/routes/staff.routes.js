import { Router } from 'express';
import { asyncHandler } from '../utils/asyncHandler.js';
import { requireAuth, requireRole } from '../middleware/auth.js';
import { upload } from '../middleware/upload.js';
import * as staffController from '../controllers/staff.controller.js';

export const staffRoutes = Router();

staffRoutes.use(requireAuth);

staffRoutes.get('/', requireRole('admin'), asyncHandler(staffController.list));
staffRoutes.post('/', requireRole('admin'), asyncHandler(staffController.create));
staffRoutes.get('/:id', asyncHandler(staffController.getById));
staffRoutes.delete('/:id', requireRole('admin'), asyncHandler(staffController.remove));
staffRoutes.post(
  '/:id/enroll',
  requireRole('admin'),
  upload.fields([
    { name: 'photo', maxCount: 1 },
    { name: 'photos', maxCount: 5 },
  ]),
  asyncHandler(staffController.enroll)
);
// Admins can read anyone's history; staff only their own (checked in the controller).
staffRoutes.get('/:id/attendance', asyncHandler(staffController.attendanceHistory));
