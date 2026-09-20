import jwt from 'jsonwebtoken';
import { supabase } from '../config/supabase.js';
import { env } from '../config/env.js';
import { ApiError } from '../utils/ApiError.js';

function signToken(payload) {
  return jwt.sign(payload, env.jwtSecret, { expiresIn: '12h' });
}

// Admin logs in with a real (dummy) username/password from the `users`
// table. Staff log in with their employee ID plus one shared dummy
// password — the assignment doesn't call for individual staff accounts,
// just a way to identify which staff member is using the app.
export async function login({ username, password }) {
  const { data: adminUser } = await supabase
    .from('users')
    .select('id, role, username, password')
    .eq('username', username)
    .eq('role', 'admin')
    .maybeSingle();

  if (adminUser) {
    if (adminUser.password !== password) {
      throw new ApiError(401, 'Invalid credentials');
    }
    return {
      token: signToken({ userId: adminUser.id, role: 'admin' }),
      role: 'admin',
    };
  }

  const { data: staff } = await supabase
    .from('staff')
    .select('id, employee_id, name')
    .eq('employee_id', username)
    .maybeSingle();

  if (!staff || password !== env.staffDummyPassword) {
    throw new ApiError(401, 'Invalid credentials');
  }

  return {
    token: signToken({ userId: staff.id, role: 'staff', staffId: staff.id }),
    role: 'staff',
    staff: { id: staff.id, employeeId: staff.employee_id, name: staff.name },
  };
}
