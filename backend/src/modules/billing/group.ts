import { Types } from 'mongoose';
import { AppError, notFound } from '../../lib/errors.js';
import type { Ctx } from '../../lib/context.js';
import { Company, Subscription } from '../../models/index.js';
import { audit } from '../audit/service.js';
import { getConfig } from '../config/service.js';
import { activeStaffCount, billingStaffCount, companyPlan } from './plans.js';

/**
 * One bill for several businesses (PRD F14 Phase 4). The business where the
 * main owner manages billing pays; other businesses they own can be added to
 * it and use the payer's plan. Staff limits and extra-staff pricing count all
 * of them together, plus a small price per extra business.
 */
async function assertMainOwnerOf(ctx: Ctx, companyId: Types.ObjectId | string) {
  const c = await Company.findOne({ _id: companyId, closedAt: null }).select('ownerUserId billedTo name').lean();
  if (!c) throw notFound('Business');
  if (String(c.ownerUserId) !== String(ctx.userId)) throw new AppError('FORBIDDEN', 'Only the main owner of both businesses can put them on one bill', { reason: 'main_owner_only' });
  return c;
}

export async function billingGroup(ctx: Ctx) {
  const me = await Company.findById(ctx.companyId).select('billedTo ownerUserId').lean();
  const payerId = me?.billedTo ?? ctx.companyId;
  const payer = await Company.findById(payerId).select('name').lean();
  const members = await Company.find({ billedTo: payerId, closedAt: null }).select('name').lean();
  const iAmMain = String(me?.ownerUserId) === String(ctx.userId);
  // Other businesses this main owner owns that are not on a bill and not paying for others.
  const owned = iAmMain ? await Company.find({ ownerUserId: ctx.userId, closedAt: null, _id: { $ne: payerId }, billedTo: null }).select('name').lean() : [];
  const payers = new Set((await Company.find({ billedTo: { $in: owned.map((c) => c._id) } }).select('billedTo').lean()).map((c) => String(c.billedTo)));
  const view = async (c: any) => ({ companyId: String(c._id), name: c.name, staffCount: await activeStaffCount(c._id) });
  return {
    payer: await view(payer ?? { _id: payerId, name: '' }),
    isPayer: String(payerId) === String(ctx.companyId),
    members: await Promise.all(members.map(view)),
    candidates: await Promise.all(owned.filter((c) => !payers.has(String(c._id)) && !members.some((m) => String(m._id) === String(c._id))).map(view)),
    totalStaff: await billingStaffCount(ctx.companyId),
    extraBusinessPricePaise: await getConfig<number>('billing.extraBusinessPricePaise'),
    plan: (await companyPlan({ _id: ctx.companyId })).plan,
  };
}

/** Add another business of the same main owner to this business's bill. */
export async function addToBill(ctx: Ctx, companyId: string) {
  const payer = await assertMainOwnerOf(ctx, ctx.companyId);
  if (payer.billedTo) throw new AppError('CONFLICT', 'This business is itself on another bill. Open the paying business.', { reason: 'not_payer' });
  if (String(companyId) === String(ctx.companyId)) throw new AppError('VALIDATION_ERROR', 'This is the paying business');
  const member = await assertMainOwnerOf(ctx, companyId);
  if (member.billedTo) throw new AppError('CONFLICT', `${member.name} is already on a bill`, { reason: 'already_billed' });
  if (await Company.exists({ billedTo: companyId })) throw new AppError('CONFLICT', `${member.name} pays for other businesses`, { reason: 'is_payer' });
  const paid = await Subscription.exists({ companyId, status: { $in: ['active', 'past_due'] }, currentPeriodEnd: { $gt: new Date() } });
  if (paid) throw new AppError('CONFLICT', `${member.name} has its own paid plan. Cancel it first so you are not charged twice.`, { reason: 'has_own_plan' });
  await Company.updateOne({ _id: companyId }, { billedTo: ctx.companyId });
  await audit(ctx, { action: 'billing.group.add', entity: 'company', entityId: new Types.ObjectId(companyId), after: { billedTo: ctx.companyId } });
  return billingGroup(ctx);
}

/** Take a business off this bill; it goes back to its own plan (Free unless it subscribes). */
export async function removeFromBill(ctx: Ctx, companyId: string) {
  await assertMainOwnerOf(ctx, ctx.companyId);
  const r = await Company.updateOne({ _id: companyId, billedTo: ctx.companyId }, { billedTo: null });
  if (!r.modifiedCount) throw notFound('Business on this bill');
  await audit(ctx, { action: 'billing.group.remove', entity: 'company', entityId: new Types.ObjectId(companyId) });
  return billingGroup(ctx);
}
