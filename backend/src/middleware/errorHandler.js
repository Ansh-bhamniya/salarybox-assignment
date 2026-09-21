import multer from 'multer';
import { ApiError } from '../utils/ApiError.js';

export function errorHandler(err, req, res, next) {
  // Upload problems (file too large, unexpected field…) are the client's
  // fault, not a server error.
  if (err instanceof multer.MulterError) {
    if (err.code === 'LIMIT_FILE_SIZE') {
      return res.status(413).json({ error: 'File too large (max 8MB)' });
    }
    if (err.code === 'LIMIT_FILE_COUNT') {
      return res.status(400).json({ error: 'Too many files' });
    }
    return res.status(400).json({ error: err.message });
  }

  if (err instanceof ApiError) {
    const body = { error: err.message };
    if (err.code) body.code = err.code;
    if (err.details !== undefined) body.details = err.details;
    return res.status(err.status).json(body);
  }

  console.error(err);
  return res.status(500).json({ error: 'Internal server error' });
}
