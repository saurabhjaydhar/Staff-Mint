import { Types, type PipelineStage } from 'mongoose';
import { AppError, notFound } from '../../lib/errors.js';
import { AdminAction, AdminUser, Branch, Company, Config, Employee, Membership, Notification, RecoveryRequest, Subscription, User } from '../../models/index.js';
import { DEFAULT_CONFIG, DEFAULT_PLANS } from '../config/defaults.js';
import { companyPlan, getPlan } from '../billing/plans.js';
import { trialFromSubscription } from '../billing/trial.js';
import { adminView, assertStrongPassword, checkPassword, hashPassword } from './auth.js';

const DAY = 86400_000;
export type BusinessStatus = 'trial' | 'paid' | 'past_due' | 'free' | 'closed' | 'billed_with';
export const BUSINESS_STATUSES: BusinessStatus[] = ['trial', 'paid', 'past_due', 'free', 'closed', 'billed_with'];

const escapeRegex = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

/**
 * Pipeline stages that attach each business's latest subscription and its status,
 * computed in the database so lists and counts stay fast as businesses grow.
 */
function statusStages(now: Date): PipelineStage[] {
  return [
    {
      $lookup: {
        from: Subscription.collection.name,
        let: { cid: '$_id' },
        pipeline: [{ $match: { $expr: { $eq: ['$companyId', '$$cid'] } } }, { $sort: { createdAt: -1 } }, { $limit: 1 }],
        as: 'sub',
      },
    },
    { $set: { sub: { $first: '$sub' } } },
    {
      $set: {
        status: {
          $switch: {
            branches: [
              { case: { $ne: [{ $ifNull: ['$closedAt', null] }, null] }, then: 'closed' },
              { case: { $ne: [{ $ifNull: ['$billedTo', null] }, null] }, then: 'billed_with' },
              { case: { $and: [{ $eq: ['$sub.status', 'trialing'] }, { $gt: ['$sub.trialEndsAt', now] }] }, then: 'trial' },
              { case: { $eq: ['$sub.status', 'past_due'] }, then: 'past_due' },
              {
                case: {
                  $or: [
                    { $and: [{ $eq: ['$sub.status', 'active'] }, { $or: [{ $eq: [{ $ifNull: ['$sub.currentPeriodEnd', null] }, null] }, { $gt: ['$sub.currentPeriodEnd', now] }] }] },
                    { $and: [{ $eq: ['$sub.status', 'cancelled'] }, { $gt: ['$sub.currentPeriodEnd', now] }] },
                  ],
                },
                then: 'paid',
              },
            ],
            default: 'free',
          },
        },
      },
    },
  ];
}

/** Monthly revenue from one subscription, in paise. */
async function monthlyPaise(sub: { planCode: string; interval?: string | null; pricePaise?: number | null }) {
  if (sub.pricePaise != null) return sub.interval === 'yearly' ? Math.round(sub.pricePaise / 12) : sub.pricePaise;
  const plan = await getPlan(sub.planCode);
  return sub.interval === 'yearly' ? Math.round(plan.priceYearlyPaise / 12) : plan.priceMonthlyPaise;
}

