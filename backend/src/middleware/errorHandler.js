import multer from 'multer';
import { ApiError } from '../utils/ApiError.js';

export function errorHandler(err, req, res, next) {
  // Upload problems (file too large, unexpected field…) are the client's
  // fault, not a server error.
  if (err instanceof multer.MulterError) {
    if (err.code === 'LIMIT_FILE_SIZE') {
      return res.status(413).json({ error: 'File too large (max 8MB)' });
    }
    return res.status(400).json({ error: err.message });
  }

  if (err instanceof ApiError) {
    return res.status(err.status).json({ error: err.message });
  }

  console.error(err);
  return res.status(500).json({ error: 'Internal server error' });
}
