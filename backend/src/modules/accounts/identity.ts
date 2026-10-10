import { randomUUID } from 'node:crypto';
import { Types } from 'mongoose';
import { AppError, notFound } from '../../lib/errors.js';
import { logger } from '../../lib/logger.js';
import { Company, Employee, Membership, Payslip, RecoveryRequest, User, type UserDoc } from '../../models/index.js';
import { provider } from '../../providers/registry.js';
import { audit } from '../audit/service.js';
import { getConfig } from '../config/service.js';
import { completeLogin, consumeOtp, createCode, currentOrDefault, openSession, revokeAllForUser, verifyIdentityToken } from '../auth/service.js';
import { endMemberships, membershipViews } from '../auth/memberships.js';
import { notifyOwners, notifyUser } from '../notifications/service.js';
import { payslipView } from '../payslips/views.js';
import { systemCtx } from '../../lib/context.js';

type Session = { deviceId: string; refreshToken?: string };

async function loadUser(id: Types.ObjectId | string): Promise<UserDoc> {
  const u = await User.findOne({ _id: id, deletedAt: null });
  if (!u) throw new AppError('UNAUTHORIZED', 'User not found');
  return u;
}

const last4 = (p: string) => p.slice(-4);

async function textNumber(phone: string, text: string) {
  try {
    await (await provider('messaging')).sendText(phone, text);
  } catch (err) {
    logger.warn({ err }, 'account notice send failed');
  }
}

// ------------------------------------------------- recycled numbers (row 12)

/** "Yes, this is me": continue the login that was paused. */
export async function confirmIdentity(token: string) {
  const { sub, did } = verifyIdentityToken(token);
  return completeLogin(await loadUser(sub), did);
}

/**
 * "No, not me": the number now belongs to someone new. The previous person's
 * staff accounts end (their employers are told to update the number) and the
 * new person starts fresh. Owner accounts stay with the previous person, who
 * can recover them from their new number.
 */
export async function rejectIdentity(token: string) {
  const { sub, did } = verifyIdentityToken(token);
  const old = await loadUser(sub);
  const phone = old.phone;
  old.phone = `recycled:${phone}:${Date.now()}`;
  await old.save();
  const staff = await Membership.find({ userId: old._id, status: 'active', role: { $in: ['employee', 'manager'] } }).lean();
  await endMemberships({ _id: { $in: staff.map((m) => m._id) } }, 'phone_changed');
  const emps = await Employee.find({ userId: old._id, phone, deletedAt: null }).setOptions({ skipTenant: true });
  for (const e of emps) {
    e.phoneRecycledAt = new Date();
    e.userId = null;
    await e.save();
    await notifyOwners(e.companyId, {
      template: 'staff_number_recycled',
      title: `${e.name}'s number now belongs to someone else`,
      titleHi: `${e.name} का नंबर अब किसी और के पास है`,
      body: 'Update their mobile number in the staff profile so they can log in again.',
      bodyHi: 'स्टाफ़ प्रोफ़ाइल में उनका मोबाइल नंबर बदलें ताकि वे फिर से लॉग इन कर सकें।',
      data: { kind: 'staff_number_recycled', employeeId: String(e._id) },
    });
    await audit(systemCtx(e.companyId), { action: 'employee.phone_recycled', entity: 'employee', entityId: e._id });
  }
  const fresh = await User.create({ phone, name: '', role: 'owner', companyId: null });
  return completeLogin(fresh, did);
}

// ------------------------------------------------- identity move (row 11)

/**
 * The person proved who they are from a new number: the account (every
 * business, every staff record) moves to it. The placeholder login the new
 * number created is retired; sessions on the lost phone end.
 */
async function moveIdentity(oldUser: UserDoc, newUser: UserDoc, why: string) {
  if (String(oldUser._id) === String(newUser._id)) throw new AppError('CONFLICT', 'This is already your number');
  if (await Membership.exists({ userId: newUser._id, status: 'active' })) {
    throw new AppError('CONFLICT', 'This new number already has its own accounts. Contact support to merge them.', { reason: 'new_number_in_use' });
  }
  const newPhone = newUser.phone;
  const oldPhone = oldUser.phone;
  newUser.phone = `merged:${newUser._id}:${Date.now()}`;
  newUser.deletedAt = new Date();
  await newUser.save();
  await revokeAllForUser(newUser._id);
  oldUser.phone = newPhone;
  await oldUser.save();
  const emps = await Employee.find({ userId: oldUser._id, deletedAt: null }).setOptions({ skipTenant: true });
  for (const e of emps) {
    e.phone = newPhone;
    await e.save().catch((err) => logger.warn({ err, employeeId: e._id }, 'staff phone not moved'));
  }
  await revokeAllForUser(oldUser._id);
  if (!oldPhone.includes(':')) await textNumber(oldPhone, `StaffMint: your account moved to the number ending ${last4(newPhone)}. If this was not you, contact support right away.`);
  const owned = await Membership.find({ userId: oldUser._id, status: 'active' }).select('companyId role').lean();
  for (const m of owned) {
    await audit(systemCtx(m.companyId), { action: 'account.number_moved', entity: 'user', entityId: oldUser._id, before: { phone: oldPhone }, after: { phone: newPhone, why } });
  }
}

