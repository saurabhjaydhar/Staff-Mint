import { Types } from 'mongoose';
import { AppError, notFound } from '../../lib/errors.js';
import type { Ctx } from '../../lib/context.js';
import { env } from '../../config/env.js';
import { decryptField, encryptField } from '../../lib/crypto.js';
import { normalizePhone } from '../../lib/phone.js';
import { Branch, Company, Employee, Shift, User } from '../../models/index.js';
import { provider } from '../../providers/registry.js';
import { audit } from '../audit/service.js';
import { consumeOtp, requestOtp, revokeAllForUser } from '../auth/service.js';
import { companyPlan } from '../billing/plans.js';
import { assertEmployeeInScope } from '../employees/service.js';
import { notifyOwners } from '../notifications/service.js';

export interface BankInput {
  holderName: string;
  accountNumber?: string | null;
  ifsc?: string | null;
  upiId?: string | null;
}

interface BankStored {
  holderName: string;
  accountNumber: string | null;
  ifsc: string | null;
  upiId: string | null;
}

export const IFSC_RE = /^[A-Z]{4}0[A-Z0-9]{6}$/;
export const UPI_RE = /^[a-zA-Z0-9.\-_]{2,256}@[a-zA-Z]{2,64}$/;

/** Masked bank details: never the full account number. */
export function bankView(enc: string | null | undefined, updatedAt?: Date | null) {
  if (!enc) return null;
  try {
    const b = JSON.parse(decryptField(enc)) as BankStored;
    return {
      holderName: b.holderName,
      accountLast4: b.accountNumber ? b.accountNumber.slice(-4) : null,
      ifsc: b.ifsc,
      upiId: b.upiId,
      updatedAt: updatedAt ?? null,
    };
  } catch {
    return null;
  }
}

export function validateBank(input: BankInput): BankStored {
  const holderName = input.holderName.trim();
  const accountNumber = input.accountNumber?.replace(/\s/g, '') || null;
  const ifsc = input.ifsc?.trim().toUpperCase() || null;
  const upiId = input.upiId?.trim() || null;
  if (!accountNumber && !upiId) throw new AppError('VALIDATION_ERROR', 'Add a bank account or a UPI ID', { field: 'accountNumber' });
  if (accountNumber && !/^\d{9,18}$/.test(accountNumber)) throw new AppError('VALIDATION_ERROR', 'Account number must be 9–18 digits', { field: 'accountNumber' });
  if (accountNumber && !ifsc) throw new AppError('VALIDATION_ERROR', 'IFSC is needed with the account number', { field: 'ifsc' });
  if (ifsc && !IFSC_RE.test(ifsc)) throw new AppError('VALIDATION_ERROR', 'IFSC looks wrong (like SBIN0001234)', { field: 'ifsc' });
  if (upiId && !UPI_RE.test(upiId)) throw new AppError('VALIDATION_ERROR', 'UPI ID looks wrong (like name@okaxis)', { field: 'upiId' });
  return { holderName, accountNumber, ifsc: accountNumber ? ifsc : null, upiId };
}

export const emergencyView = (e: any) => (e?.emergencyContact?.name ? { name: e.emergencyContact.name, phone: e.emergencyContact.phone ?? null, relation: e.emergencyContact.relation ?? null } : null);

async function loadUser(ctx: Ctx) {
  const user = await User.findOne({ _id: ctx.userId, deletedAt: null });
  if (!user) throw new AppError('UNAUTHORIZED', 'User not found');
  return user;
}

async function loadOwnEmployee(ctx: Ctx) {
  if (!ctx.employeeId) return null;
  return Employee.findOne({ _id: ctx.employeeId, companyId: ctx.companyId });
}

/** What still makes the profile feel incomplete, in the order we nudge for it. */
function completeness(user: any, employee: any) {
  const items: [string, boolean][] = [
    ['photo', !!user.photoKey],
    ['name', !!user.name?.trim()],
  ];
  // Shop staff often have no email; only owners / managers are nudged for one.
  if (!employee) items.push(['email', !!user.email]);
  if (employee) {
    items.push(['bank', !!employee.bankDetailsEnc]);
    items.push(['emergencyContact', !!employee.emergencyContact?.name]);
  }
  const done = items.filter(([, ok]) => ok).length;
  return { percent: Math.round((done / items.length) * 100), missing: items.filter(([, ok]) => !ok).map(([k]) => k) };
}

