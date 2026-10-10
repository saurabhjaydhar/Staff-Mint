import { Types } from 'mongoose';
import { logger } from '../../lib/logger.js';
import { Company, Employee, Membership, RefreshToken, type MembershipDoc, type UserDoc } from '../../models/index.js';

export type MembershipRole = 'owner' | 'manager' | 'employee' | 'ca';
const STAFF_ROLES = ['employee', 'manager'];

export const isStaffMembership = (m: { role: string }) => STAFF_ROLES.includes(m.role);
const isWebDevice = (deviceId?: string | null) => !!deviceId && deviceId.startsWith('web-');

/**
 * Accounts created before memberships kept a single business on the user.
 * Turn that into a membership once, so nothing has to be migrated by hand.
 */
export async function ensureLegacyMembership(user: UserDoc): Promise<void> {
  if (!user.companyId) return;
  if (await Membership.exists({ userId: user._id, companyId: user.companyId })) return;
  let status: 'active' | 'inactive' = 'active';
  if (user.employeeId) {
    const emp = await Employee.findOne({ _id: user.employeeId, companyId: user.companyId }).lean();
    if (!emp || emp.status !== 'active' || emp.deletedAt) status = 'inactive';
  }
  await Membership.create({
    userId: user._id,
    companyId: user.companyId,
    role: user.role,
    employeeId: user.employeeId ?? null,
    branchIds: user.branchIds ?? [],
    deviceIds: isStaffMembership(user) ? user.deviceIds ?? [] : [],
    status,
    lastUsedAt: user.lastLoginAt ?? null,
  }).catch((e: any) => {
    if (e?.code !== 11000) throw e; // another request created it first
  });
}

/**
 * Every active staff record with this phone, in any business, becomes (or
 * stays) a staff membership. Covers numbers added before they first logged
 * in, and people who work at more than one shop. Returns how many it added.
 */
export async function attachStaffMemberships(user: UserDoc, opts: { force?: (Types.ObjectId | string)[] } = {}): Promise<number> {
  // Records whose number was found to be recycled wait for the owner to update the number.
  const emps = await Employee.find({ phone: user.phone, status: 'active', deletedAt: null, phoneRecycledAt: null }).setOptions({ skipTenant: true });
  if (!emps.length) return 0;
  const closed = new Set(
    (await Company.find({ _id: { $in: emps.map((e) => e.companyId) }, closedAt: { $ne: null } }).select('_id').lean()).map((c) => String(c._id)),
  );
  const forced = new Set((opts.force ?? []).map(String));
  let added = 0;
  for (const emp of emps) {
    if (closed.has(String(emp.companyId))) continue; // a closed business gives no access
    const existing = await Membership.findOne({ userId: user._id, companyId: emp.companyId });
    if (existing && (existing.role === 'owner' || existing.role === 'ca')) continue; // never downgrade an owner/CA
    // Someone who left stays out until the owner adds them again (re-invite or reactivate).
    if (existing?.status === 'inactive' && existing.endedReason === 'left' && String(existing.employeeId) === String(emp._id) && !forced.has(String(emp._id))) continue;
    const role = (emp.appRole ?? 'employee') as MembershipRole;
    const branchIds = role === 'manager' && emp.branchId ? [emp.branchId] : [];
    if (existing) {
      const changed = existing.status !== 'active' || String(existing.employeeId) !== String(emp._id);
      if (changed) {
        existing.status = 'active';
        existing.employeeId = emp._id;
        existing.role = role;
        existing.branchIds = branchIds as any;
        existing.deviceIds = [];
        existing.endedAt = null;
        existing.endedReason = null;
        existing.noticeDismissedAt = null;
        await existing.save();
        added++;
      }
    } else {
      await Membership.create({ userId: user._id, companyId: emp.companyId, role, employeeId: emp._id, branchIds });
      added++;
    }
    if (String(emp.userId) !== String(user._id)) {
      emp.userId = user._id;
      await emp.save();
    }
    if (!user.name) user.name = emp.name;
  }
  if (added) logger.info({ userId: user._id, added }, 'Staff memberships attached');
  return added;
}

/** Active memberships, most recently used first. */
export async function activeMemberships(userId: Types.ObjectId) {
  return Membership.find({ userId, status: 'active' }).sort({ lastUsedAt: -1, createdAt: -1 });
}