export async function stats(now = new Date()) {
  const [byStatus, owners, staff, newWeek, newMonth, perDay, pendingRecoveries, failedMessages, trialsEndingSoon] = await Promise.all([
    Company.aggregate([...statusStages(now), { $group: { _id: '$status', n: { $sum: 1 }, plans: { $push: '$sub.planCode' } } }]),
    Company.distinct('ownerUserId', { closedAt: null, deletedAt: null }),
    Employee.countDocuments({ status: 'active', deletedAt: null }).setOptions({ skipTenant: true }),
    Company.countDocuments({ createdAt: { $gte: new Date(now.getTime() - 7 * DAY) } }),
    Company.countDocuments({ createdAt: { $gte: new Date(now.getTime() - 30 * DAY) } }),
    Company.aggregate([
      { $match: { createdAt: { $gte: new Date(now.getTime() - 30 * DAY) } } },
      { $group: { _id: { $dateToString: { format: '%Y-%m-%d', date: '$createdAt', timezone: 'Asia/Kolkata' } }, n: { $sum: 1 } } },
      { $sort: { _id: 1 } },
    ]),
    RecoveryRequest.countDocuments({ status: 'submitted' }),
    Notification.countDocuments({ status: 'failed', createdAt: { $gte: new Date(now.getTime() - 7 * DAY) } }).setOptions({ skipTenant: true }),
    Subscription.countDocuments({ status: 'trialing', trialEndsAt: { $gt: now, $lte: new Date(now.getTime() + 3 * DAY) } }).setOptions({ skipTenant: true }),
  ]);
  const count = (s: BusinessStatus) => byStatus.find((x) => x._id === s)?.n ?? 0;
  const paidPlans: Record<string, number> = {};
  for (const row of byStatus.filter((x) => x._id === 'paid' || x._id === 'past_due')) for (const p of row.plans as string[]) paidPlans[p] = (paidPlans[p] ?? 0) + 1;

  // Revenue: latest paid subscription of each paying business.
  const paying = await Company.aggregate([...statusStages(now), { $match: { status: 'paid' } }, { $project: { sub: 1 } }]);
  let mrrPaise = 0;
  for (const p of paying) mrrPaise += await monthlyPaise(p.sub);

  // Signups per day for the last 30 days, zeros included.
  const days: { date: string; count: number }[] = [];
  const fmt = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Kolkata', year: 'numeric', month: '2-digit', day: '2-digit' });
  for (let i = 29; i >= 0; i--) {
    const date = fmt.format(new Date(now.getTime() - i * DAY));
    days.push({ date, count: perDay.find((d) => d._id === date)?.n ?? 0 });
  }

  return {
    businesses: {
      total: byStatus.reduce((a, x) => a + x.n, 0) - count('closed'),
      trial: count('trial'),
      paid: count('paid'),
      pastDue: count('past_due'),
      free: count('free'),
      billedWith: count('billed_with'),
      closed: count('closed'),
    },
    owners: owners.length,
    staff,
    signups: { week: newWeek, month: newMonth, perDay: days },
    mrrPaise,
    paidPlans,
    trialsEndingSoon,
    pendingRecoveries,
    failedMessages,
  };
}

/** Businesses, newest first; search by name or owner phone; filter by status. */
export async function listCompanies(q: { search?: string; status?: BusinessStatus; page: number; limit: number }, now = new Date()) {
  const match: Record<string, unknown> = {};
  const search = q.search?.trim();
  if (search) {
    const digits = search.replace(/\D/g, '');
    const or: Record<string, unknown>[] = [{ name: { $regex: escapeRegex(search), $options: 'i' } }];
    if (Types.ObjectId.isValid(search)) or.push({ _id: new Types.ObjectId(search) });
    if (digits.length >= 6) {
      const users = await User.find({ phone: { $regex: escapeRegex(digits.slice(-10)) + '$' } }).select('_id').limit(50).lean();
      if (users.length) {
        const ms = await Membership.find({ userId: { $in: users.map((u) => u._id) }, role: 'owner' }).select('companyId').lean();
        or.push({ _id: { $in: ms.map((m) => m.companyId) } });
      }
    }
    match.$or = or;
  }
  const [res] = await Company.aggregate([
    { $match: match },
    { $sort: { createdAt: -1 } },
    ...statusStages(now),
    ...(q.status ? [{ $match: { status: q.status } }] : []),
    { $facet: { total: [{ $count: 'n' }], rows: [{ $skip: (q.page - 1) * q.limit }, { $limit: q.limit }] } },
  ]);
  const rows: any[] = res?.rows ?? [];
  const ids = rows.map((r) => r._id);
  const [staff, owners] = await Promise.all([
    Employee.aggregate([{ $match: { companyId: { $in: ids }, status: 'active', deletedAt: null } }, { $group: { _id: '$companyId', n: { $sum: 1 } } }]),
    User.find({ _id: { $in: rows.map((r) => r.ownerUserId) } }).select('name phone').lean(),
  ]);
  return {
    total: res?.total?.[0]?.n ?? 0,
    page: q.page,
    limit: q.limit,
    rows: rows.map((r) => {
      const owner = owners.find((o) => String(o._id) === String(r.ownerUserId));
      return {
        id: String(r._id),
        name: r.name,
        businessType: r.businessType,
        status: r.status as BusinessStatus,
        planCode: r.status === 'free' || r.status === 'closed' ? 'free' : (r.sub?.planCode ?? 'free'),
        trialEndsAt: r.status === 'trial' ? r.sub.trialEndsAt : null,
        paidUntil: r.status === 'paid' || r.status === 'past_due' ? (r.sub?.currentPeriodEnd ?? null) : null,
        staffCount: staff.find((s) => String(s._id) === String(r._id))?.n ?? 0,
        owner: owner ? { name: owner.name, phone: owner.phone } : null,
        createdAt: r.createdAt,
      };
    }),
  };
}

