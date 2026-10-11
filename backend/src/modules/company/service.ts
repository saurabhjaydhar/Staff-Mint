import { Types } from 'mongoose';
import { env } from '../../config/env.js';
import { AppError, notFound } from '../../lib/errors.js';
import { toGeoPoint } from '../../lib/geo.js';
import { minutesOfDay } from '../../lib/dates.js';
import type { Ctx } from '../../lib/context.js';
import { Branch, Company, Holiday, Membership, RefreshToken, Shift, Subscription, User } from '../../models/index.js';
import { sha256 } from '../../lib/crypto.js';
import { HOLIDAY_TEMPLATES } from '../config/defaults.js';
import { companyPlan } from '../billing/plans.js';
import { trialForNewBusiness, trialFromSubscription } from '../billing/trial.js';
import { audit } from '../audit/service.js';
import { issueTokens } from '../auth/service.js';
import { activate, activeMemberships, membershipViews } from '../auth/memberships.js';
import { branchView, holidayView, shiftView } from '../views.js';
import { provider } from '../../providers/registry.js';

export interface SetupInput {
  name: string;
  businessType: string;
  location: { lat: number; lng: number; address?: string };
  openingTime: string;
  closingTime?: string;
  weeklyOff: number[];
  country?: string;
  timezone?: string;
  currency?: string;
  ownerName?: string;
}

export async function companyView(company: any) {
  const { plan, subscription } = await companyPlan(company);
  return {
    id: String(company._id),
    name: company.name,
    businessType: company.businessType,
    country: company.country,
    currency: company.currency,
    timezone: company.timezone,
    location: company.location ?? null,
    settings: company.settings,
    plan,
    subscription: subscription
      ? { status: subscription.status, planCode: subscription.planCode, trialEndsAt: subscription.trialEndsAt ?? null, currentPeriodEnd: subscription.currentPeriodEnd ?? null }
      : { status: 'free', planCode: 'free', trialEndsAt: null, currentPeriodEnd: null },
    /** Free trial countdown, or "trial ended" for 30 days after (owners see a banner). */
    trial: await trialFromSubscription(subscription),
  };
}

const addHours = (time: string, h: number) => {
  const m = (minutesOfDay(time) + h * 60) % (24 * 60);
  return `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`;
};

export async function seedHolidays(companyId: Types.ObjectId, country: string, years: number[]) {
  for (const y of years) {
    for (const h of HOLIDAY_TEMPLATES[country]?.[y] ?? []) {
      await Holiday.updateOne({ companyId, date: h.date }, { $setOnInsert: { companyId, date: h.date, name: h.name, source: 'template' } }, { upsert: true });
    }
  }
}

/** A person can own several businesses; this keeps accidental duplicates and abuse in check. */
export const MAX_OWNED_BUSINESSES = 10;

/**
 * Create a business owned by this person. Anyone can do this, including
 * someone who is staff or accountant elsewhere: they get an owner membership
 * and the session (on this device) switches into the new business.
 */
export async function setupCompany(userId: Types.ObjectId, input: SetupInput, session: { deviceId?: string; refreshToken?: string } = {}) {
  const user = await User.findOne({ _id: userId, deletedAt: null });
  if (!user) throw notFound('User');
  const owned = await Membership.countDocuments({ userId: user._id, role: 'owner', status: 'active' });
  if (owned >= MAX_OWNED_BUSINESSES) throw new AppError('CONFLICT', `You can own up to ${MAX_OWNED_BUSINESSES} businesses. Contact support to add more.`);

  let address = input.location.address;
  if (!address) address = (await (await provider('geo')).reverseGeocode(input.location.lat, input.location.lng)).address ?? undefined;

  const country = input.country ?? env.DEFAULT_COUNTRY;
  const company = await Company.create({
    name: input.name,
    businessType: input.businessType,
    ownerUserId: user._id,
    country,
    currency: input.currency ?? env.DEFAULT_CURRENCY,
    timezone: input.timezone ?? env.DEFAULT_TIMEZONE,
    location: { ...input.location, address },
    settings: { language: user.language ?? 'hi' },
  });
  const shift = await Shift.create({ companyId: company._id, name: 'General', start: input.openingTime, end: input.closingTime ?? addHours(input.openingTime, 10), weeklyOff: input.weeklyOff, isDefault: true });
  await Branch.create({ companyId: company._id, name: 'Main', geo: toGeoPoint(input.location), address, radiusM: 100, shiftId: shift._id, isDefault: true });
  const year = new Date().getFullYear();
  await seedHolidays(company._id, country, [year, year + 1]);

  const trial = await trialForNewBusiness(user._id);
  await Subscription.create({
    companyId: company._id,
    provider: 'internal',
    planCode: trial ? trial.planCode : 'free',
    status: trial ? 'trialing' : 'free',
    trialEndsAt: trial?.endsAt,
    currency: company.currency,
  });

  if (input.ownerName) user.name = input.ownerName;
  const membership = await Membership.create({ userId: user._id, companyId: company._id, role: 'owner' });
  await activate(user, membership);

  const ctx: Ctx = { userId: user._id, companyId: company._id, role: 'owner', employeeId: null, branchIds: [], actorName: user.name || user.phone, channel: 'app', language: 'hi' };
  await audit(ctx, { action: 'company.create', entity: 'company', entityId: company._id, after: company });
  // The device that created the business continues in it; its previous session token is retired.
  let deviceId = session.deviceId;
  if (session.refreshToken) {
    const old = await RefreshToken.findOneAndUpdate({ tokenHash: sha256(session.refreshToken), userId: user._id }, { revokedAt: new Date() });
    deviceId ??= old?.deviceId ?? undefined;
  }
  const tokens = await issueTokens(user, deviceId, undefined, membership);
  return {
    company: await companyView(company),
    ...tokens,
    activeMembershipId: String(membership._id),
    memberships: await membershipViews(await activeMemberships(user._id)),
  };
}

