import { Types } from 'mongoose';
import { AppError, notFound } from '../../lib/errors.js';
import type { Ctx, Role } from '../../lib/context.js';
import { Company, DeviceRequest, Employee, Membership, User, type UserDoc } from '../../models/index.js';
import { audit } from '../audit/service.js';
import { getConfig } from '../config/service.js';
import { provider } from '../../providers/registry.js';
import { attachStaffMemberships, deviceAllowed, endMemberships, isStaffMembership, revokeMembershipSessions } from '../auth/memberships.js';
import { currentOrDefault, openSession } from '../auth/service.js';
import { notifyEmployee, notifyOwners, notifyUser, sendWhatsApp } from '../notifications/service.js';
import { assertEmployeeInScope, employeeScope } from '../employees/service.js';

type Session = { deviceId: string; refreshToken?: string };

async function loadUser(userId: Types.ObjectId | string): Promise<UserDoc> {
  const user = await User.findOne({ _id: userId, deletedAt: null });
  if (!user) throw new AppError('UNAUTHORIZED', 'User not found');
  return user;
}

/** Audit context for an action a person takes on one of their own accounts. */
const actorCtx = (user: UserDoc, companyId: Types.ObjectId, role: string): Ctx => ({
  userId: user._id,
  companyId,
  role: role as Role,
  employeeId: null,
  branchIds: [],
  actorName: user.name || user.phone,
  channel: 'app',
  language: (user.language as 'en' | 'hi') ?? 'hi',
});

// ---------------------------------------------------------------- notices

/** "Your access to X ended" has been seen. */
export async function dismissNotice(userId: Types.ObjectId | string, membershipId: string) {
  await Membership.updateOne({ _id: membershipId, userId, status: 'inactive' }, { noticeDismissedAt: new Date() });
}

/** Businesses this person closed that can still be restored. */
export async function closedBusinesses(userId: Types.ObjectId | string) {
  const list = await Company.find({ ownerUserId: userId, closedAt: { $ne: null }, restoreUntil: { $gt: new Date() } }).select('name businessType closedAt restoreUntil').lean();
  return list.map((c) => ({ companyId: String(c._id), companyName: c.name, businessType: c.businessType, closedAt: c.closedAt, restoreUntil: c.restoreUntil }));
}

// ------------------------------------------------------------------ leave

/** Staff, manager or accountant stops working with a business. Owners close or (later) transfer instead. */
export async function leaveAccount(userId: Types.ObjectId | string, membershipId: string, session: Session) {
  const user = await loadUser(userId);
  const m = await Membership.findOne({ _id: membershipId, userId: user._id, status: 'active' });
  if (!m) throw notFound('Account');
  if (m.role === 'owner') {
    // Co-owners can step away; the main owner transfers or closes instead.
    const company = await Company.findById(m.companyId).select('ownerUserId').lean();
    if (String(company?.ownerUserId) === String(user._id)) {
      throw new AppError('CONFLICT', 'The main owner cannot leave. Transfer the business or close it from Settings.', { reason: 'owner_cannot_leave' });
    }
  }
  await endMemberships({ _id: m._id }, 'left');
  const who = user.name || user.phone;
  await notifyOwners(m.companyId, {
    template: 'member_left',
    title: `${who} left your business on StaffMint`,
    titleHi: `${who} ने StaffMint पर आपका बिज़नेस छोड़ दिया`,
    body: m.role === 'ca' ? 'Their accountant access has ended.' : 'They can no longer check in. Mark their exit from the staff profile when you are ready.',
    bodyHi: m.role === 'ca' ? 'उनकी अकाउंटेंट पहुँच ख़त्म हो गई है।' : 'वे अब हाज़िरी नहीं लगा सकते। स्टाफ़ प्रोफ़ाइल से उनकी छुट्टी दर्ज करें।',
    data: { kind: 'member_left', ...(m.employeeId ? { employeeId: String(m.employeeId) } : {}) },
  });
  await audit(actorCtx(user, m.companyId, m.role), { action: 'account.leave', entity: 'membership', entityId: m._id, after: { role: m.role } });
  return openSession(user, await currentOrDefault(user, session.deviceId, session.refreshToken), session.deviceId, session.refreshToken);
}

// ------------------------------------------------------- close / restore

