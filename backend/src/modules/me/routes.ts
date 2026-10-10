import { Router } from 'express';
import { z } from 'zod';
import { body, query } from '../../lib/http.js';
import { zMonth } from '../../lib/schemas.js';
import { authenticate, ctxOf, requireRole } from '../../middleware/auth.js';
import { AppError } from '../../lib/errors.js';
import { Company, Employee, User } from '../../models/index.js';
import { userView } from '../auth/service.js';
import { activeMemberships, endedNotices, membershipViews } from '../auth/memberships.js';
import { closedBusinesses } from '../accounts/service.js';
import { pendingTransfersFor } from '../accounts/owners.js';
import { stoppableHolds } from '../accounts/identity.js';
import { companyView } from '../company/service.js';
import { employeeView } from '../views.js';
import { audit } from '../audit/service.js';
import { estimateFor } from '../payroll/service.js';
import { advanceBalanceFor } from '../advances/service.js';
import { listPayslips } from '../payslips/service.js';
import { payslipView } from '../payslips/views.js';
import { listMyNotifications, markRead, registerPushToken } from '../notifications/service.js';
import { Types } from 'mongoose';

export const meRouter = Router();
meRouter.use(authenticate);

meRouter.get('/', async (req, res) => {
  const user = await User.findById(req.auth!.userId).lean();
  // The business is this session's, not the user's last one: two devices can be in different businesses.
  const a = req.auth!;
  const company = a.companyId ? await Company.findById(a.companyId).lean() : null;
  const employee = a.employeeId ? await Employee.findOne({ _id: a.employeeId, companyId: a.companyId }).lean() : null;
  const uid = new Types.ObjectId(a.userId);
  const memberships = await membershipViews(await activeMemberships(uid), a.deviceId);
  const activeMembershipId = a.membershipId ?? (a.companyId ? memberships.find((m) => m.companyId === a.companyId)?.id ?? null : null);
  res.json({
    data: {
      user: { ...userView(user), role: a.role, companyId: a.companyId, employeeId: a.employeeId },
      company: company ? await companyView(company) : null,
      employee: employee ? employeeView(employee, { hasDevice: true }) : null,
      activeMembershipId,
      memberships,
      /** Staff accounts locked to another phone (offer "Request device change"). */
      blockedAccounts: memberships.filter((m) => m.lockedToOtherPhone),
      /** "Your access to X ended on …" — shown until dismissed. */
      endedNotices: await endedNotices(uid),
      /** Businesses this person closed that can still be restored. */
      closedBusinesses: await closedBusinesses(uid),
      /** Ownership offers waiting for this number (accept to become main owner). */
      pendingTransfers: user ? await pendingTransfersFor(user) : [],
      /** Support recoveries this person can stop (their own old account, or a business they help run). */
      recoveryHolds: await stoppableHolds(a.userId),
    },
  });
});

meRouter.patch('/', async (req, res) => {
  const b = body(req, z.object({ name: z.string().trim().min(1).max(80).optional(), language: z.enum(['en', 'hi']).optional() }));
  const user = await User.findById(req.auth!.userId);
  if (!user) throw new AppError('UNAUTHORIZED', 'User not found');
  if (b.name) user.name = b.name;
  if (b.language) user.language = b.language;
  await user.save();
  // Language is the person's: keep every staff record linked to them in step.
  if (b.language) await Employee.updateMany({ userId: user._id }, { language: b.language }).setOptions({ skipTenant: true });
  const a = req.auth!;
  res.json({ data: { ...userView(user), role: a.role, companyId: a.companyId, employeeId: a.employeeId } });
});

meRouter.post('/consent', requireRole('employee', 'manager'), async (req, res) => {
  const b = body(req, z.object({ location: z.literal(true) }));
  const ctx = ctxOf(req);
  const emp = await Employee.findOne({ _id: ctx.employeeId, companyId: ctx.companyId });
  if (!emp) throw new AppError('NOT_FOUND', 'Employee not found');
  emp.consent = { location: b.location, at: new Date() } as any;
  await emp.save();
  await audit(ctx, { action: 'employee.consent', entity: 'employee', entityId: emp._id, after: { consent: emp.consent } });
  res.json({ data: employeeView(emp, { hasDevice: true }) });
});

meRouter.post('/push-token', async (req, res) => {
  const b = body(req, z.object({ token: z.string().min(10).max(4096), platform: z.enum(['android', 'ios', 'web']) }));
  await registerPushToken(new Types.ObjectId(req.auth!.userId), b.token, b.platform);
  res.json({ data: { ok: true } });
});

meRouter.get('/salary', requireRole('employee', 'manager'), async (req, res) => {
  const q = query(req, z.object({ month: zMonth.optional() }));
  const ctx = ctxOf(req);
  const est = await estimateFor(ctx.companyId, ctx.employeeId!, q.month);
  const slips = await listPayslips({ ...ctx, role: 'employee' }, {});
  res.json({
    data: {
      estimate: est ? { ...(await payslipView({ ...est.result, employeeName: est.input.employee.name, month: est.month, status: 'draft' }, ctx.language)), asOfDate: est.asOfDate } : null,
      advanceBalancePaise: await advanceBalanceFor(ctx.companyId, ctx.employeeId!),
      payslips: await Promise.all(slips.map((s) => payslipView(s, ctx.language))),
    },
  });
});

meRouter.get('/notifications', async (req, res) => {
  const ctx = ctxOf(req);
  res.json({ data: await listMyNotifications(ctx.companyId, ctx.userId!) });
});

meRouter.post('/notifications/read', async (req, res) => {
  const b = body(req, z.object({ ids: z.array(z.string()).max(100) }));
  const ctx = ctxOf(req);
  await markRead(ctx.companyId, ctx.userId!, b.ids);
  res.json({ data: { ok: true } });
});