export async function profileView(ctx: Ctx) {
  const user = await loadUser(ctx);
  const storage = await provider('storage');
  const company = ctx.companyId ? await Company.findById(ctx.companyId).lean() : null;
  const employee = await loadOwnEmployee(ctx);
  let work = null;
  if (employee) {
    const branch = employee.branchId ? await Branch.findOne({ _id: employee.branchId, companyId: ctx.companyId }).lean() : await Branch.findOne({ companyId: ctx.companyId, isDefault: true }).lean();
    const shiftId = employee.shiftId ?? branch?.shiftId;
    const shift = (shiftId ? await Shift.findOne({ _id: shiftId, companyId: ctx.companyId }).lean() : null) ?? (await Shift.findOne({ companyId: ctx.companyId, isDefault: true }).lean());
    work = {
      employeeId: String(employee._id),
      designation: employee.designation ?? null,
      joiningDate: employee.joiningDate ?? null,
      wageType: employee.wageType,
      ratePaise: employee.ratePaise,
      branchName: branch?.name ?? null,
      shift: shift ? { name: shift.name, start: shift.start, end: shift.end } : null,
    };
  }
  const plan = company ? (await companyPlan(company)).plan : null;
  return {
    user: {
      id: String(user._id),
      name: user.name ?? '',
      phone: user.phone,
      email: user.email ?? null,
      role: ctx.role,
      language: user.language ?? 'hi',
      photoUrl: user.photoKey ? await storage.signedUrl(user.photoKey, env.SIGNED_URL_TTL_SEC) : null,
      memberSince: (user as any).createdAt ?? null,
      lastLoginAt: user.lastLoginAt ?? null,
    },
    company: company ? { id: String(company._id), name: company.name, businessType: company.businessType, planName: plan?.name ?? null } : null,
    work,
    bank: employee ? bankView(employee.bankDetailsEnc, employee.bankUpdatedAt) : null,
    emergencyContact: employee ? emergencyView(employee) : null,
    completeness: completeness(user, employee),
  };
}

export async function updateProfile(
  ctx: Ctx,
  patch: { name?: string; email?: string | null; language?: 'en' | 'hi'; emergencyContact?: { name: string; phone?: string | null; relation?: string | null } | null },
) {
  const user = await loadUser(ctx);
  const employee = await loadOwnEmployee(ctx);
  const before = { name: user.name, email: user.email, language: user.language, emergencyContact: employee ? emergencyView(employee) : undefined };
  if (patch.name !== undefined) user.name = patch.name.trim();
  if (patch.email !== undefined) user.email = patch.email ? patch.email.trim().toLowerCase() : null;
  if (patch.language) user.language = patch.language;
  await user.save();
  if (employee) {
    if (patch.name !== undefined) employee.name = patch.name.trim();
    if (patch.language) employee.language = patch.language;
    if (patch.emergencyContact !== undefined) {
      const ec = patch.emergencyContact;
      let phone: string | null = null;
      if (ec?.phone) {
        phone = normalizePhone(ec.phone);
        if (!phone) throw new AppError('VALIDATION_ERROR', 'Emergency contact phone looks wrong', { field: 'emergencyContact.phone' });
      }
      employee.emergencyContact = (ec ? { name: ec.name.trim(), phone, relation: ec.relation?.trim() || null } : { name: null, phone: null, relation: null }) as any;
    }
    await employee.save();
  } else if (patch.emergencyContact !== undefined) {
    throw new AppError('VALIDATION_ERROR', 'Emergency contact is for staff profiles', { field: 'emergencyContact' });
  }
  await audit(ctx, { action: 'profile.update', entity: 'user', entityId: user._id, before, after: { name: user.name, email: user.email, language: user.language, emergencyContact: employee ? emergencyView(employee) : undefined } });
  return profileView(ctx);
}

export async function setPhoto(ctx: Ctx, photoBase64: string) {
  const user = await loadUser(ctx);
  const buf = Buffer.from(photoBase64.replace(/^data:image\/\w+;base64,/, ''), 'base64');
  if (buf.length < 100) throw new AppError('VALIDATION_ERROR', 'Photo is empty');
  if (buf.length > 2_000_000) throw new AppError('VALIDATION_ERROR', 'Photo too large (max 2 MB)');
  const storage = await provider('storage');
  const old = user.photoKey;
  const key = `avatars/${user._id}-${Date.now()}.jpg`;
  await storage.put(key, buf, 'image/jpeg');
  user.photoKey = key;
  await user.save();
  if (old) await storage.delete(old).catch(() => undefined);
  await audit(ctx, { action: 'profile.photo', entity: 'user', entityId: user._id });
  return profileView(ctx);
}

