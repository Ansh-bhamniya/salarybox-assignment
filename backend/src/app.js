import express from 'express';
import cors from 'cors';
import { authRoutes } from './routes/auth.routes.js';
import { staffRoutes } from './routes/staff.routes.js';
import { attendanceRoutes } from './routes/attendance.routes.js';
import { errorHandler } from './middleware/errorHandler.js';

export const app = express();

app.use(cors());
app.use(express.json());

app.get('/health', (req, res) => res.json({ ok: true }));

app.use('/auth', authRoutes);
app.use('/staff', staffRoutes);
app.use('/attendance', attendanceRoutes);

app.use(errorHandler);
