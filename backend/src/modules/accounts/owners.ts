import type { NextFunction, Request, Response } from 'express';
import { Types } from 'mongoose';
import { AppError, notFound } from '../../lib/errors.js';
import type { Ctx } from '../../lib/context.js';
import { Company, Membership, OwnershipTransfer, User, type UserDoc } from '../../models/index.js';
import { audit } from '../audit/service.js';
import { getConfig } from '../config/service.js';
import { consumeOtp, openSession } from '../auth/service.js';
import { endMemberships } from '../auth/memberships.js';
import { notifyUser } from '../notifications/service.js';
import { provider } from '../../providers/registry.js';
import { logger } from '../../lib/logger.js';

/** The main owner is the one on the company record; other owner accounts are co-owners. */
export async function isMainOwner(ctx: Ctx) {
  const c = await Company.findById(ctx.companyId).select('ownerUserId').lean();
  return !!c && String(c.ownerUserId) === String(ctx.userId);
}

async function assertMainOwner(ctx: Ctx) {
  if (!(await isMainOwner(ctx))) throw new AppError('FORBIDDEN', 'Only the main owner can do this', { reason: 'main_owner_only' });
}

/** Billing: the main owner, or a co-owner the main owner allowed (F14 decision). */
export async function requireBillingAccess(req: Request, _res: Response, next: NextFunction) {
  const ctx = req.ctx;
  if (!ctx || ctx.role !== 'owner') throw new AppError('FORBIDDEN', 'Only owners can manage billing');
  if (await isMainOwner(ctx)) return next();
  const m = req.auth?.membershipId ? await Membership.findById(req.auth.membershipId).select('canManageBilling').lean() : null;
  if (!m?.canManageBilling) throw new AppError('FORBIDDEN', 'Ask the main owner to let you manage billing', { reason: 'billing_not_allowed' });
  next();
}

const maskPhone = (p: string) => (p.length > 4 ? `${'•'.repeat(Math.max(0, p.length - 7))}${p.slice(-4)}` : p);

/** Plain text to a number that may have no app or business context (lost/recovered numbers). */
async function textNumber(phone: string, text: string) {
  try {
    await (await provider('messaging')).sendText(phone, text);
  } catch (err) {
    logger.warn({ err }, 'account notice send failed');
  }
}

// ---------------------------------------------------------------- co-owners

export async function listOwners(ctx: Ctx) {
  const company = await Company.findById(ctx.companyId).select('ownerUserId').lean();
  const ms = await Membership.find({ companyId: ctx.companyId, role: 'owner', status: 'active' }).sort({ createdAt: 1 }).lean();
  const users = await User.find({ _id: { $in: ms.map((m) => m.userId) } }).select('name phone').lean();
  const byId = new Map(users.map((u) => [String(u._id), u]));
  return ms.map((m) => {
    const main = String(m.userId) === String(company?.ownerUserId);
    return {
      id: String(m._id),
      userId: String(m.userId),
      name: byId.get(String(m.userId))?.name ?? '',
      phone: byId.get(String(m.userId))?.phone ?? '',
      isMain: main,
      canManageBilling: main || !!m.canManageBilling,
      isYou: String(m.userId) === String(ctx.userId),
    };
  });
}

export async function addCoOwner(ctx: Ctx, input: { phone: string; name: string; canManageBilling?: boolean }) {
  await assertMainOwner(ctx);
  const user = (await User.findOne({ phone: input.phone, deletedAt: null })) ?? (await User.create({ phone: input.phone, name: input.name, role: 'owner', companyId: null }));
  const here = await Membership.findOne({ userId: user._id, companyId: ctx.companyId });
  if (here?.status === 'active') {
    const msg =
      here.role === 'owner'
        ? 'This number is already an owner of this business'
        : here.role === 'ca'
          ? 'This number is your accountant. Remove them as accountant first.'
          : 'This number is on your staff. Remove them from staff first.';
    throw new AppError('CONFLICT', msg, { reason: `already_${here.role}` });
  }
  const canManageBilling = !!input.canManageBilling;
  if (here) {
    here.set({ role: 'owner', status: 'active', employeeId: null, branchIds: [], deviceIds: [], endedAt: null, endedReason: null, canManageBilling });
    await here.save();
  } else {
    await Membership.create({ userId: user._id, companyId: ctx.companyId, role: 'owner', canManageBilling });
  }
  const company = await Company.findById(ctx.companyId).select('name').lean();
  await notifyUser(ctx.companyId, user, {
    template: 'co_owner_added',
    title: `You are now a co-owner of ${company?.name}`,
    titleHi: `अब आप ${company?.name} के सह-मालिक हैं`,
    body: 'Open StaffMint and switch to this business.',
    bodyHi: 'StaffMint खोलें और इस बिज़नेस पर जाएँ।',
    data: { kind: 'co_owner_added' },
  });
  await audit(ctx, { action: 'owner.add', entity: 'user', entityId: user._id, after: { phone: input.phone, canManageBilling } });
  return listOwners(ctx);
}