export async function getCompany(ctx: Ctx) {
  const c = await Company.findById(ctx.companyId);
  if (!c) throw notFound('Company');
  return c;
}

export async function updateCompany(ctx: Ctx, patch: { name?: string; businessType?: string; location?: { lat: number; lng: number; address?: string } }) {
  const c = await getCompany(ctx);
  const before = c.toObject();
  if (patch.name) c.name = patch.name;
  if (patch.businessType) c.businessType = patch.businessType;
  if (patch.location) c.location = patch.location as any;
  await c.save();
  await audit(ctx, { action: 'company.update', entity: 'company', entityId: c._id, before, after: c });
  return c;
}

export async function updateSettings(ctx: Ctx, patch: Record<string, unknown>) {
  const c = await getCompany(ctx);
  if (patch.faceMatchPolicy === 'review') {
    const { plan } = await companyPlan(c);
    if (!plan.features.includes('face_match')) throw new AppError('FEATURE_NOT_IN_PLAN', 'Face check needs the Growth plan or higher', { feature: 'face_match', planCode: plan.code });
  }
  const before = JSON.parse(JSON.stringify(c.settings));
  for (const [k, v] of Object.entries(patch)) (c.settings as any)[k] = v;
  await c.save();
  await audit(ctx, { action: 'company.settings.update', entity: 'company', entityId: c._id, before: { settings: before }, after: { settings: c.settings } });
  return c;
}

// ---- Branches ----
export async function listBranches(ctx: Ctx) {
  return (await Branch.find({ companyId: ctx.companyId, deletedAt: null }).sort({ createdAt: 1 }).lean()).map(branchView);
}

export async function createBranch(ctx: Ctx, input: { name: string; location: { lat: number; lng: number; address?: string }; radiusM?: number; shiftId?: string }) {
  const count = await Branch.countDocuments({ companyId: ctx.companyId, deletedAt: null });
  if (count >= 1) {
    const { plan } = await companyPlan({ _id: ctx.companyId });
    if (!plan.features.includes('branches')) throw new AppError('FEATURE_NOT_IN_PLAN', 'Multiple branches need the Growth plan', { feature: 'branches' });
  }
  const shiftId = input.shiftId ?? (await Shift.findOne({ companyId: ctx.companyId, isDefault: true }).lean())?._id;
  const b = await Branch.create({ companyId: ctx.companyId, name: input.name, geo: toGeoPoint(input.location), address: input.location.address, radiusM: input.radiusM ?? 100, shiftId });
  await audit(ctx, { action: 'branch.create', entity: 'branch', entityId: b._id, after: b });
  return branchView(b);
}

