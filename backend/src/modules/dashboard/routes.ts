import { Router } from 'express';
import { authenticate, ctxOf, requireRole } from '../../middleware/auth.js';
import { dashboardToday } from '../attendance/service.js';

export const dashboardRouter = Router();
dashboardRouter.get('/today', authenticate, requireRole('owner', 'manager'), async (req, res) => {
  res.json({ data: await dashboardToday(ctxOf(req)) });
});