/** Small summary for choosers and switchers. */
export async function membershipViews(
  list: { _id: Types.ObjectId; companyId: Types.ObjectId; role: string; employeeId?: Types.ObjectId | null; lastUsedAt?: Date | null; deviceIds?: string[] | null }[],
  deviceId?: string | null,
) {
  const companies = await Company.find({ _id: { $in: list.map((m) => m.companyId) } }).select('name businessType').lean();
  const names = new Map(companies.map((c) => [String(c._id), c]));
  return list.map((m) => ({
    id: String(m._id),
    companyId: String(m.companyId),
    companyName: names.get(String(m.companyId))?.name ?? '',
    businessType: names.get(String(m.companyId))?.businessType ?? null,
    role: m.role,
    lastUsedAt: m.lastUsedAt ?? null,
    /** Pinned to the top of the chooser. */
    pinned: !!(m as { pinnedAt?: Date | null }).pinnedAt,
    /** Staff account bound to another phone (only known when the device is). */
    lockedToOtherPhone: deviceId ? !deviceAllowed(m, deviceId) : false,
  }));
}

/** Staff phone binding: the first phone used for a staff membership is the only one allowed after that. */
export function deviceAllowed(m: { role: string; deviceIds?: string[] | null }, deviceId?: string | null) {
  if (!isStaffMembership(m) || isWebDevice(deviceId) || !deviceId) return true;
  const ids = m.deviceIds ?? [];
  return ids.length === 0 || ids.includes(deviceId);
}

export async function bindDevice(m: MembershipDoc, deviceId?: string | null) {
  if (!isStaffMembership(m) || isWebDevice(deviceId) || !deviceId) return;
  if ((m.deviceIds ?? []).length === 0) {
    m.deviceIds = [deviceId];
    await m.save();
  }
}

/**
 * Open a membership: mirror it onto the user (for older code paths that read
 * user.role / user.companyId) and remember it as the last used.
 */
export async function activate(user: UserDoc, m: MembershipDoc | null) {
  if (m) {
    user.role = m.role;
    user.companyId = m.companyId;
    user.employeeId = m.employeeId ?? null;
    user.branchIds = (m.branchIds ?? []) as any;
    m.lastUsedAt = new Date();
    await m.save();
  } else {
    user.role = 'owner';
    user.companyId = null;
    user.employeeId = null;
    user.branchIds = [] as any;
  }
  await user.save();
}

/** Picks the membership a new session opens in: the most recent one this device may use. */
export async function defaultMembership(user: UserDoc, deviceId?: string | null) {
  const list = await activeMemberships(user._id);
  const usable = list.find((m) => deviceAllowed(m, deviceId)) ?? null;
  // Staff accounts locked to another phone: the app offers "Request device change" instead of a dead end.
  const blocked = list.filter((m) => !deviceAllowed(m, deviceId));
  return { list, chosen: usable, blocked };
}

/** Log out every device session open in these memberships. */
export async function revokeMembershipSessions(membershipIds: (Types.ObjectId | string)[]) {
  if (!membershipIds.length) return;
  await RefreshToken.updateMany({ membershipId: { $in: membershipIds }, revokedAt: null }, { revokedAt: new Date() });
}

export type EndReason = 'removed' | 'left' | 'closed' | 'phone_changed' | 'import_rollback';

/**
 * End access. Sessions are not logged out: their next request is told the
 * account changed and their refresh moves them to another account (or to
 * "no business" with a notice) — removal from one shop never logs anyone
 * out of the others.
 */
export async function endMemberships(filter: Record<string, unknown>, reason: EndReason) {
  return Membership.updateMany({ ...filter, status: 'active' }, { status: 'inactive', endedAt: new Date(), endedReason: reason, noticeDismissedAt: null });
}

/** End staff access to a business (deactivation, removal, phone change). */
export async function deactivateStaffMemberships(companyId: Types.ObjectId, employeeIds: Types.ObjectId[], reason: EndReason = 'removed') {
  await endMemberships({ companyId, employeeId: { $in: employeeIds } }, reason);
}

/** Recently ended accounts the person hasn't been told about yet (last 30 days; leaving was their own choice). */
export async function endedNotices(userId: Types.ObjectId) {
  const list = await Membership.find({
    userId,
    status: 'inactive',
    endedReason: { $in: ['removed', 'closed', 'phone_changed', 'import_rollback'] },
    endedAt: { $gte: new Date(Date.now() - 30 * 86400_000) },
    noticeDismissedAt: null,
  })
    .sort({ endedAt: -1 })
    .limit(5)
    .lean();
  const views = await membershipViews(list);
  return views.map((v, i) => ({ ...v, endedAt: list[i].endedAt, endedReason: list[i].endedReason }));
}