export async function removePhoto(ctx: Ctx) {
  const user = await loadUser(ctx);
  const old = user.photoKey;
  user.photoKey = null;
  await user.save();
  if (old) await (await provider('storage')).delete(old).catch(() => undefined);
  await audit(ctx, { action: 'profile.photo.remove', entity: 'user', entityId: user._id });
  return profileView(ctx);
}

/** Bank details for salary. Staff edit their own; owners can fill them in for staff. */
export async function setBank(ctx: Ctx, employeeId: Types.ObjectId | string, input: BankInput | null) {
  const self = ctx.employeeId && String(ctx.employeeId) === String(employeeId);
  const emp = self ? await Employee.findOne({ _id: employeeId, companyId: ctx.companyId }) : await assertEmployeeInScope(ctx, String(employeeId));
  if (!emp) throw notFound('Employee');
  const before = bankView(emp.bankDetailsEnc);
  emp.bankDetailsEnc = input ? encryptField(JSON.stringify(validateBank(input))) : null;
  emp.bankUpdatedAt = input ? new Date() : null;
  await emp.save();
  const after = bankView(emp.bankDetailsEnc, emp.bankUpdatedAt);
  await audit(ctx, { action: input ? 'employee.bank.update' : 'employee.bank.remove', entity: 'employee', entityId: emp._id, before, after });
  if (self) {
    // Money goes here: the owner always hears about a change, so a stolen phone can't quietly redirect salary.
    await notifyOwners(ctx.companyId, {
      template: 'bank_changed',
      title: 'Salary account changed',
      titleHi: 'सैलरी खाता बदला',
      body: `${emp.name} ${input ? 'updated' : 'removed'} their salary account. Check it before the next payout.`,
      bodyHi: `${emp.name} ने अपना सैलरी खाता ${input ? 'बदला' : 'हटाया'}। अगली सैलरी से पहले जाँच लें।`,
      data: { type: 'bank_changed', employeeId: String(emp._id) },
    });
  }
  return after;
}

/** Step 1 of a phone change: OTP to the new number. */
export async function requestPhoneChange(ctx: Ctx, rawPhone: string, ip?: string) {
  const user = await loadUser(ctx);
  const phone = normalizePhone(rawPhone);
  if (!phone) throw new AppError('VALIDATION_ERROR', 'Enter a valid mobile number', { field: 'phone' });
  if (phone === user.phone) throw new AppError('VALIDATION_ERROR', 'This is already your number', { field: 'phone' });
  await assertPhoneFree(ctx, phone);
  return requestOtp(phone, 'sms', ip);
}

async function assertPhoneFree(ctx: Ctx, phone: string) {
  if (await User.exists({ phone, deletedAt: null, _id: { $ne: ctx.userId } })) throw new AppError('CONFLICT', 'This number is already used by another account', { field: 'phone' });
  if (ctx.companyId && (await Employee.exists({ companyId: ctx.companyId, phone, deletedAt: null, _id: { $ne: ctx.employeeId ?? null } }))) {
    throw new AppError('CONFLICT', 'This number belongs to another staff member', { field: 'phone' });
  }
  // Staff records elsewhere move with this person; someone else's record with that number blocks the change.
  if (await Employee.exists({ phone, deletedAt: null, userId: { $ne: ctx.userId } }).setOptions({ skipTenant: true })) {
    throw new AppError('CONFLICT', 'This number is already added as staff in a business', { field: 'phone' });
  }
}

/** Step 2: the code proves the new number is theirs; login moves to it. */
export async function verifyPhoneChange(ctx: Ctx, rawPhone: string, code: string) {
  const user = await loadUser(ctx);
  const phone = normalizePhone(rawPhone);
  if (!phone) throw new AppError('VALIDATION_ERROR', 'Enter a valid mobile number', { field: 'phone' });
  await consumeOtp(phone, code);
  await assertPhoneFree(ctx, phone);
  const before = user.phone;
  user.phone = phone;
  await user.save();
  // Every business this person is staff at now knows the new number.
  await Employee.updateMany({ userId: user._id, deletedAt: null }, { phone }).setOptions({ skipTenant: true });
  await audit(ctx, { action: 'profile.phone', entity: 'user', entityId: user._id, before: { phone: before }, after: { phone } });
  return profileView(ctx);
}

export async function logoutEverywhere(ctx: Ctx) {
  const user = await loadUser(ctx);
  await revokeAllForUser(user._id);
  await audit(ctx, { action: 'profile.logout_all', entity: 'user', entityId: user._id });
}
