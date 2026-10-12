import { Router } from 'express';
import { Types } from 'mongoose';
import { z } from 'zod';
import { query } from '../../lib/http.js';
import { authenticate, ctxOf, requireRole } from '../../middleware/auth.js';
import { AuditLog, Employee } from '../../models/index.js';
import { CATEGORY_ACTIONS, describe } from './describe.js';

export const auditRouter = Router();

const CATEGORIES = ['attendance', 'leave', 'salary', 'staff', 'settings', 'team', 'billing'] as const;

auditRouter.get('/', authenticate, requireRole('owner'), async (req, res) => {
  const q = query(
    req,
    z.object({
      entity: z.string().optional(),
      entityId: z.string().optional(),
      category: z.enum(CATEGORIES).optional(),
      limit: z.coerce.number().int().min(1).max(200).default(50),
      before: z.string().datetime().optional(),
    }),
  );
  const ctx = ctxOf(req);
  const f: any = { companyId: ctx.companyId, action: { $ne: 'admin.login' } };
  if (q.entity) f.entity = q.entity;
  if (q.entityId) f.entityId = q.entityId;
  if (q.category) f.action = { $regex: CATEGORY_ACTIONS[q.category].source, $ne: 'admin.login' };
  if (q.before) f.at = { $lt: new Date(q.before) };
  const logs = await AuditLog.find(f).sort({ at: -1 }).limit(q.limit).lean();

  // Staff names for the sentences ("Raju: 12 Oct set to Absent"), current names first.
  const ids = new Set<string>();
  for (const l of logs as any[]) {
    for (const v of [l.after?.employeeId, l.before?.employeeId, l.entity === 'employee' ? l.entityId : null]) {
      if (v && Types.ObjectId.isValid(String(v))) ids.add(String(v));
    }
  }
  const emps = ids.size
    ? await Employee.find({ companyId: ctx.companyId, _id: { $in: [...ids] } }, { name: 1 }).lean()
    : [];
  const names = new Map(emps.map((e: any) => [String(e._id), e.name as string]));
  const look = { employeeName: (id: unknown) => (id ? names.get(String(id)) ?? null : null) };

  res.json({
    data: logs.map((l: any) => {
      const d = describe(l, ctx.language, look);
      return {
        id: String(l._id),
        actorId: l.actorId ? String(l.actorId) : null,
        actorName: l.actorName,
        channel: l.channel,
        action: l.action,
        entity: l.entity,
        entityId: l.entityId ? String(l.entityId) : null,
        before: l.before ?? null,
        after: l.after ?? null,
        at: l.at,
        // Plain words for people (the raw fields above stay for exports and the web table).
        text: d?.text ?? null,
        category: d?.category ?? 'other',
        changes: d?.changes ?? [],
      };
    }),
  });
});
