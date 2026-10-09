import { Types } from 'mongoose';
import { AppError, notFound } from '../../lib/errors.js';
import { normalizePhone } from '../../lib/phone.js';
import { todayIn } from '../../lib/dates.js';
import type { Ctx } from '../../lib/context.js';
import { Branch, Company, Employee, SalaryStructure, Shift, User } from '../../models/index.js';
import { companyPlan, activeStaffCount } from '../billing/plans.js';
import { audit } from '../audit/service.js';
import { employeeView } from '../views.js';
import { revokeAllForUser } from '../auth/service.js';
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
  const userIds = emps.map((e) => e.userId).filter(Boolean);
  const users = userIds.length ? await User.find({ _id: { $in: userIds } }).select('deviceIds').lean() : [];
  const hasDevice = new Map(users.map((u) => [String(u._id), (u.deviceIds?.length ?? 0) > 0]));
  return emps.map((e) => employeeView(e, { hasDevice: e.userId ? !!hasDevice.get(String(e.userId)) : false }));
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
  const count = await activeStaffCount(companyId);
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

export async function createEmployee(ctx: Ctx, input: EmployeeInput, opts: { skipCapacityCheck?: boolean; importSessionId?: Types.ObjectId } = {}) {
  const company = await Company.findById(ctx.companyId).lean();
  const phone = normalizePhone(input.phone, company?.country ?? 'IN');
  if (!phone) throw new AppError('VALIDATION_ERROR', `Invalid phone number for ${input.name}`);
  if (await Employee.exists({ companyId: ctx.companyId, phone, deletedAt: null })) throw new AppError('CONFLICT', `${phone} is already added`, { phone });
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
  return e;
}

export async function bulkCreate(ctx: Ctx, list: EmployeeInput[]) {
  const created: any[] = [];
  const skipped: { phone: string; reason: string }[] = [];
  for (const item of list) {
    try {
      created.push(employeeView(await createEmployee(ctx, item)));
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
  return { ...view, leaveBalance: await getLeaveBalance(ctx, e._id, year), advanceBalancePaise: await advanceBalanceFor(ctx.companyId, e._id) };
}

export async function updateEmployee(ctx: Ctx, id: string, patch: Partial<EmployeeInput> & { effectiveFrom?: string; language?: 'en' | 'hi' }) {
  const e = await assertEmployeeInScope(ctx, id);
  const before = e.toObject();
  const company = await Company.findById(ctx.companyId).lean();
  if (patch.phone) {
    const phone = normalizePhone(patch.phone, company?.country ?? 'IN');
    if (!phone) throw new AppError('VALIDATION_ERROR', 'Invalid phone number');
    if (phone !== e.phone && (await Employee.exists({ companyId: ctx.companyId, phone, deletedAt: null }))) throw new AppError('CONFLICT', `${phone} is already added`);
    if (phone !== e.phone && e.userId) {
      // Phone change detaches the old login.
      await revokeAllForUser(e.userId);
      await User.updateOne({ _id: e.userId }, { deletedAt: new Date() });
      e.userId = null;
    }
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
  if (e.userId) await revokeAllForUser(e.userId);
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
  await audit(ctx, { action: 'employee.reactivate', entity: 'employee', entityId: e._id, before, after: e });
  return e;
}

export async function resetDevice(ctx: Ctx, id: string) {
  const e = await assertEmployeeInScope(ctx, id);
  if (e.userId) {
    await User.updateOne({ _id: e.userId }, { deviceIds: [] });
    await revokeAllForUser(e.userId);
  }
  await audit(ctx, { action: 'employee.reset_device', entity: 'employee', entityId: e._id });
  return e;
}

export async function setAppRole(ctx: Ctx, id: string, appRole: 'employee' | 'manager') {
  const e = await assertEmployeeInScope(ctx, id);
  const before = { appRole: e.appRole };
  e.appRole = appRole;
  await e.save();
  if (e.userId) {
    await User.updateOne({ _id: e.userId }, { role: appRole, branchIds: appRole === 'manager' && e.branchId ? [e.branchId] : [] });
    await revokeAllForUser(e.userId);
  }
  await audit(ctx, { action: 'employee.role', entity: 'employee', entityId: e._id, before, after: { appRole } });
  return e;
}

/** Salary structure effective on a date (versioned). Falls back to the employee's current rate. */
export async function rateOn(companyId: Types.ObjectId, employee: { _id: Types.ObjectId; wageType: string; ratePaise: number }, date: string) {
  const s = await SalaryStructure.findOne({ companyId, employeeId: employee._id, effectiveFrom: { $lte: date } }).sort({ effectiveFrom: -1, createdAt: -1 }).lean();
  return s ? { wageType: s.wageType as 'monthly' | 'daily', ratePaise: s.basePaise } : { wageType: employee.wageType as 'monthly' | 'daily', ratePaise: employee.ratePaise };
}
