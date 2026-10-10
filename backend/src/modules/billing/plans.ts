import { Types } from 'mongoose';
import { Company, Plan, Subscription, Employee } from '../../models/index.js';
import { DEFAULT_PLANS } from '../config/defaults.js';

export interface PlanView {
  code: string;
  name: string;
  priceMonthlyPaise: number;
  priceYearlyPaise: number;
  currency: string;
  staffLimit: number;
  extraStaffPricePaise: number;
  maxStaffHardCap: number;
  trialDays: number;
  features: string[];
}

const toView = (p: any): PlanView => ({
  code: p.code,
  name: p.name,
  priceMonthlyPaise: p.priceMonthlyPaise,
  priceYearlyPaise: p.priceYearlyPaise,
  currency: p.currency ?? 'INR',
  staffLimit: p.staffLimit,
  extraStaffPricePaise: p.extraStaffPricePaise ?? 0,
  maxStaffHardCap: p.maxStaffHardCap ?? p.staffLimit,
  trialDays: p.trialDays ?? 0,
  features: p.features ?? [],
});

export async function listPlans(country = 'IN'): Promise<PlanView[]> {
  const plans = await Plan.find({ active: true, country }).sort({ sort: 1 }).lean();
  if (plans.length) return plans.map(toView);
  return DEFAULT_PLANS.map((p) => toView({ ...p, currency: 'INR' }));
}

export async function getPlan(code: string): Promise<PlanView> {
  const p = await Plan.findOne({ code }).lean();
  if (p) return toView(p);
  const d = DEFAULT_PLANS.find((x) => x.code === code) ?? DEFAULT_PLANS[0];
  return toView({ ...d, currency: 'INR' });
}

/**
 * Effective plan: active/trialing/past_due subscription → its plan, otherwise Free.
 * A business on another's bill (one bill for several businesses) uses the payer's plan.
 */
export async function companyPlan(company: { _id: Types.ObjectId }, now = new Date()) {
  const own = await Company.findById(company._id).select('billedTo').lean();
  const payerId = own?.billedTo ?? company._id;
  const sub = await Subscription.findOne({ companyId: payerId, status: { $in: ['trialing', 'active', 'past_due', 'pending', 'cancelled'] } })
    .sort({ createdAt: -1 })
    .lean();
  let effective = 'free';
  if (sub) {
    const inTrial = sub.status === 'trialing' && sub.trialEndsAt && sub.trialEndsAt > now;
    const paidUp = (sub.status === 'active' || sub.status === 'past_due') && (!sub.currentPeriodEnd || sub.currentPeriodEnd > now);
    const cancelledButPaid = sub.status === 'cancelled' && sub.currentPeriodEnd && sub.currentPeriodEnd > now;
    if (inTrial || paidUp || cancelledButPaid) effective = sub.planCode;
  }
  return { plan: await getPlan(effective), subscription: sub };
}

/** Businesses paid together: the payer and every business billed to it. */
export async function billingGroupIds(companyId: Types.ObjectId): Promise<Types.ObjectId[]> {
  const c = await Company.findById(companyId).select('billedTo').lean();
  const payer = c?.billedTo ?? companyId;
  const members = await Company.find({ billedTo: payer, closedAt: null }).select('_id').lean();
  return [payer, ...members.map((m) => m._id)];
}

/** Staff counted for the plan limit and price: across the whole bill. */
export async function billingStaffCount(companyId: Types.ObjectId): Promise<number> {
  const ids = await billingGroupIds(companyId);
  return Employee.countDocuments({ companyId: { $in: ids }, status: 'active', deletedAt: null }).setOptions({ skipTenant: true });
}

export async function activeStaffCount(companyId: Types.ObjectId): Promise<number> {
  return Employee.countDocuments({ companyId, status: 'active', deletedAt: null });
}