/** Step 2 of owner recovery: a code to the email on the lost account's profile. */
export async function requestEmailRecovery(userId: string, rawEmail: string) {
  const me = await loadUser(userId);
  const email = rawEmail.trim().toLowerCase();
  const old = await User.findOne({ email, deletedAt: null, _id: { $ne: me._id } }).lean();
  // Same answer either way, so nobody can test which emails have accounts.
  if (!old) return { sent: true as const };
  const { code, mock } = await createCode(`email:${email}`, 'email');
  try {
    await (await provider('email')).send(email, 'Your StaffMint recovery code', `<p>Your code to move your StaffMint account to a new number is <b>${code}</b>.</p><p>If you did not ask for this, ignore this email.</p>`);
  } catch (err) {
    logger.warn({ err }, 'recovery email failed');
  }
  return { sent: true as const, ...(mock ? { devCode: code } : {}) };
}

export async function verifyEmailRecovery(userId: string, input: { email: string; code: string } & Session) {
  const me = await loadUser(userId);
  const email = input.email.trim().toLowerCase();
  await consumeOtp(`email:${email}`, input.code);
  const old = await User.findOne({ email, deletedAt: null, _id: { $ne: me._id } });
  if (!old) throw new AppError('OTP_INVALID', 'Wrong code');
  await moveIdentity(old, me, 'email');
  return openSession(old, await currentOrDefault(old, input.deviceId), input.deviceId);
}

// ------------------------------------------------- support recovery (row 11)

const recoveryView = (r: any) => ({
  id: String(r._id),
  oldPhoneMasked: `•••• ${last4(r.oldPhone)}`,
  businessName: r.businessName,
  status: r.status,
  holdUntil: r.holdUntil ?? null,
  note: r.note ?? null,
  createdAt: r.createdAt,
});

/** From the new number: ask support to move the account. Needs 2 of 3 proofs. */
export async function submitRecovery(
  userId: string,
  input: { oldPhone: string; businessName: string; gstin?: string; paymentTxnId?: string; selfieVideoBase64?: string },
) {
  const me = await loadUser(userId);
  const proofs = [input.gstin?.trim(), input.paymentTxnId?.trim(), input.selfieVideoBase64].filter(Boolean).length;
  if (proofs < 2) throw new AppError('VALIDATION_ERROR', 'Give at least 2 of the 3 proofs', { reason: 'need_two_proofs' });
  const old = await User.findOne({ phone: input.oldPhone, deletedAt: null }).lean();
  if (!old || String(old._id) === String(me._id)) throw new AppError('NOT_FOUND', 'No StaffMint account uses that old number');
  if (await RecoveryRequest.exists({ requesterUserId: me._id, status: { $in: ['submitted', 'hold'] } })) {
    throw new AppError('CONFLICT', 'You already have a recovery request in progress');
  }
  let selfieVideoKey: string | null = null;
  if (input.selfieVideoBase64) {
    const buf = Buffer.from(input.selfieVideoBase64.replace(/^data:video\/[\w-]+;base64,/, ''), 'base64');
    if (buf.length > 8 * 1024 * 1024) throw new AppError('VALIDATION_ERROR', 'Video is too large (max 8 MB)');
    selfieVideoKey = `recovery/${me._id}/${randomUUID()}.mp4`;
    await (await provider('storage')).put(selfieVideoKey, buf, 'video/mp4');
  }
  const r = await RecoveryRequest.create({
    requesterUserId: me._id,
    oldUserId: old._id,
    oldPhone: old.phone,
    businessName: input.businessName.trim(),
    gstin: input.gstin?.trim() || null,
    paymentTxnId: input.paymentTxnId?.trim() || null,
    selfieVideoKey,
  });
  logger.info({ requestId: r._id }, 'Support recovery requested');
  return recoveryView(r);
}

export async function myRecoveries(userId: string) {
  return (await RecoveryRequest.find({ requesterUserId: userId }).sort({ createdAt: -1 }).limit(5).lean()).map(recoveryView);
}

