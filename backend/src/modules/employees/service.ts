import { Types } from 'mongoose';
import { AppError, notFound } from '../../lib/errors.js';
import { normalizePhone } from '../../lib/phone.js';
import { todayIn } from '../../lib/dates.js';
import type { Ctx } from '../../lib/context.js';
import { Branch, Company, Employee, Membership, SalaryStructure, Shift, User } from '../../models/index.js';
import { companyPlan, billingStaffCount } from '../billing/plans.js';
import { audit } from '../audit/service.js';
import { employeeView } from '../views.js';
import { activate, attachStaffMemberships, deactivateStaffMemberships, revokeMembershipSessions } from '../auth/memberships.js';
import { advanceBalanceFor } from '../advances/service.js';
import { getLeaveBalance } from '../leave/service.js';

export interface EmployeeInput {
  name: string;
  phone: string;
  wageType?: 'monthly' | 'daily';
  ratePaise?: number;
  branchId?: string;
  shiftId?: string;
  designation?: string;
  joiningDate?: string;
}

/** Base filter honouring RBAC scope: managers see their branches, employees only themselves. */
export function employeeScope(ctx: Ctx): Record<string, unknown> {
  const f: Record<string, unknown> = { companyId: ctx.companyId, deletedAt: null };
  if (ctx.role === 'manager' && ctx.branchIds.length) f.branchId = { $in: ctx.branchIds };
  if (ctx.role === 'employee') f._id = ctx.employeeId;
  return f;
}

export async function assertEmployeeInScope(ctx: Ctx, employeeId: string | Types.ObjectId) {
  const e = await Employee.findOne({ ...employeeScope(ctx), _id: employeeId });
  if (!e) throw notFound('Employee');
  return e;
}

async function withDeviceFlags(emps: any[]) {
  const linked = emps.filter((e) => e.userId);
  const ms = linked.length
    ? await Membership.find({ companyId: linked[0].companyId, employeeId: { $in: linked.map((e) => e._id) } }).select('employeeId deviceIds').lean()
    : [];
  const hasDevice = new Map(ms.map((m) => [String(m.employeeId), (m.deviceIds?.length ?? 0) > 0]));
  return emps.map((e) => employeeView(e, { hasDevice: e.userId ? !!hasDevice.get(String(e._id)) : false }));
}