async function coOwnerMembership(ctx: Ctx, membershipId: string) {
  const m = await Membership.findOne({ _id: membershipId, companyId: ctx.companyId, role: 'owner', status: 'active' });
  if (!m) throw notFound('Co-owner');
  const company = await Company.findById(ctx.companyId).select('ownerUserId').lean();
  if (String(m.userId) === String(company?.ownerUserId)) throw new AppError('CONFLICT', 'This is the main owner', { reason: 'main_owner' });
  return m;
}

export async function setCoOwnerBilling(ctx: Ctx, membershipId: string, canManageBilling: boolean) {
  await assertMainOwner(ctx);
  const m = await coOwnerMembership(ctx, membershipId);
  m.canManageBilling = canManageBilling;
  await m.save();
  await audit(ctx, { action: 'owner.billing', entity: 'membership', entityId: m._id, after: { canManageBilling } });
  return listOwners(ctx);
}

export async function removeCoOwner(ctx: Ctx, membershipId: string) {
  await assertMainOwner(ctx);
  const m = await coOwnerMembership(ctx, membershipId);
  await endMemberships({ _id: m._id }, 'removed');
  await audit(ctx, { action: 'owner.remove', entity: 'membership', entityId: m._id });
  return listOwners(ctx);
}

// ----------------------------------------------------------------- transfer

const transferView = (t: any, companyName?: string, fromName?: string) => ({
  id: String(t._id),
  companyId: String(t.companyId),
  companyName: companyName ?? null,
  fromName: fromName ?? null,
  kind: t.kind,
  toPhone: t.toPhone,
  toPhoneMasked: maskPhone(t.toPhone),
  keepAs: t.keepAs,
  status: t.status,
  expiresAt: t.expiresAt,
});

async function createTransfer(ctx: Ctx, kind: 'transfer' | 'recovery', fromUserId: Types.ObjectId, toPhone: string, keepAs: 'co_owner' | 'leave') {
  const fromUser = await User.findById(fromUserId).lean();
  if (fromUser?.phone === toPhone) throw new AppError('VALIDATION_ERROR', 'That is already the owner’s number', { field: 'phone' });
  await OwnershipTransfer.updateMany({ companyId: ctx.companyId, status: 'pending' }, { status: 'cancelled', decidedAt: new Date() });
  const days = await getConfig<number>('accounts.transferDays');
  const t = await OwnershipTransfer.create({ companyId: ctx.companyId, kind, fromUserId, toPhone, keepAs, initiatedBy: ctx.userId!, expiresAt: new Date(Date.now() + days * 86400_000) });
  const company = await Company.findById(ctx.companyId).select('name').lean();
  const target = await User.findOne({ phone: toPhone, deletedAt: null }).lean();
  if (target) {
    await notifyUser(ctx.companyId, target, {
      template: 'ownership_offer',
      title: `${company?.name}: you are being made the owner`,
      titleHi: `${company?.name}: आपको मालिक बनाया जा रहा है`,
      body: 'Open StaffMint to accept.',
      bodyHi: 'स्वीकार करने के लिए StaffMint खोलें।',
      data: { kind: 'ownership_offer', transferId: String(t._id) },
    });
  } else {
    await textNumber(toPhone, `${company?.name} wants to make you its owner on StaffMint. Log in with this number to accept: ${await getConfig<string>('app.downloadUrl')}`);
  }
  return { t, companyName: company?.name ?? '' };
}

/** Main owner hands the business to another number; their own OTP confirms it (F14 row 9). */
export async function startTransfer(ctx: Ctx, input: { phone: string; keepAs: 'co_owner' | 'leave'; code: string }) {
  await assertMainOwner(ctx);
  const me = await loadUser(ctx.userId!);
  await consumeOtp(me.phone, input.code);
  const { t, companyName } = await createTransfer(ctx, 'transfer', me._id, input.phone, input.keepAs);
  await audit(ctx, { action: 'owner.transfer.start', entity: 'company', entityId: ctx.companyId, after: { toPhone: input.phone, keepAs: input.keepAs } });
  return transferView(t, companyName, me.name);
}

/** A co-owner moves main ownership to the owner's new number when the old one is lost (F14 row 11, step 1). */
export async function startOwnerRecovery(ctx: Ctx, newPhone: string) {
  if (await isMainOwner(ctx)) throw new AppError('CONFLICT', 'You are the main owner. Change your own number from Profile.');
  const company = await Company.findById(ctx.companyId).select('ownerUserId name').lean();
  const oldOwner = await User.findById(company!.ownerUserId).lean();
  const { t } = await createTransfer(ctx, 'recovery', company!.ownerUserId, newPhone, 'co_owner');
  // The old number hears about it at once and can still cancel from the app if it is not actually lost.
  if (oldOwner) await textNumber(oldOwner.phone, `StaffMint: a co-owner of ${company!.name} is moving its main owner to the number ending ${newPhone.slice(-4)}. If this is wrong, open StaffMint and cancel it.`);
  await audit(ctx, { action: 'owner.recovery.start', entity: 'company', entityId: ctx.companyId, after: { toPhone: newPhone } });
  return transferView(t, company!.name, oldOwner?.name);
}

