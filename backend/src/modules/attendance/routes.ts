import { Router } from 'express';
import { z } from 'zod';
import { body, param, query } from '../../lib/http.js';
import { zDate, zMonth } from '../../lib/schemas.js';
import { authenticate, ctxOf, requireRole } from '../../middleware/auth.js';
import { ATTENDANCE_STATUSES } from '../../models/attendance.js';
import { Company } from '../../models/index.js';
import { todayIn } from '../../lib/dates.js';
import * as svc from './service.js';

export const attendanceRouter = Router();
attendanceRouter.use(authenticate);

const punchSchema = z.object({
  clientTime: z.string().datetime({ offset: true }),
  geo: z.object({ lat: z.number().min(-90).max(90), lng: z.number().min(-180).max(180), accuracyM: z.number().min(0).max(100000).optional() }).nullable().optional(),
  mockLocation: z.boolean().default(false),
  lockCheck: z.enum(['passed', 'failed', 'unavailable']).optional(),
  deviceId: z.string().min(4).max(200),
  selfieBase64: z.string().max(3_000_000).nullable().optional(),
  clientPunchId: z.string().min(8).max(80),
});

const punchHandler = (type: 'in' | 'out') => async (req: any, res: any) => {
  const b = body(req, punchSchema);
  const r = await svc.punch(ctxOf(req), { ...b, type });
  res.status(r.duplicate ? 200 : 201).json({ data: { record: await svc.attendanceView(r.record), punch: await svc.punchView(r.punch) } });
};

attendanceRouter.post('/check-in', requireRole('employee', 'manager'), punchHandler('in'));
attendanceRouter.post('/check-out', requireRole('employee', 'manager'), punchHandler('out'));

attendanceRouter.post('/sync', requireRole('employee', 'manager'), async (req, res) => {
  const b = body(req, z.object({ punches: z.array(punchSchema.extend({ type: z.enum(['in', 'out']) })).min(1).max(100) }));
  res.json({ data: await svc.syncPunches(ctxOf(req), b.punches) });
});

attendanceRouter.get('/today', requireRole('employee', 'manager'), async (req, res) => {
  res.json({ data: await svc.todayForEmployee(ctxOf(req)) });
});

attendanceRouter.get('/month', requireRole('owner', 'manager', 'employee', 'ca'), async (req, res) => {
  const q = query(req, z.object({ month: zMonth, employeeId: z.string().optional() }));
  res.json({ data: await svc.monthGrid(ctxOf(req), q.month, q.employeeId) });
});

attendanceRouter.get('/', requireRole('owner', 'manager', 'ca'), async (req, res) => {
  const q = query(req, z.object({ date: zDate.optional() }));
  const ctx = ctxOf(req);
  const date = q.date ?? todayIn((await Company.findById(ctx.companyId).lean())!.timezone);
  res.json({ data: await svc.dayView(ctx, date) });
});

attendanceRouter.post('/override', requireRole('owner', 'manager'), async (req, res) => {
  const b = body(req, z.object({ employeeId: z.string(), date: zDate, status: z.enum(ATTENDANCE_STATUSES), leaveType: z.enum(['paid', 'sick', 'unpaid']).optional(), reason: z.string().trim().min(2).max(300) }));
  res.json({ data: await svc.attendanceView(await svc.overrideDay(ctxOf(req), b)) });
});

attendanceRouter.post('/clear-override', requireRole('owner', 'manager'), async (req, res) => {
  const b = body(req, z.object({ employeeId: z.string(), date: zDate, reason: z.string().trim().min(2).max(300) }));
  const r = await svc.clearOverride(ctxOf(req), b);
  res.json({ data: r ? await svc.attendanceView(r) : null });
});

attendanceRouter.post('/:id/punches/:punchId/decision', requireRole('owner', 'manager'), async (req, res) => {
  const b = body(req, z.object({ approve: z.boolean() }));
  const punchId = String(req.params.punchId);
  res.json({ data: await svc.attendanceView(await svc.decidePunch(ctxOf(req), param(req, 'id'), punchId, b.approve)) });
});
