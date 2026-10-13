import { Router } from 'express';
import { z } from 'zod';
import { body, query } from '../../lib/http.js';
import { zDate } from '../../lib/schemas.js';
import { authenticate, ctxOf, requireFeature, requireRole } from '../../middleware/auth.js';
import { todayIn } from '../../lib/dates.js';
import { Company } from '../../models/index.js';
import * as svc from './service.js';

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
// Staff: their own week (works on every plan: without a roster it is just their usual shift).
rosterRouter.get('/mine', authenticate, requireRole('employee'), async (req, res) => {
  const q = query(req, z.object({ week: zDate.optional() }));
  res.json({ data: await svc.myWeek(ctxOf(req), q.week ?? (await today(ctxOf(req).companyId))) });
});