export async function currentTransfer(ctx: Ctx) {
  const t = await OwnershipTransfer.findOne({ companyId: ctx.companyId, status: 'pending', expiresAt: { $gt: new Date() } }).lean();
  return t ? transferView(t) : null;
}

export async function cancelTransfer(ctx: Ctx) {
  // The main owner, or the co-owner who started it.
  const t = await OwnershipTransfer.findOne({ companyId: ctx.companyId, status: 'pending' });
  if (!t) throw notFound('Transfer');
  if (!(await isMainOwner(ctx)) && String(t.initiatedBy) !== String(ctx.userId)) throw new AppError('FORBIDDEN', 'Only the main owner can cancel this');
  t.status = 'cancelled';
  t.decidedAt = new Date();
  await t.save();
  await audit(ctx, { action: 'owner.transfer.cancel', entity: 'company', entityId: ctx.companyId });
}

/** Offers waiting for this number. */
export async function pendingTransfersFor(user: { phone: string }) {
  const list = await OwnershipTransfer.find({ toPhone: user.phone, status: 'pending', expiresAt: { $gt: new Date() } }).lean();
  const companies = await Company.find({ _id: { $in: list.map((t) => t.companyId) } }).select('name').lean();
  const users = await User.find({ _id: { $in: list.map((t) => t.fromUserId) } }).select('name phone').lean();
  const cn = new Map(companies.map((c) => [String(c._id), c.name]));
  const un = new Map(users.map((u) => [String(u._id), u.name || u.phone]));
  return list.map((t) => transferView(t, cn.get(String(t.companyId)), un.get(String(t.fromUserId))));
}

async function loadUser(id: Types.ObjectId | string): Promise<UserDoc> {
  const u = await User.findOne({ _id: id, deletedAt: null });
  if (!u) throw new AppError('UNAUTHORIZED', 'User not found');
  return u;
}

export async function decideTransfer(userId: string, transferId: string, accept: boolean, session: { deviceId: string; refreshToken?: string }) {
  const me = await loadUser(userId);
  const t = await OwnershipTransfer.findOne({ _id: transferId, toPhone: me.phone, status: 'pending', expiresAt: { $gt: new Date() } });
  if (!t) throw notFound('Ownership offer');
  const company = await Company.findById(t.companyId);
  if (!company || company.closedAt) throw notFound('Business');
  t.status = accept ? 'accepted' : 'declined';
  t.decidedAt = new Date();
  await t.save();
  const fromUser = await User.findById(t.fromUserId);
  const ctx: Ctx = { userId: me._id, companyId: company._id, role: 'owner', employeeId: null, branchIds: [], actorName: me.name || me.phone, channel: 'app', language: (me.language as 'en' | 'hi') ?? 'hi' };
  if (!accept) {
    await audit(ctx, { action: 'owner.transfer.decline', entity: 'company', entityId: company._id });
    return null;
  }
  // The new main owner: any earlier staff/CA access here becomes the owner account.
  let mine = await Membership.findOne({ userId: me._id, companyId: company._id });
  if (mine) {
    mine.set({ role: 'owner', status: 'active', employeeId: null, branchIds: [], deviceIds: [], endedAt: null, endedReason: null, canManageBilling: false });
    await mine.save();
  } else {
    mine = await Membership.create({ userId: me._id, companyId: company._id, role: 'owner' });
  }
  company.ownerUserId = me._id;
  await company.save();
  if (t.keepAs === 'leave') await endMemberships({ userId: t.fromUserId, companyId: company._id }, 'left');
  if (fromUser) {
    await notifyUser(company._id, fromUser, {
      template: 'ownership_moved',
      title: `${company.name} has a new main owner`,
      titleHi: `${company.name} के नए मुख्य मालिक`,
      body: t.keepAs === 'leave' ? 'Your access to this business has ended.' : 'You are now a co-owner.',
      bodyHi: t.keepAs === 'leave' ? 'इस बिज़नेस तक आपकी पहुँच ख़त्म हो गई है।' : 'अब आप सह-मालिक हैं।',
      data: { kind: 'ownership_moved' },
    });
  }
  await audit(ctx, { action: t.kind === 'recovery' ? 'owner.recovery.accept' : 'owner.transfer.accept', entity: 'company', entityId: company._id, before: { ownerUserId: t.fromUserId }, after: { ownerUserId: me._id } });
  return openSession(me, mine, session.deviceId, session.refreshToken);
}
