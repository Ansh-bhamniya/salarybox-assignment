import * as authService from '../services/auth.service.js';
import { ApiError } from '../utils/ApiError.js';

export async function login(req, res) {
  const { username, password } = req.body;
  if (!username || !password) {
    throw new ApiError(400, 'username and password are required');
  }

  const result = await authService.login({ username, password });
  res.json(result);
}
