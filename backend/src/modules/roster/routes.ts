import { Router } from 'express';
import { z } from 'zod';
import { body, param, query } from '../../lib/http.js';
import { zDate } from '../../lib/schemas.js';
import { authenticate, ctxOf, requireFeature, requireRole } from '../../middleware/auth.js';
import { todayIn } from '../../lib/dates.js';
import { Company } from '../../models/index.js';
import * as svc from './service.js';
import * as repeat from './repeat.js';
import * as swaps from './swaps.js';

export const rosterRouter = Router();

const today = async (companyId: any) => todayIn((await Company.findById(companyId).select('timezone').lean())?.timezone ?? 'Asia/Kolkata');
const weekQuery = z.object({ week: zDate.optional(), branchId: z.string().optional() });
const owner = [authenticate, requireRole('owner', 'manager'), requireFeature('roster')];

rosterRouter.get('/', ...owner, async (req, res) => {
  const q = query(req, weekQuery);
  res.json({ data: await svc.weekView(ctxOf(req), q.week ?? (await today(ctxOf(req).companyId)), q.branchId) });
});
rosterRouter.put('/cells', ...owner, async (req, res) => {
  const b = body(
    req,
    z.object({
      cells: z
        .array(z.object({ employeeId: z.string(), date: zDate, kind: z.enum(['shift', 'off', 'usual']), shiftId: z.string().nullable().optional() }))
        .min(1)
        .max(500),
    }),
  );
  res.json({ data: await svc.setCells(ctxOf(req), b.cells) });
});
rosterRouter.post('/copy-last-week', ...owner, async (req, res) => {
  const b = body(req, weekQuery);
  res.json({ data: await svc.copyLastWeek(ctxOf(req), b.week ?? (await today(ctxOf(req).companyId)), b.branchId) });
});
rosterRouter.post('/send', ...owner, async (req, res) => {
  const b = body(req, weekQuery);
  res.json({ data: await svc.sendWeek(ctxOf(req), b.week ?? (await today(ctxOf(req).companyId)), b.branchId) });
});
rosterRouter.post('/repeat', ...owner, requireFeature('roster_repeat'), async (req, res) => {
  const b = body(req, weekQuery.extend({ mode: z.enum(['same', 'rotate']), autoSend: z.boolean().optional() }));
  res.json({ data: await repeat.turnOnRepeat(ctxOf(req), { ...b, week: b.week ?? (await today(ctxOf(req).companyId)) }) });
});
// Turning it off works on any plan, so a shop that moved to a smaller plan can still stop it.
rosterRouter.delete('/repeat', authenticate, requireRole('owner', 'manager'), async (req, res) => {
  const q = query(req, weekQuery);
  res.json({ data: await repeat.turnOffRepeat(ctxOf(req), q.branchId) });
});
// ---- Swaps: staff ask a colleague, the colleague accepts, the owner or a manager approves.
const staff = [authenticate, requireRole('employee')];
rosterRouter.get('/swaps', authenticate, requireRole('owner', 'manager', 'employee'), async (req, res) => res.json({ data: await swaps.listSwaps(ctxOf(req)) }));
rosterRouter.get('/swap-options', ...staff, requireFeature('roster_swaps'), async (req, res) => {
  const q = query(req, z.object({ date: zDate }));
  res.json({ data: await swaps.swapOptions(ctxOf(req), q.date) });
});
rosterRouter.post('/swaps', ...staff, requireFeature('roster_swaps'), async (req, res) => {
  const b = body(req, z.object({ date: zDate, withEmployeeId: z.string().min(1), note: z.string().trim().max(200).optional() }));
  res.status(201).json({ data: await swaps.askSwap(ctxOf(req), b) });
});
rosterRouter.post('/swaps/:id/accept', ...staff, async (req, res) => res.json({ data: await swaps.answerSwap(ctxOf(req), param(req, 'id'), true) }));
rosterRouter.post('/swaps/:id/decline', ...staff, async (req, res) => res.json({ data: await swaps.answerSwap(ctxOf(req), param(req, 'id'), false) }));
rosterRouter.post('/swaps/:id/cancel', ...staff, async (req, res) => res.json({ data: await swaps.cancelSwap(ctxOf(req), param(req, 'id')) }));
rosterRouter.post('/swaps/:id/approve', ...owner, async (req, res) => res.json({ data: await swaps.decideSwap(ctxOf(req), param(req, 'id'), true) }));
rosterRouter.post('/swaps/:id/reject', ...owner, async (req, res) => res.json({ data: await swaps.decideSwap(ctxOf(req), param(req, 'id'), false) }));
// Staff: their own week (works on every plan: without a roster it is just their usual shift).
rosterRouter.get('/mine', authenticate, requireRole('employee'), async (req, res) => {
  const q = query(req, z.object({ week: zDate.optional() }));
  res.json({ data: await svc.myWeek(ctxOf(req), q.week ?? (await today(ctxOf(req).companyId))) });
});