export async function listEmployees(ctx: Ctx, q: { search?: string; status?: 'active' | 'inactive' | 'all'; branchId?: string }) {
  const f: any = employeeScope(ctx);
  if (q.status !== 'all') f.status = q.status ?? 'active';
  if (q.branchId) f.branchId = q.branchId;
  if (q.search) {
    const rx = new RegExp(q.search.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i');
    f.$or = [{ name: rx }, { phone: rx }, { designation: rx }];
  }
  const emps = await Employee.find(f).sort({ name: 1 }).lean();
  return withDeviceFlags(emps);
}

export async function ensureStaffCapacity(companyId: Types.ObjectId, adding = 1) {
  const { plan } = await companyPlan({ _id: companyId });
  // One bill for several businesses: the limit covers all of them together.
  const count = await billingStaffCount(companyId);
  const limit = plan.extraStaffPricePaise > 0 ? plan.maxStaffHardCap : plan.staffLimit;
  if (count + adding > limit) {
    throw new AppError('PLAN_LIMIT', `Your ${plan.name} plan allows ${limit} staff. Upgrade to add more.`, { planCode: plan.code, limit, count });
  }
}

async function defaults(companyId: Types.ObjectId) {
  const branch = await Branch.findOne({ companyId, isDefault: true, deletedAt: null }).lean();
  const shiftId = branch?.shiftId ?? (await Shift.findOne({ companyId, isDefault: true }).lean())?._id;
  return { branchId: branch?._id, shiftId };
}

export async function createEmployee(ctx: Ctx, input: EmployeeInput, opts: { skipCapacityCheck?: boolean; importSessionId?: Types.ObjectId; invite?: boolean } = {}) {
  const company = await Company.findById(ctx.companyId).lean();
  const phone = normalizePhone(input.phone, company?.country ?? 'IN');
  if (!phone) throw new AppError('VALIDATION_ERROR', `Invalid phone number for ${input.name}`);
  if (await Employee.exists({ companyId: ctx.companyId, phone, deletedAt: null })) throw new AppError('CONFLICT', `${phone} is already added`, { phone });
  const login = await assertPhoneCanBeStaff(ctx, phone, input.name);
  if (!opts.skipCapacityCheck) await ensureStaffCapacity(ctx.companyId);
  const d = await defaults(ctx.companyId);
  if (input.branchId && !(await Branch.exists({ _id: input.branchId, companyId: ctx.companyId }))) throw notFound('Branch');
  if (input.shiftId && !(await Shift.exists({ _id: input.shiftId, companyId: ctx.companyId }))) throw notFound('Shift');
  const joiningDate = input.joiningDate;
  const e = await Employee.create({
    companyId: ctx.companyId,
    name: input.name.trim(),
    phone,
    wageType: input.wageType ?? 'monthly',
    ratePaise: input.ratePaise ?? 0,
    branchId: input.branchId ?? (ctx.role === 'manager' && ctx.branchIds[0] ? ctx.branchIds[0] : d.branchId),
    shiftId: input.shiftId ?? d.shiftId,
    designation: input.designation,
    joiningDate,
    language: company?.settings?.language ?? 'hi',
    importSessionId: opts.importSessionId ?? null,
  });
  await SalaryStructure.create({
    companyId: ctx.companyId,
    employeeId: e._id,
    effectiveFrom: joiningDate ?? todayIn(company?.timezone ?? 'Asia/Kolkata'),
    wageType: e.wageType,
    basePaise: e.ratePaise,
  });
  await audit(ctx, { action: 'employee.create', entity: 'employee', entityId: e._id, after: e });
  await attachLogin(ctx, e, login);
  // New staff get the app link on WhatsApp right away (not for bulk imports; the owner can invite later).
  if (opts.invite && !login) {
    try {
      await (await import('../accounts/service.js')).inviteStaff(ctx, e._id, { auto: true });
      e.invitedAt = new Date();
    } catch {
      /* invite is best effort; adding the staff member already worked */
    }
  }
  return e;
}

/**
 * A phone can be staff here unless it is this business's owner or accountant.
 * People who own or work at another business simply get one more membership.
 * Returns the existing login, if any, so it can be attached after saving.
 */
async function assertPhoneCanBeStaff(ctx: Ctx, phone: string, name: string) {
  const login = await User.findOne({ phone, deletedAt: null });
  if (!login) return null;
  const here = await Membership.findOne({ userId: login._id, companyId: ctx.companyId, status: 'active' }).lean();
  if (here && (here.role === 'owner' || here.role === 'ca')) {
    throw new AppError(
      'CONFLICT',
      here.role === 'owner' ? `${phone} is the business owner's own number. Use ${name}'s personal number.` : `${phone} is your accountant's number. Use ${name}'s personal number.`,
      { phone, reason: here.role === 'owner' ? 'owner_number' : 'accountant_number' },
    );
  }
  return login;
}

/** Give a waiting login its membership for this staff record right away. */
async function attachLogin(ctx: Ctx, e: any, login: any) {
  if (!login) return;
  // The owner is adding this person on purpose, so even someone who left earlier comes back.
  if (await attachStaffMemberships(login, { force: [e._id] })) {
    if (!login.companyId) await activate(login, await Membership.findOne({ userId: login._id, companyId: ctx.companyId }));
    else await login.save();
    await audit(ctx, { action: 'employee.login.attach', entity: 'employee', entityId: e._id });
    // Someone waiting on "Ask your employer to add you" hears about it straight away.
    const company = await Company.findById(ctx.companyId).select('name').lean();
    const { notifyEmployee } = await import('../notifications/service.js');
    await notifyEmployee(ctx.companyId, e._id, {
      template: 'staff_added',
      title: `You've been added to ${company?.name ?? 'a business'}`,
      titleHi: `आपको ${company?.name ?? 'एक बिज़नेस'} में जोड़ा गया है`,
      body: 'Open StaffMint to check in.',
      bodyHi: 'हाज़िरी लगाने के लिए StaffMint खोलें।',
      data: { kind: 'staff_added' },
    });
  }
}

export async function bulkCreate(ctx: Ctx, list: EmployeeInput[]) {
  const created: any[] = [];
  const skipped: { phone: string; reason: string }[] = [];
  for (const item of list) {
    try {
      created.push(employeeView(await createEmployee(ctx, item, { invite: true })));
    } catch (e: any) {
      skipped.push({ phone: item.phone, reason: e?.message ?? 'failed' });
      if (e?.code === 'PLAN_LIMIT') break;
    }
  }
  return { created, skipped };
}

export async function getEmployee(ctx: Ctx, id: string) {
  const e = await assertEmployeeInScope(ctx, id);
  const company = await Company.findById(ctx.companyId).lean();
  const year = Number(todayIn(company!.timezone).slice(0, 4));
  const [view] = await withDeviceFlags([e.toObject()]);
  const { bankView, emergencyView } = await import('../profile/service.js');
  const { employeeStatutoryView } = await import('../statutory/service.js');
  return {
    ...view,
    statutory: employeeStatutoryView(e),
    leaveBalance: await getLeaveBalance(ctx, e._id, year),
    advanceBalancePaise: await advanceBalanceFor(ctx.companyId, e._id),
    // CA sees neither; owners and managers see the bank account masked.
    ...(ctx.role === 'ca' ? {} : { bank: bankView(e.bankDetailsEnc, e.bankUpdatedAt), emergencyContact: emergencyView(e) }),
  };
}

export async function updateEmployee(ctx: Ctx, id: string, patch: Partial<EmployeeInput> & { effectiveFrom?: string; language?: 'en' | 'hi' }) {
  const e = await assertEmployeeInScope(ctx, id);
  let newLogin: any = null;
  const before = e.toObject();
  const company = await Company.findById(ctx.companyId).lean();
  if (patch.phone) {
    const phone = normalizePhone(patch.phone, company?.country ?? 'IN');
    if (!phone) throw new AppError('VALIDATION_ERROR', 'Invalid phone number');
    if (phone !== e.phone && (await Employee.exists({ companyId: ctx.companyId, phone, deletedAt: null }))) throw new AppError('CONFLICT', `${phone} is already added`);
    const waiting = phone !== e.phone ? await assertPhoneCanBeStaff(ctx, phone, e.name) : null;
    if (waiting) newLogin = waiting;
    if (phone !== e.phone && e.userId) {
      // The old number loses access to this business only; that person's other businesses are untouched.
      await deactivateStaffMemberships(ctx.companyId, [e._id], 'phone_changed');
      e.userId = null;
    }
    if (phone !== e.phone) e.phoneRecycledAt = null;
    e.phone = phone;
  }
  const rateChanged = (patch.ratePaise !== undefined && patch.ratePaise !== e.ratePaise) || (patch.wageType && patch.wageType !== e.wageType);
  if (patch.name) e.name = patch.name.trim();
  if (patch.wageType) e.wageType = patch.wageType;
  if (patch.ratePaise !== undefined) e.ratePaise = patch.ratePaise;
  if (patch.designation !== undefined) e.designation = patch.designation;
  if (patch.joiningDate !== undefined) e.joiningDate = patch.joiningDate;
  if (patch.language) e.language = patch.language;
  if (patch.branchId) {
    if (!(await Branch.exists({ _id: patch.branchId, companyId: ctx.companyId }))) throw notFound('Branch');
    e.branchId = new Types.ObjectId(patch.branchId);
  }
  if (patch.shiftId) {
    if (!(await Shift.exists({ _id: patch.shiftId, companyId: ctx.companyId }))) throw notFound('Shift');
    e.shiftId = new Types.ObjectId(patch.shiftId);
  }
  await e.save();
  if (rateChanged) {
    await SalaryStructure.create({
      companyId: ctx.companyId,
      employeeId: e._id,
      effectiveFrom: patch.effectiveFrom ?? todayIn(company?.timezone ?? 'Asia/Kolkata'),
      wageType: e.wageType,
      basePaise: e.ratePaise,
    });
  }
  await audit(ctx, { action: 'employee.update', entity: 'employee', entityId: e._id, before, after: e });
  await attachLogin(ctx, e, newLogin);
  return e;
}

export async function deactivateEmployee(ctx: Ctx, id: string, reason?: string) {
  const e = await assertEmployeeInScope(ctx, id);
  const before = e.toObject();
  const company = await Company.findById(ctx.companyId).lean();
  e.status = 'inactive';
  e.exitDate = todayIn(company!.timezone);
  await e.save();
  // Face photo is personal data with no use after exit: delete it now.
  if (e.face?.refKey) await (await import('../face/service.js')).clearFace(e);
  await deactivateStaffMemberships(ctx.companyId, [e._id]);
  await audit(ctx, { action: 'employee.deactivate', entity: 'employee', entityId: e._id, before, after: { ...e.toObject(), reason } });
  return e;
}

export async function reactivateEmployee(ctx: Ctx, id: string) {
  const e = await assertEmployeeInScope(ctx, id);
  if (e.status === 'active') return e;
  await ensureStaffCapacity(ctx.companyId);
  const before = e.toObject();
  e.status = 'active';
  e.exitDate = undefined;
  await e.save();
  if (e.userId) {
    const user = await User.findOne({ _id: e.userId, deletedAt: null });
    if (user) await attachStaffMemberships(user, { force: [e._id] });
  }
  await audit(ctx, { action: 'employee.reactivate', entity: 'employee', entityId: e._id, before, after: e });
  return e;
}

export async function resetDevice(ctx: Ctx, id: string) {
  const e = await assertEmployeeInScope(ctx, id);
  // Only this business's binding: the person's other memberships keep their phones.
  const ms = await Membership.find({ companyId: ctx.companyId, employeeId: e._id }).select('_id').lean();
  if (ms.length) {
    await Membership.updateMany({ _id: { $in: ms.map((m) => m._id) } }, { deviceIds: [] });
    await revokeMembershipSessions(ms.map((m) => m._id));
  }
  if (e.userId) await User.updateOne({ _id: e.userId, companyId: ctx.companyId }, { deviceIds: [] });
  await audit(ctx, { action: 'employee.reset_device', entity: 'employee', entityId: e._id });
  return e;
}

export async function setAppRole(ctx: Ctx, id: string, appRole: 'employee' | 'manager') {
  const e = await assertEmployeeInScope(ctx, id);
  const before = { appRole: e.appRole };
  e.appRole = appRole;
  await e.save();
  const branchIds = appRole === 'manager' && e.branchId ? [e.branchId] : [];
  const ms = await Membership.find({ companyId: ctx.companyId, employeeId: e._id, role: { $in: ['employee', 'manager'] } }).select('_id').lean();
  // Applies at once: open sessions are told their access changed and refresh into the new role.
  if (ms.length) await Membership.updateMany({ _id: { $in: ms.map((m) => m._id) } }, { role: appRole, branchIds });
  if (e.userId) await User.updateOne({ _id: e.userId, companyId: ctx.companyId, employeeId: e._id }, { role: appRole, branchIds });
  await audit(ctx, { action: 'employee.role', entity: 'employee', entityId: e._id, before, after: { appRole } });
  return e;
}

/** Salary structure effective on a date (versioned). Falls back to the employee's current rate. */
export async function rateOn(companyId: Types.ObjectId, employee: { _id: Types.ObjectId; wageType: string; ratePaise: number }, date: string) {
  const s = await SalaryStructure.findOne({ companyId, employeeId: employee._id, effectiveFrom: { $lte: date } }).sort({ effectiveFrom: -1, createdAt: -1 }).lean();
  return s ? { wageType: s.wageType as 'monthly' | 'daily', ratePaise: s.basePaise } : { wageType: employee.wageType as 'monthly' | 'daily', ratePaise: employee.ratePaise };
}