/** Support (admin API): list requests with what the requester gave. */
export async function adminListRecoveries(status?: string) {
  const filter: Record<string, unknown> = status ? { status } : {};
  const list = await RecoveryRequest.find(filter).sort({ createdAt: -1 }).limit(100).lean();
  const storage = await provider('storage');
  return Promise.all(
    list.map(async (r) => ({
      ...recoveryView(r),
      oldPhone: r.oldPhone,
      gstin: r.gstin,
      paymentTxnId: r.paymentTxnId,
      selfieVideoUrl: r.selfieVideoKey ? await storage.signedUrl(r.selfieVideoKey, 900) : null,
    })),
  );
}

/** Support approved the proofs: start the hold and tell everyone who could object. */
export async function adminApproveRecovery(id: string) {
  const r = await RecoveryRequest.findOne({ _id: id, status: 'submitted' });
  if (!r) throw notFound('Recovery request');
  const days = await getConfig<number>('accounts.recoveryHoldDays');
  const owned = await Company.find({ ownerUserId: r.oldUserId, closedAt: null }).select('_id name').lean();
  r.status = 'hold';
  r.holdUntil = new Date(Date.now() + days * 86400_000);
  r.companyIds = owned.map((c) => c._id) as any;
  r.decidedAt = new Date();
  await r.save();
  await textNumber(r.oldPhone, `StaffMint: someone asked to move your account to a new number. If this is not you, open StaffMint and stop it within ${days} days.`);
  for (const c of owned) {
    const ms = await Membership.find({ companyId: c._id, status: 'active', role: { $in: ['manager', 'ca', 'owner'] }, userId: { $ne: r.oldUserId } }).select('userId').lean();
    const people = await User.find({ _id: { $in: ms.map((m) => m.userId) } }).lean();
    for (const u of people) {
      await notifyUser(c._id, u, {
        template: 'recovery_hold',
        title: `${c.name}: owner account is being recovered`,
        titleHi: `${c.name}: मालिक का खाता वापस लिया जा रहा है`,
        body: `It moves to a new number in ${days} days. Stop it from StaffMint if this looks wrong.`,
        bodyHi: `${days} दिन में यह नए नंबर पर चला जाएगा। गलत लगे तो StaffMint से रोकें।`,
        data: { kind: 'recovery_hold', requestId: String(r._id) },
      });
    }
    await audit(systemCtx(c._id), { action: 'account.recovery.hold', entity: 'user', entityId: r.oldUserId, after: { holdUntil: r.holdUntil } });
  }
  return recoveryView(r);
}

export async function adminRejectRecovery(id: string, note?: string) {
  const r = await RecoveryRequest.findOne({ _id: id, status: { $in: ['submitted', 'hold'] } });
  if (!r) throw notFound('Recovery request');
  r.status = 'rejected';
  r.note = note ?? null;
  r.decidedAt = new Date();
  await r.save();
  return recoveryView(r);
}

/** Holds this person may stop: their own old account, or a business where they manage/own/account. */
export async function stoppableHolds(userId: string) {
  const ms = await Membership.find({ userId, status: 'active', role: { $in: ['manager', 'ca', 'owner'] } }).select('companyId').lean();
  const list = await RecoveryRequest.find({
    status: 'hold',
    $or: [{ oldUserId: userId }, { companyIds: { $in: ms.map((m) => m.companyId) } }],
  }).lean();
  return list.map(recoveryView);
}

export async function stopRecovery(userId: string, id: string) {
  const allowed = (await stoppableHolds(userId)).some((h) => h.id === id);
  if (!allowed) throw notFound('Recovery');
  await RecoveryRequest.updateOne({ _id: id, status: 'hold' }, { status: 'stopped', stoppedBy: userId, decidedAt: new Date() });
  logger.info({ requestId: id, userId }, 'Recovery stopped');
}

/** Scheduler: finish holds that ran out without anyone stopping them. */
export async function completeRecoveries(now = new Date()) {
  const due = await RecoveryRequest.find({ status: 'hold', holdUntil: { $lte: now } });
  let done = 0;
  for (const r of due) {
    try {
      const [old, requester] = await Promise.all([loadUser(r.oldUserId), loadUser(r.requesterUserId)]);
      await moveIdentity(old, requester, 'support');
      r.status = 'completed';
      done++;
    } catch (err: any) {
      r.status = 'rejected';
      r.note = err?.message ?? 'Could not complete';
    }
    r.decidedAt = new Date();
    await r.save();
  }
  return done;
}

// ------------------------------------------------- delete my account (row 17)

