import jwt from 'jsonwebtoken';
import { env } from '../config/env.js';
import { ApiError } from '../utils/ApiError.js';

export function requireAuth(req, res, next) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;

  if (!token) {
    throw new ApiError(401, 'Missing bearer token');
  }

  try {
    req.user = jwt.verify(token, env.jwtSecret);
    next();
  } catch {
    throw new ApiError(401, 'Invalid or expired token');
  }
}

export function requireRole(role) {
  return (req, res, next) => {
    if (req.user?.role !== role) {
      throw new ApiError(403, `Requires ${role} role`);
    }
    next();
  };
}