export async function companyDetail(id: string, now = new Date()) {
  if (!Types.ObjectId.isValid(id)) throw notFound('Business');
  const company = await Company.findById(id).lean();
  if (!company) throw notFound('Business');
  const [[withStatus], { plan, subscription }, subs, members, staffActive, staffTotal, branches, payer, onBill, actions, failed] = await Promise.all([
    Company.aggregate([{ $match: { _id: company._id } }, ...statusStages(now), { $project: { status: 1 } }]),
    companyPlan(company, now),
    Subscription.find({ companyId: company._id }).sort({ createdAt: -1 }).limit(10).lean(),
    Membership.find({ companyId: company._id, status: 'active', role: { $in: ['owner', 'manager', 'ca'] } }).lean(),
    Employee.countDocuments({ companyId: company._id, status: 'active', deletedAt: null }),
    Employee.countDocuments({ companyId: company._id, deletedAt: null }),
    Branch.countDocuments({ companyId: company._id, deletedAt: null }),
    company.billedTo ? Company.findById(company.billedTo).select('name').lean() : null,
    Company.find({ billedTo: company._id, closedAt: null }).select('name').lean(),
    AdminAction.find({ companyId: company._id }).sort({ createdAt: -1 }).limit(20).lean(),
    Notification.find({ companyId: company._id, status: 'failed' }).sort({ createdAt: -1 }).limit(10).lean(),
  ]);
  const users = await User.find({ _id: { $in: members.map((m) => m.userId) } }).select('name phone email lastLoginAt').lean();
  return {
    id: String(company._id),
    name: company.name,
    businessType: company.businessType,
    timezone: company.timezone,
    address: company.location?.address ?? null,
    createdAt: (company as any).createdAt,
    closedAt: company.closedAt ?? null,
    status: (withStatus?.status ?? 'free') as BusinessStatus,
    plan: { code: plan.code, name: plan.name, staffLimit: plan.staffLimit },
    trial: await trialFromSubscription(subscription, now),
    billedTo: payer ? { id: String(payer._id), name: payer.name } : null,
    onThisBill: onBill.map((c) => ({ id: String(c._id), name: c.name })),
    staff: { active: staffActive, total: staffTotal },
    branches,
    people: members.map((m) => {
      const u = users.find((x) => String(x._id) === String(m.userId));
      return { role: m.role, name: u?.name ?? '', phone: u?.phone ?? '', main: String(m.userId) === String(company.ownerUserId) };
    }),
    subscriptions: subs.map((s) => ({
      id: String(s._id),
      provider: s.provider,
      planCode: s.planCode,
      status: s.status,
      interval: s.interval,
      trialEndsAt: s.trialEndsAt ?? null,
      currentPeriodEnd: s.currentPeriodEnd ?? null,
      pricePaise: s.pricePaise ?? null,
      createdAt: (s as any).createdAt,
    })),
    failedMessages: failed.map((n) => ({ id: String(n._id), channel: n.channel, template: n.template ?? null, to: n.to ?? null, error: n.error ?? null, createdAt: (n as any).createdAt })),
    actions: actions.map(actionView),
  };
}

