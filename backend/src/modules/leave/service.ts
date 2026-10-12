import { Types } from 'mongoose';
import { AppError, notFound } from '../../lib/errors.js';
import { dateRange, todayIn } from '../../lib/dates.js';
import type { Ctx } from '../../lib/context.js';
import { Attendance, Company, Employee, Leave, LeaveBalance } from '../../models/index.js';
import { audit } from '../audit/service.js';
import { assertEmployeeInScope, employeeScope } from '../employees/service.js';
import { dayContext } from '../attendance/service.js';
import { notifyEmployee, notifyOwners } from '../notifications/service.js';
import { leaveView } from '../views.js';

export async function getLeaveBalance(ctx: Ctx, employeeId: Types.ObjectId, year: number) {
  const b = await LeaveBalance.findOne({ companyId: ctx.companyId, employeeId, year }).lean();
  return { employeeId: String(employeeId), year, paid: b?.paid ?? 0, sick: b?.sick ?? 0, usedPaid: b?.usedPaid ?? 0, usedSick: b?.usedSick ?? 0 };
}

export async function setLeaveBalance(ctx: Ctx, employeeId: string, year: number, paid: number, sick: number) {
  const emp = await assertEmployeeInScope(ctx, employeeId);
  const before = await LeaveBalance.findOne({ companyId: ctx.companyId, employeeId: emp._id, year }).lean();
  const b = await LeaveBalance.findOneAndUpdate({ companyId: ctx.companyId, employeeId: emp._id, year }, { $set: { paid, sick } }, { upsert: true, new: true });
  await audit(ctx, { action: 'leave_balance.set', entity: 'leave_balance', entityId: b!._id, before, after: b });
  return getLeaveBalance(ctx, emp._id, year);
}

export async function listBalances(ctx: Ctx, year: number, employeeId?: string) {
  const f: any = employeeScope(ctx);
  if (employeeId) f._id = employeeId;
  const emps = await Employee.find({ ...f, status: 'active' }).select('_id').lean();
  return Promise.all(emps.map((e) => getLeaveBalance(ctx, e._id, year)));
}

/** Working days a leave consumes (week offs and holidays excluded). */
async function countLeaveDays(companyId: Types.ObjectId, emp: any, from: string, to: string, halfDay: boolean) {
  if (halfDay) return 0.5;
  const dc = await dayContext(companyId, from, to, [emp._id]);
  return dateRange(from, to).filter((d) => !dc.holidayName(d) && !dc.isWeekOff(emp, d)).length;
}

export async function listLeaves(ctx: Ctx, q: { status?: string; employeeId?: string }) {
  const scopeIds = (await Employee.find(employeeScope(ctx)).select('_id').lean()).map((e) => e._id);
  const f: any = { companyId: ctx.companyId, deletedAt: null, employeeId: { $in: scopeIds } };
  if (q.status) f.status = q.status;
  if (q.employeeId) f.employeeId = q.employeeId;
  return (await Leave.find(f).sort({ createdAt: -1 }).limit(200).populate('employeeId', 'name').lean()).map((l) => leaveView(l));
}

export async function applyLeave(ctx: Ctx, input: { type: 'paid' | 'sick' | 'unpaid'; from: string; to: string; halfDay?: boolean; reason?: string; employeeId?: string }) {
  const empId = ctx.role === 'employee' ? ctx.employeeId : input.employeeId;
  if (!empId) throw new AppError('VALIDATION_ERROR', 'employeeId is required');
  const emp = await assertEmployeeInScope(ctx, empId);
  if (input.to < input.from) throw new AppError('VALIDATION_ERROR', '"to" must be on or after "from"');
  if (input.halfDay && input.from !== input.to) throw new AppError('VALIDATION_ERROR', 'Half-day leave must be a single day');
  const overlap = await Leave.exists({ companyId: ctx.companyId, employeeId: emp._id, status: { $in: ['pending', 'approved'] }, deletedAt: null, from: { $lte: input.to }, to: { $gte: input.from } });
  if (overlap) throw new AppError('CONFLICT', 'Leave already applied for these dates');
  const days = await countLeaveDays(ctx.companyId, emp, input.from, input.to, !!input.halfDay);
  const leave = await Leave.create({
    companyId: ctx.companyId,
    employeeId: emp._id,
    type: input.type,
    from: input.from,
    to: input.to,
    halfDay: !!input.halfDay,
    days,
    reason: input.reason,
    requestedBy: ctx.userId,
  });
  await audit(ctx, { action: 'leave.apply', entity: 'leave', entityId: leave._id, after: leave });

  if (ctx.role === 'employee') {
    const range = input.from === input.to ? input.from : `${input.from} → ${input.to}`;
    await notifyOwners(ctx.companyId, {
      template: 'leave_request',
      title: `Leave request: ${emp.name}`,
      titleHi: `छुट्टी की अर्ज़ी: ${emp.name}`,
      body: `${input.type} leave, ${range} (${days} day${days === 1 ? '' : 's'})${input.reason ? ` — ${input.reason}` : ''}`,
      bodyHi: `${input.type} छुट्टी, ${range} (${days} दिन)${input.reason ? ` — ${input.reason}` : ''}`,
      data: { type: 'leave_request', leaveId: String(leave._id) },
      whatsapp: { template: 'leave_request', params: [emp.name, range, String(days), input.reason ?? '-'], buttons: [{ id: `leave:approve:${leave._id}`, title: 'Approve' }, { id: `leave:reject:${leave._id}`, title: 'Reject' }] },
    });
    return leave;
  }
  // Owner/manager applying on behalf: approve immediately.
  return decideLeave(ctx, String(leave._id), 'approved');
}