export async function updateBranch(ctx: Ctx, id: string, patch: { name?: string; location?: { lat: number; lng: number; address?: string }; radiusM?: number; shiftId?: string }) {
  const b = await Branch.findOne({ _id: id, companyId: ctx.companyId, deletedAt: null });
  if (!b) throw notFound('Branch');
  const before = b.toObject();
  if (patch.name) b.name = patch.name;
  if (patch.location) {
    b.geo = toGeoPoint(patch.location) as any;
    b.address = patch.location.address ?? b.address;
  }
  if (patch.radiusM) b.radiusM = patch.radiusM;
  if (patch.shiftId) {
    if (!(await Shift.exists({ _id: patch.shiftId, companyId: ctx.companyId }))) throw notFound('Shift');
    b.shiftId = new Types.ObjectId(patch.shiftId);
  }
  await b.save();
  await audit(ctx, { action: 'branch.update', entity: 'branch', entityId: b._id, before, after: b });
  return branchView(b);
}

// ---- Shifts ----
export async function listShifts(ctx: Ctx) {
  return (await Shift.find({ companyId: ctx.companyId, deletedAt: null }).sort({ createdAt: 1 }).lean()).map(shiftView);
}

export async function createShift(ctx: Ctx, input: { name: string; start: string; end: string; graceMinutes?: number | null; weeklyOff: number[] }) {
  const s = await Shift.create({ companyId: ctx.companyId, ...input });
  await audit(ctx, { action: 'shift.create', entity: 'shift', entityId: s._id, after: s });
  return shiftView(s);
}

export async function updateShift(ctx: Ctx, id: string, patch: Partial<{ name: string; start: string; end: string; graceMinutes: number | null; weeklyOff: number[] }>) {
  const s = await Shift.findOne({ _id: id, companyId: ctx.companyId, deletedAt: null });
  if (!s) throw notFound('Shift');
  const before = s.toObject();
  Object.assign(s, patch);
  await s.save();
  await audit(ctx, { action: 'shift.update', entity: 'shift', entityId: s._id, before, after: s });
  return shiftView(s);
}

// ---- Holidays ----
export async function listHolidays(ctx: Ctx, year?: number) {
  const filter: any = { companyId: ctx.companyId, deletedAt: null };
  if (year) filter.date = { $gte: `${year}-01-01`, $lte: `${year}-12-31` };
  return (await Holiday.find(filter).sort({ date: 1 }).lean()).map(holidayView);
}

export async function addHoliday(ctx: Ctx, date: string, name: string) {
  const existing = await Holiday.findOne({ companyId: ctx.companyId, date });
  if (existing && !existing.deletedAt) throw new AppError('CONFLICT', 'A holiday already exists on this date');
  const h = existing ?? new Holiday({ companyId: ctx.companyId, date, name });
  h.name = name;
  h.deletedAt = null;
  await h.save();
  await audit(ctx, { action: 'holiday.create', entity: 'holiday', entityId: h._id, after: h });
  return holidayView(h);
}

export async function deleteHoliday(ctx: Ctx, id: string) {
  const h = await Holiday.findOne({ _id: id, companyId: ctx.companyId, deletedAt: null });
  if (!h) throw notFound('Holiday');
  h.deletedAt = new Date();
  await h.save();
  await audit(ctx, { action: 'holiday.delete', entity: 'holiday', entityId: h._id, before: h });
}

// ---- CA / accountant access ----
export async function addAccountant(ctx: Ctx, phone: string, name: string) {
  const { plan } = await companyPlan({ _id: ctx.companyId });
  if (!plan.features.includes('ca_access')) throw new AppError('FEATURE_NOT_IN_PLAN', 'CA access needs the Pro plan', { feature: 'ca_access' });
  // An existing StaffMint user (owner elsewhere, another client's CA) simply gets one more membership.
  const u = (await User.findOne({ phone, deletedAt: null })) ?? (await User.create({ phone, name, role: 'owner', companyId: null }));
  const here = await Membership.findOne({ userId: u._id, companyId: ctx.companyId });
  if (here?.status === 'active') {
    const msg = here.role === 'ca' ? 'This number is already your accountant' : here.role === 'owner' ? 'This is the owner\'s own number' : 'This number is one of your staff. Use a different number for the accountant.';
    throw new AppError('CONFLICT', msg, { reason: `already_${here.role}` });
  }
  if (here) {
    here.set({ role: 'ca', status: 'active', employeeId: null, branchIds: [], deviceIds: [] });
    await here.save();
  } else {
    await Membership.create({ userId: u._id, companyId: ctx.companyId, role: 'ca' });
  }
  if (!u.companyId) await activate(u, await Membership.findOne({ userId: u._id, companyId: ctx.companyId }));
  await audit(ctx, { action: 'user.ca.add', entity: 'user', entityId: u._id, after: { phone, name, role: 'ca' } });
  return { id: String(u._id), phone, name: u.name || name, role: 'ca' };
}