/** Owner closes a business: everyone's access ends, data is kept for the restore window. */
export async function closeBusiness(ctx: Ctx, confirmName: string, session: Session) {
  const company = await Company.findById(ctx.companyId);
  if (!company || company.closedAt) throw notFound('Business');
  if (String(company.ownerUserId) !== String(ctx.userId)) throw new AppError('FORBIDDEN', 'Only the main owner can close the business');
  if (confirmName.trim().toLowerCase() !== company.name.trim().toLowerCase()) {
    throw new AppError('VALIDATION_ERROR', 'Type the business name exactly to confirm', { field: 'confirmName' });
  }
  const days = await getConfig<number>('accounts.restoreDays');
  const now = new Date();
  // Tell everyone else first, while their accounts still point at this business.
  const others = await Membership.find({ companyId: company._id, status: 'active', userId: { $ne: ctx.userId } }).select('userId').lean();
  const users = others.length ? await User.find({ _id: { $in: others.map((m) => m.userId) } }).lean() : [];
  for (const u of users) {
    await notifyUser(company._id, u, {
      template: 'business_closed',
      title: `${company.name} has closed its StaffMint account`,
      titleHi: `${company.name} ने अपना StaffMint खाता बंद कर दिया है`,
      body: 'Your access to this business has ended.',
      bodyHi: 'इस बिज़नेस तक आपकी पहुँच ख़त्म हो गई है।',
      data: { kind: 'business_closed' },
    });
  }
  try {
    const { cancel } = await import('../billing/service.js');
    await cancel(ctx);
  } catch {
    /* no paid subscription */
  }
  company.closedAt = now;
  company.restoreUntil = new Date(now.getTime() + days * 86400_000);
  company.deletedAt = now; // background jobs skip it
  await company.save();
  await endMemberships({ companyId: company._id }, 'closed');
  await audit(ctx, { action: 'company.close', entity: 'company', entityId: company._id, after: { restoreUntil: company.restoreUntil } });
  const user = await loadUser(ctx.userId!);
  return openSession(user, await currentOrDefault(user, session.deviceId), session.deviceId, session.refreshToken);
}

/** Undo a close within the restore window: everyone who had access gets it back. */
export async function restoreBusiness(userId: Types.ObjectId | string, companyId: string, session: Session) {
  const user = await loadUser(userId);
  const company = await Company.findOne({ _id: companyId, ownerUserId: user._id, closedAt: { $ne: null } });
  if (!company) throw notFound('Business');
  if (!company.restoreUntil || company.restoreUntil < new Date()) throw new AppError('CONFLICT', 'The restore window for this business has passed');
  const closedAt = company.closedAt!;
  company.closedAt = null;
  company.restoreUntil = null;
  company.deletedAt = null;
  company.cancelledAt = null;
  await company.save();
  await Membership.updateMany(
    { companyId: company._id, status: 'inactive', endedReason: 'closed', endedAt: { $gte: new Date(closedAt.getTime() - 60_000) } },
    { status: 'active', endedAt: null, endedReason: null, noticeDismissedAt: null },
  );
  const owner = await Membership.findOne({ companyId: company._id, userId: user._id, status: 'active' });
  await audit(actorCtx(user, company._id, 'owner'), { action: 'company.restore', entity: 'company', entityId: company._id });
  return openSession(user, owner, session.deviceId, session.refreshToken);
}

// --------------------------------------------------------- device change

const requestView = (r: any, name?: string | null) => ({
  id: String(r._id),
  employeeId: r.employeeId ? String(r.employeeId) : null,
  employeeName: name ?? null,
  deviceName: r.deviceName ?? null,
  status: r.status,
  createdAt: r.createdAt,
});

/** Staff whose account is locked to an old phone asks the owner to approve this one. */
export async function requestDeviceChange(userId: Types.ObjectId | string, input: { membershipId: string; deviceId: string; deviceName?: string }) {
  const user = await loadUser(userId);
  const m = await Membership.findOne({ _id: input.membershipId, userId: user._id, status: 'active' });
  if (!m || !isStaffMembership(m)) throw notFound('Staff account');
  if (deviceAllowed(m, input.deviceId)) return { status: 'not_needed' as const };
  await DeviceRequest.updateMany({ companyId: m.companyId, membershipId: m._id, status: 'pending' }, { status: 'cancelled' });
  const r = await DeviceRequest.create({ companyId: m.companyId, membershipId: m._id, employeeId: m.employeeId, userId: user._id, deviceId: input.deviceId, deviceName: input.deviceName ?? null });
  const emp = m.employeeId ? await Employee.findOne({ _id: m.employeeId, companyId: m.companyId }).select('name').lean() : null;
  const who = emp?.name || user.name || user.phone;
  await notifyOwners(m.companyId, {
    template: 'device_request',
    title: `${who} wants to use a new phone`,
    titleHi: `${who} नया फ़ोन इस्तेमाल करना चाहते हैं`,
    body: 'Approve it from Needs you so they can check in.',
    bodyHi: '“आपके लिए” से मंज़ूरी दें ताकि वे हाज़िरी लगा सकें।',
    data: { kind: 'device_request', requestId: String(r._id) },
  });
  await audit(actorCtx(user, m.companyId, m.role), { action: 'device.request', entity: 'employee', entityId: m.employeeId ?? m._id, after: { deviceName: input.deviceName ?? null } });
  return { status: 'pending' as const, request: requestView(r, who) };
}