/**
 * Put a business on a plan by hand (free months, deals, fixing a stuck payment).
 * Free ends any internal paid plan or trial. A live Razorpay subscription must be cancelled there first.
 */
export async function setCompanyPlan(id: string, input: { planCode: string; months: number }, now = new Date()) {
  const company = await Company.findOne({ _id: id, deletedAt: null }).lean();
  if (!company) throw notFound('Business');
  if (input.planCode !== 'free') {
    const plan = await getPlan(input.planCode);
    if (plan.code !== input.planCode) throw new AppError('VALIDATION_ERROR', `Unknown plan: ${input.planCode}`);
  }
  const live = await Subscription.findOne({ companyId: company._id, provider: { $ne: 'internal' }, status: { $in: ['active', 'past_due', 'pending'] } }).lean();
  if (live) throw new AppError('CONFLICT', `This business pays through ${live.provider}. Cancel that subscription first.`, { reason: 'provider_subscription' });
  await Subscription.updateMany({ companyId: company._id, status: { $in: ['trialing', 'active', 'past_due', 'pending', 'free'] } }, { status: 'cancelled', cancelledAt: now, currentPeriodEnd: now });
  if (input.planCode === 'free') {
    await Subscription.create({ companyId: company._id, provider: 'internal', planCode: 'free', status: 'free', currency: company.currency ?? 'INR' });
    return { planCode: 'free', until: null };
  }
  const until = new Date(now);
  until.setMonth(until.getMonth() + input.months);
  await Subscription.create({ companyId: company._id, provider: 'internal', planCode: input.planCode, status: 'active', currentPeriodEnd: until, pricePaise: 0, currency: company.currency ?? 'INR' });
  return { planCode: input.planCode, until };
}

/** Every known setting: code default, live value, and how many businesses override it. */
export async function listConfigs() {
  const [globals, overrides] = await Promise.all([
    Config.find({ companyId: null }).lean(),
    Config.aggregate([{ $match: { companyId: { $ne: null } } }, { $group: { _id: '$key', n: { $sum: 1 } } }]),
  ]);
  const keys = [...new Set([...Object.keys(DEFAULT_CONFIG), ...globals.map((g) => g.key)])].sort();
  return keys.map((key) => {
    const g = globals.find((x) => x.key === key);
    return {
      key,
      value: g ? g.value : DEFAULT_CONFIG[key],
      defaultValue: DEFAULT_CONFIG[key] ?? null,
      changed: !!g && JSON.stringify(g.value) !== JSON.stringify(DEFAULT_CONFIG[key]),
      businessOverrides: overrides.find((o) => o._id === key)?.n ?? 0,
    };
  });
}

/** A known setting must keep its type (a number stays a number) so a typo can't break the app. */
export function checkConfigValue(key: string, value: unknown) {
  if (!(key in DEFAULT_CONFIG)) return;
  const d = DEFAULT_CONFIG[key];
  const type = (v: unknown) => (Array.isArray(v) ? 'list' : v === null ? 'null' : typeof v);
  if (type(d) !== type(value)) throw new AppError('VALIDATION_ERROR', `${key} must be a ${type(d)}`);
}

export async function listMessages(q: { status?: string; channel?: string; companyId?: string; page: number; limit: number }) {
  const filter: Record<string, unknown> = { channel: q.channel ?? { $ne: 'in_app' } };
  if (q.status) filter.status = q.status;
  if (q.companyId && Types.ObjectId.isValid(q.companyId)) filter.companyId = new Types.ObjectId(q.companyId);
  const [rows, total] = await Promise.all([
    Notification.find(filter).sort({ createdAt: -1 }).skip((q.page - 1) * q.limit).limit(q.limit).setOptions({ skipTenant: true }).lean(),
    Notification.countDocuments(filter).setOptions({ skipTenant: true }),
  ]);
  const companies = await Company.find({ _id: { $in: [...new Set(rows.map((r) => String(r.companyId)))] } }).select('name').lean();
  return {
    total,
    page: q.page,
    limit: q.limit,
    rows: rows.map((n) => ({
      id: String(n._id),
      companyId: String(n.companyId),
      companyName: companies.find((c) => String(c._id) === String(n.companyId))?.name ?? '',
      channel: n.channel,
      template: n.template ?? null,
      title: n.title ?? null,
      to: n.to ?? null,
      status: n.status,
      provider: n.provider ?? null,
      error: n.error ?? null,
      createdAt: (n as any).createdAt,
    })),
  };
}

