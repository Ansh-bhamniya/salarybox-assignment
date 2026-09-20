import { Router } from 'express';
import { asyncHandler } from '../utils/asyncHandler.js';
import * as authController from '../controllers/auth.controller.js';

export const authRoutes = Router();

authRoutes.post('/login', asyncHandler(authController.login));