export async function listDeviceRequests(ctx: Ctx) {
  const scope = await Employee.find(employeeScope(ctx)).select('_id name').lean();
  const names = new Map(scope.map((e) => [String(e._id), e.name]));
  const list = await DeviceRequest.find({ companyId: ctx.companyId, status: 'pending', employeeId: { $in: scope.map((e) => e._id) } }).sort({ createdAt: 1 }).lean();
  return list.map((r) => requestView(r, names.get(String(r.employeeId))));
}

export async function decideDeviceRequest(ctx: Ctx, id: string, approve: boolean) {
  const r = await DeviceRequest.findOne({ _id: id, companyId: ctx.companyId, status: 'pending' });
  if (!r) throw notFound('Request');
  const emp = await assertEmployeeInScope(ctx, r.employeeId!);
  r.status = approve ? 'approved' : 'rejected';
  r.decidedBy = ctx.userId;
  r.decidedAt = new Date();
  await r.save();
  if (approve) {
    await Membership.updateOne({ _id: r.membershipId, companyId: ctx.companyId }, { deviceIds: [r.deviceId] });
    await revokeMembershipSessions([r.membershipId]); // the old phone leaves this staff account
  }
  await notifyEmployee(ctx.companyId, emp._id, {
    template: approve ? 'device_approved' : 'device_rejected',
    title: approve ? 'Your new phone is approved' : 'New phone not approved',
    titleHi: approve ? 'आपका नया फ़ोन मंज़ूर हो गया' : 'नया फ़ोन मंज़ूर नहीं हुआ',
    body: approve ? 'Open StaffMint on it to check in.' : 'Talk to your employer.',
    bodyHi: approve ? 'हाज़िरी के लिए उस पर StaffMint खोलें।' : 'अपने मालिक से बात करें।',
    data: { kind: approve ? 'device_approved' : 'device_rejected' },
  });
  await audit(ctx, { action: approve ? 'device.approve' : 'device.reject', entity: 'employee', entityId: emp._id, after: { deviceName: r.deviceName } });
  return requestView(r, emp.name);
}

// ------------------------------------------------------------ accountants

export async function listAccountants(ctx: Ctx) {
  const ms = await Membership.find({ companyId: ctx.companyId, role: 'ca', status: 'active' }).sort({ createdAt: 1 }).lean();
  const users = await User.find({ _id: { $in: ms.map((m) => m.userId) } }).select('name phone').lean();
  const byId = new Map(users.map((u) => [String(u._id), u]));
  return ms.map((m) => ({ id: String(m._id), name: byId.get(String(m.userId))?.name ?? '', phone: byId.get(String(m.userId))?.phone ?? '', addedAt: (m as any).createdAt }));
}

export async function removeAccountant(ctx: Ctx, membershipId: string) {
  const m = await Membership.findOne({ _id: membershipId, companyId: ctx.companyId, role: 'ca', status: 'active' });
  if (!m) throw notFound('Accountant');
  await endMemberships({ _id: m._id }, 'removed');
  await audit(ctx, { action: 'user.ca.remove', entity: 'membership', entityId: m._id });
}

// ---------------------------------------------------------------- invite

const INVITE_GAP_MS = 10 * 60_000;

/**
 * WhatsApp the staff member their invite: business name, their number and the
 * app link. Re-inviting also lets back in someone who had left.
 */
export async function inviteStaff(ctx: Ctx, employeeId: string | Types.ObjectId, opts: { auto?: boolean } = {}) {
  const emp = await assertEmployeeInScope(ctx, employeeId);
  if (emp.status !== 'active') throw new AppError('CONFLICT', 'Reactivate this staff member before inviting them');
  const company = await Company.findById(ctx.companyId).select('name messagingProvider').lean();
  const link = await getConfig<string>('app.downloadUrl', ctx.companyId);
  const whatsappConnected = (await provider('messaging', company?.messagingProvider)).name !== 'mock';
  if (!opts.auto && emp.invitedAt && Date.now() - emp.invitedAt.getTime() < INVITE_GAP_MS) {
    // The owner can still send it from their own WhatsApp.
    throw new AppError('RATE_LIMITED', 'Invite already sent. You can send it again in a few minutes.', { shareText: inviteText(emp, company?.name ?? '', link), whatsappConnected });
  }
  const n = await sendWhatsApp(ctx.companyId, emp.phone, { template: 'staff_invite', params: [emp.name, company?.name ?? '', emp.phone, link] }, { employeeId: emp._id, language: emp.language as 'en' | 'hi' });
  emp.invitedAt = new Date();
  await emp.save();
  const login = await User.findOne({ phone: emp.phone, deletedAt: null });
  if (login) await attachStaffMemberships(login, { force: [emp._id] });
  if (!opts.auto) await audit(ctx, { action: 'employee.invite', entity: 'employee', entityId: emp._id });
  return { invitedAt: emp.invitedAt, delivered: n.status === 'sent', whatsappConnected, shareText: inviteText(emp, company?.name ?? '', link) };
}