export const actionView = (a: any) => ({
  id: String(a._id),
  actor: a.actor,
  action: a.action,
  companyId: a.companyId ? String(a.companyId) : null,
  target: a.target ?? null,
  details: a.details ?? {},
  createdAt: a.createdAt,
});

export async function listActions(q: { companyId?: string; page: number; limit: number }) {
  const filter: Record<string, unknown> = {};
  if (q.companyId && Types.ObjectId.isValid(q.companyId)) filter.companyId = new Types.ObjectId(q.companyId);
  const [rows, total] = await Promise.all([AdminAction.find(filter).sort({ createdAt: -1 }).skip((q.page - 1) * q.limit).limit(q.limit).lean(), AdminAction.countDocuments(filter)]);
  return { total, page: q.page, limit: q.limit, rows: rows.map(actionView) };
}

// ---- Admin accounts ----

export async function listAdmins() {
  return (await AdminUser.find().sort({ createdAt: 1 }).lean()).map(adminView);
}

export async function createAdmin(input: { email: string; name?: string; role: 'admin' | 'viewer'; password: string }) {
  assertStrongPassword(input.password);
  const email = input.email.trim().toLowerCase();
  if (await AdminUser.exists({ email })) throw new AppError('CONFLICT', 'An admin with this email already exists');
  const a = await AdminUser.create({ email, name: input.name ?? '', role: input.role, passwordHash: await hashPassword(input.password) });
  return adminView(a);
}

export async function updateAdmin(id: string, patch: { role?: 'admin' | 'viewer'; active?: boolean; name?: string }, actorId: string | null) {
  if (!Types.ObjectId.isValid(id)) throw notFound('Admin');
  const a = await AdminUser.findById(id);
  if (!a) throw notFound('Admin');
  const losesAdmin = (patch.role && patch.role !== 'admin') || patch.active === false;
  if (losesAdmin && a.role === 'admin' && a.active) {
    if (actorId && String(a._id) === actorId) throw new AppError('CONFLICT', 'You cannot remove your own admin access');
    if ((await AdminUser.countDocuments({ role: 'admin', active: true })) <= 1) throw new AppError('CONFLICT', 'Keep at least one active admin');
  }
  if (patch.name !== undefined) a.name = patch.name;
  if (patch.role) a.role = patch.role;
  if (patch.active !== undefined) {
    a.active = patch.active;
    if (!patch.active) a.tokenVersion += 1; // signs them out everywhere
  }
  if (patch.role) a.tokenVersion += 1; // new role takes effect on next sign-in
  await a.save();
  return adminView(a);
}

export async function changeOwnPassword(id: string, current: string, next: string) {
  const a = await AdminUser.findById(id);
  if (!a || !(await checkPassword(current, a.passwordHash))) throw new AppError('UNAUTHORIZED', 'Current password is wrong');
  assertStrongPassword(next);
  a.passwordHash = await hashPassword(next);
  a.tokenVersion += 1;
  await a.save();
}


/** Built-in plans, shaped like saved ones, before anyone has edited prices. */
export async function listPlansForAdmin() {
  return DEFAULT_PLANS.map((p) => ({ ...p, country: 'IN', currency: 'INR', active: true }));
}

/** The parts of a plan worth keeping in the change log. */
export const planSummary = (p: any) =>
  p ? { name: p.name, priceMonthlyPaise: p.priceMonthlyPaise, priceYearlyPaise: p.priceYearlyPaise, staffLimit: p.staffLimit, trialDays: p.trialDays, features: p.features, active: p.active } : null;
