import { Router } from 'express';
import { z } from 'zod';
import { body, param, query } from '../../lib/http.js';
import { zDate } from '../../lib/schemas.js';
import { authenticate, ctxOf, requireRole } from '../../middleware/auth.js';
import { leaveView } from '../views.js';
import { Employee } from '../../models/index.js';
import * as svc from './service.js';

export const leaveRouter = Router();
leaveRouter.use(authenticate);

const withName = async (l: any) => leaveView(l, (await Employee.findOne({ _id: l.employeeId, companyId: l.companyId }).select('name').lean())?.name);

leaveRouter.get('/leaves', requireRole('owner', 'manager', 'employee'), async (req, res) => {
  const q = query(req, z.object({ status: z.enum(['pending', 'approved', 'rejected', 'cancelled']).optional(), employeeId: z.string().optional() }));
  res.json({ data: await svc.listLeaves(ctxOf(req), q) });
});

leaveRouter.post('/leaves', requireRole('owner', 'manager', 'employee'), async (req, res) => {
  const b = body(req, z.object({ type: z.enum(['paid', 'sick', 'unpaid']), from: zDate, to: zDate, halfDay: z.boolean().optional(), reason: z.string().max(300).optional(), employeeId: z.string().optional() }));
  res.status(201).json({ data: await withName(await svc.applyLeave(ctxOf(req), b)) });
});

leaveRouter.post('/leaves/:id/decision', requireRole('owner', 'manager'), async (req, res) => {
  const b = body(req, z.object({ decision: z.enum(['approved', 'rejected']), note: z.string().max(300).optional(), asUnpaid: z.boolean().optional() }));
  res.json({ data: await withName(await svc.decideLeave(ctxOf(req), param(req, 'id'), b.decision, b.note, { asUnpaid: b.asUnpaid })) });
});

leaveRouter.post('/leaves/:id/cancel', requireRole('owner', 'manager', 'employee'), async (req, res) => {
  res.json({ data: await withName(await svc.cancelLeave(ctxOf(req), param(req, 'id'))) });
});

leaveRouter.get('/leave-balances', requireRole('owner', 'manager', 'employee'), async (req, res) => {
  const q = query(req, z.object({ employeeId: z.string().optional(), year: z.coerce.number().int().optional() }));
  res.json({ data: await svc.listBalances(ctxOf(req), q.year ?? new Date().getFullYear(), q.employeeId) });
});

leaveRouter.put('/leave-balances/:employeeId', requireRole('owner'), async (req, res) => {
  const b = body(req, z.object({ year: z.number().int().min(2000).max(2100), paid: z.number().min(0).max(366), sick: z.number().min(0).max(366) }));
  res.json({ data: await svc.setLeaveBalance(ctxOf(req), param(req, 'employeeId'), b.year, b.paid, b.sick) });
});