/** Everything StaffMint holds about this person, for "export before delete" (DPDP). */
export async function exportMyData(userId: string) {
  const user = await loadUser(userId);
  const ms = await Membership.find({ userId: user._id }).lean();
  const views = await membershipViews(ms);
  const empIds = ms.map((m) => m.employeeId).filter((x): x is Types.ObjectId => !!x);
  const slips = await Payslip.find({ employeeId: { $in: empIds }, status: { $in: ['final', 'sent'] }, deletedAt: null })
    .setOptions({ skipTenant: true })
    .sort({ month: -1 })
    .lean();
  return {
    exportedAt: new Date(),
    profile: { name: user.name, phone: user.phone, email: user.email ?? null, language: user.language, memberSince: (user as any).createdAt },
    accounts: views.map((v, i) => ({ ...v, status: ms[i].status, endedAt: ms[i].endedAt ?? null, endedReason: ms[i].endedReason ?? null })),
    payslips: await Promise.all(slips.map(async (s) => ({ companyId: String(s.companyId), ...(await payslipView(s)) }))),
  };
}

/**
 * Delete the person (after an OTP to their own number). Main owners must first
 * transfer or close each business. Staff records and payslips stay with the
 * employers as payroll law requires; the login itself is gone.
 */
export async function deleteMyAccount(userId: string, code: string) {
  const user = await loadUser(userId);
  await consumeOtp(user.phone, code);
  const owns = await Company.find({ ownerUserId: user._id, closedAt: null, deletedAt: null }).select('name').lean();
  if (owns.length) {
    throw new AppError('CONFLICT', 'Transfer or close your businesses first', { reason: 'owns_business', businesses: owns.map((c) => c.name) });
  }
  const active = await Membership.find({ userId: user._id, status: 'active' }).lean();
  await endMemberships({ userId: user._id }, 'left');
  for (const m of active) {
    await notifyOwners(m.companyId, {
      template: 'member_left',
      title: `${user.name || user.phone} deleted their StaffMint account`,
      titleHi: `${user.name || user.phone} ने अपना StaffMint खाता हटा दिया`,
      body: m.role === 'ca' ? 'Their accountant access has ended.' : 'Mark their exit from the staff profile when you are ready.',
      bodyHi: m.role === 'ca' ? 'उनकी अकाउंटेंट पहुँच ख़त्म हो गई है।' : 'स्टाफ़ प्रोफ़ाइल से उनकी छुट्टी दर्ज करें।',
      data: { kind: 'member_left' },
    });
  }
  if (user.photoKey) await (await provider('storage')).delete(user.photoKey).catch(() => undefined);
  const phone = user.phone;
  user.set({ name: '', email: null, photoKey: null, pushTokens: [], loginDevices: [], deviceIds: [], phone: `deleted:${user._id}`, deletedAt: new Date() });
  await user.save();
  // The same number can sign up again later as a new person; its staff records should not re-attach silently.
  await Employee.updateMany({ userId: user._id }, { userId: null }).setOptions({ skipTenant: true });
  await revokeAllForUser(user._id);
  logger.info({ userId: user._id, phoneLast4: last4(phone) }, 'Account deleted');
}

// ------------------------------------------------- ex-staff payslips (row 21)

/**
 * Removed or departed staff keep read-only access to their own payslips for
 * 12 months, unless the business switched it off.
 */
export async function pastPayslips(userId: string) {
  const since = new Date(Date.now() - 365 * 86400_000);
  const ended = await Membership.find({
    userId,
    status: 'inactive',
    employeeId: { $ne: null },
    endedReason: { $in: ['removed', 'left', 'phone_changed'] },
    endedAt: { $gte: since },
  }).lean();
  if (!ended.length) return [];
  const companies = await Company.find({ _id: { $in: ended.map((m) => m.companyId) }, closedAt: null }).lean();
  const out = [];
  for (const c of companies) {
    if (c.settings?.exStaffPayslips === false) continue;
    const m = ended.find((x) => String(x.companyId) === String(c._id))!;
    const slips = await Payslip.find({ companyId: c._id, employeeId: m.employeeId, status: { $in: ['final', 'sent'] }, deletedAt: null }).sort({ month: -1, revision: -1 }).limit(24).lean();
    const latest = new Map<string, any>();
    for (const s of slips) if (!latest.has(s.month)) latest.set(s.month, s);
    if (!latest.size) continue;
    out.push({
      companyId: String(c._id),
      companyName: c.name,
      endedAt: m.endedAt,
      payslips: await Promise.all([...latest.values()].map(async (s) => payslipView(s))),
    });
  }
  return out;
}