async function writeLeaveToAttendance(ctx: Ctx, leave: any, emp: any) {
  const dc = await dayContext(ctx.companyId, leave.from, leave.to, [emp._id]);
  for (const d of dateRange(leave.from, leave.to)) {
    if (dc.holidayName(d) || dc.isWeekOff(emp, d)) continue;
    const r = await Attendance.findOne({ companyId: ctx.companyId, employeeId: emp._id, date: d });
    if (r && (r.overridden || r.punches.some((p: any) => p.approval !== 'rejected'))) continue; // actual punches / owner override win
    await Attendance.updateOne(
      { companyId: ctx.companyId, employeeId: emp._id, date: d },
      { $set: { status: leave.halfDay ? 'half_day' : 'leave', leaveType: leave.halfDay ? null : leave.type, autoMarked: true }, $setOnInsert: { companyId: ctx.companyId, employeeId: emp._id, date: d, punches: [] } },
      { upsert: true },
    );
  }
}

async function removeLeaveFromAttendance(ctx: Ctx, leave: any) {
  await Attendance.updateMany(
    { companyId: ctx.companyId, employeeId: leave.employeeId, date: { $gte: leave.from, $lte: leave.to }, overridden: false, autoMarked: true, status: { $in: ['leave', 'half_day'] }, 'punches.0': { $exists: false } },
    { $set: { status: null, leaveType: null } },
  );
}

async function adjustUsed(ctx: Ctx, leave: any, sign: 1 | -1) {
  if (leave.type === 'unpaid') return;
  const year = Number(leave.from.slice(0, 4));
  const field = leave.type === 'paid' ? 'usedPaid' : 'usedSick';
  await LeaveBalance.updateOne({ companyId: ctx.companyId, employeeId: leave.employeeId, year }, { $inc: { [field]: sign * leave.days } }, { upsert: true });
}

/**
 * Approve or reject. [opts.asUnpaid]: approve as unpaid leave (used when the
 * person has no paid/sick leave left, so salary is cut for those days).
 */
export async function decideLeave(ctx: Ctx, id: string, decision: 'approved' | 'rejected', note?: string, opts: { asUnpaid?: boolean } = {}) {
  const leave = await Leave.findOne({ _id: id, companyId: ctx.companyId, deletedAt: null });
  if (!leave) throw notFound('Leave');
  const emp = await assertEmployeeInScope(ctx, leave.employeeId);
  if (leave.status !== 'pending') throw new AppError('CONFLICT', `Leave is already ${leave.status}`);
  const before = leave.toObject();
  leave.status = decision;
  if (decision === 'approved' && opts.asUnpaid) leave.type = 'unpaid';
  leave.decidedBy = ctx.userId ?? undefined;
  leave.decidedAt = new Date();
  leave.note = note;
  await leave.save();
  if (decision === 'approved') {
    await writeLeaveToAttendance(ctx, leave, emp);
    await adjustUsed(ctx, leave, 1);
  }
  await audit(ctx, { action: `leave.${decision}`, entity: 'leave', entityId: leave._id, before, after: leave });
  const range = leave.from === leave.to ? leave.from : `${leave.from} → ${leave.to}`;
  await notifyEmployee(
    ctx.companyId,
    emp._id,
    {
      template: 'leave_status',
      title: decision === 'approved' ? (leave.type === 'unpaid' && opts.asUnpaid ? 'Leave approved (unpaid)' : 'Leave approved') : 'Leave rejected',
      titleHi: decision === 'approved' ? (leave.type === 'unpaid' && opts.asUnpaid ? 'छुट्टी मंज़ूर (बिना पैसे)' : 'छुट्टी मंज़ूर') : 'छुट्टी नामंज़ूर',
      body: `${range}${note ? ` — ${note}` : ''}`,
      bodyHi: `${range}${note ? ` — ${note}` : ''}`,
      data: { type: 'leave_status', leaveId: String(leave._id), status: decision },
      whatsapp: { template: 'leave_status', params: [emp.name, range, decision === 'approved' ? 'approved / मंज़ूर' : 'rejected / नामंज़ूर'] },
    },
    { whatsapp: ctx.role !== 'employee' },
  );
  return leave;
}

export async function cancelLeave(ctx: Ctx, id: string) {
  const leave = await Leave.findOne({ _id: id, companyId: ctx.companyId, deletedAt: null });
  if (!leave) throw notFound('Leave');
  await assertEmployeeInScope(ctx, leave.employeeId);
  if (ctx.role === 'employee' && leave.status !== 'pending') throw new AppError('FORBIDDEN', 'Ask your employer to cancel an approved leave');
  if (!['pending', 'approved'].includes(leave.status)) throw new AppError('CONFLICT', `Leave is already ${leave.status}`);
  const company = await Company.findById(ctx.companyId).lean();
  if (leave.status === 'approved' && leave.to < todayIn(company!.timezone) && ctx.role !== 'owner') throw new AppError('FORBIDDEN', 'Past leave can only be cancelled by the owner');
  const before = leave.toObject();
  const wasApproved = leave.status === 'approved';
  leave.status = 'cancelled';
  await leave.save();
  if (wasApproved) {
    await removeLeaveFromAttendance(ctx, leave);
    await adjustUsed(ctx, leave, -1);
  }
  await audit(ctx, { action: 'leave.cancel', entity: 'leave', entityId: leave._id, before, after: leave });
  return leave;
}
