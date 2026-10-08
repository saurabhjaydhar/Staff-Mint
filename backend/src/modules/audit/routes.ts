import { Router } from 'express';
import { z } from 'zod';
import { query } from '../../lib/http.js';
import { authenticate, ctxOf, requireRole } from '../../middleware/auth.js';
import { AuditLog } from '../../models/index.js';

export const auditRouter = Router();
auditRouter.get('/', authenticate, requireRole('owner'), async (req, res) => {
  const q = query(req, z.object({ entity: z.string().optional(), entityId: z.string().optional(), limit: z.coerce.number().int().min(1).max(200).default(50), before: z.string().datetime().optional() }));
  const ctx = ctxOf(req);
  const f: any = { companyId: ctx.companyId };
  if (q.entity) f.entity = q.entity;
  if (q.entityId) f.entityId = q.entityId;
  if (q.before) f.at = { $lt: new Date(q.before) };
  const logs = await AuditLog.find(f).sort({ at: -1 }).limit(q.limit).lean();
  res.json({
    data: logs.map((l) => ({ id: String(l._id), actorId: l.actorId ? String(l.actorId) : null, actorName: l.actorName, channel: l.channel, action: l.action, entity: l.entity, entityId: l.entityId ? String(l.entityId) : null, before: l.before ?? null, after: l.after ?? null, at: l.at })),
  });
});