/** The invite in words, for the owner to send from their own WhatsApp or SMS when the business WhatsApp can't. */
function inviteText(emp: { name: string; phone: string; language?: string | null }, business: string, link: string) {
  const phone = emp.phone.replace(/^\+91/, '');
  return emp.language === 'en'
    ? `Namaste ${emp.name}, ${business} has added you on StaffMint for attendance and salary. Download the app: ${link} and log in with your number ${phone}.`
    : `नमस्ते ${emp.name}, ${business} ने आपको हाज़िरी और सैलरी के लिए StaffMint पर जोड़ा है। ऐप डाउनलोड करें: ${link} और अपने नंबर ${phone} से लॉग इन करें।`;
}


/**
 * "Remind" on Home: re-sends the app invite to every active staff member who hasn't joined yet (also those the
 * owner marks attendance for: they still use the app to see their attendance and salary). Says per person what
 * happened, with the invite text so the owner can send it from their own WhatsApp when ours couldn't.
 */
export async function remindNotJoined(ctx: Ctx) {
  const emps = await Employee.find({ ...employeeScope(ctx), status: 'active', userId: null }).select('_id name phone language invitedAt').sort({ name: 1 }).lean();
  const company = await Company.findById(ctx.companyId).select('name messagingProvider').lean();
  const link = await getConfig<string>('app.downloadUrl', ctx.companyId);
  let sent = 0;
  let skipped = 0;
  let failed = 0;
  const people: { employeeId: string; name: string; phone: string; status: 'sent' | 'recent' | 'failed'; shareText: string }[] = [];
  for (const e of emps) {
    const base = { employeeId: String(e._id), name: e.name, phone: e.phone, shareText: inviteText(e, company?.name ?? '', link) };
    if (e.invitedAt && Date.now() - new Date(e.invitedAt).getTime() < INVITE_GAP_MS) {
      skipped++;
      people.push({ ...base, status: 'recent' });
      continue;
    }
    const r = await inviteStaff(ctx, e._id, { auto: true });
    if (r.delivered) sent++;
    else failed++;
    people.push({ ...base, status: r.delivered ? 'sent' : 'failed' });
  }
  if (sent || failed) await audit(ctx, { action: 'employee.invite_all', entity: 'employee', after: { sent, failed } });
  // Not connected yet (development, or keys not set): nothing really reaches their phone, so the app says so.
  const whatsappConnected = (await provider('messaging', company?.messagingProvider)).name !== 'mock';
  return { sent, skipped, failed, people, whatsappConnected };
}


// ------------------------------------------------------------ Phase 4

/** Pin an account to the top of the chooser (accountants with many clients). */
export async function pinAccount(userId: Types.ObjectId | string, membershipId: string, pinned: boolean) {
  const r = await Membership.updateOne({ _id: membershipId, userId, status: 'active' }, { pinnedAt: pinned ? new Date() : null });
  if (!r.matchedCount) throw notFound('Account');
}

/**
 * Accountant's clients at a glance: every business they are CA for, with
 * staff and last month's payroll state, so the month-end round needs no
 * switching just to see who is ready.
 */
export async function caClients(userId: Types.ObjectId | string) {
  const ms = await Membership.find({ userId, role: 'ca', status: 'active' }).lean();
  const companies = await Company.find({ _id: { $in: ms.map((m) => m.companyId) }, closedAt: null }).select('name businessType timezone').lean();
  const { PayrollRun } = await import('../../models/index.js');
  const { previousMonth, todayIn } = await import('../../lib/dates.js');
  const { activeStaffCount } = await import('../billing/plans.js');
  const out = [];
  for (const c of companies) {
    const m = ms.find((x) => String(x.companyId) === String(c._id))!;
    const month = previousMonth(todayIn(c.timezone ?? 'Asia/Kolkata').slice(0, 7));
    const run = await PayrollRun.findOne({ companyId: c._id, month, status: { $ne: 'superseded' } }).sort({ revision: -1 }).lean();
    out.push({
      membershipId: String(m._id),
      companyId: String(c._id),
      companyName: c.name,
      businessType: c.businessType ?? null,
      pinned: !!m.pinnedAt,
      staffCount: await activeStaffCount(c._id),
      month,
      payrollStatus: run?.status ?? 'not_started',
      netPaise: run?.totals?.netPaise ?? null,
    });
  }
  return out.sort((a, b) => Number(b.pinned) - Number(a.pinned) || a.companyName.localeCompare(b.companyName));
}
