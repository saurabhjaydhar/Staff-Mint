import type { Types } from 'mongoose';
import { AuditLog } from '../../models/index.js';
import type { Ctx } from '../../lib/context.js';

const strip = (v: any) => {
  if (v === null || v === undefined) return v;
  const o = typeof v.toObject === 'function' ? v.toObject() : v;
  const { __v, updatedAt, createdAt, selfieBase64, ...rest } = o ?? {};
  return JSON.parse(JSON.stringify(rest));
};

/** Append-only audit trail for every write from any channel (PRD F13, §19). */
export async function audit(ctx: Ctx, entry: { action: string; entity: string; entityId?: Types.ObjectId | string | null; before?: unknown; after?: unknown }) {
  await AuditLog.create({
    companyId: ctx.companyId,
    actorId: ctx.userId,
    actorName: ctx.actorName,
    channel: ctx.channel,
    action: entry.action,
    entity: entry.entity,
    entityId: entry.entityId ?? null,
    before: strip(entry.before),
    after: strip(entry.after),
    at: new Date(),
  });
}
