import { Types } from 'mongoose';
import { AssistantSession, Advance, Attendance, Branch, Membership, Notification, PayrollRun, Payslip } from '../../models/index.js';
import type { PlanView } from './plans.js';

const DAY = 86400_000;

/** Plan features we can count, keyed like plan.features. */
export type Usage = Partial<Record<'payroll' | 'advances' | 'payslips' | 'assistant' | 'branches' | 'whatsapp_payslips' | 'whatsapp_assistant' | 'face_match' | 'ca_access', number>>;

const userMessages = (ids: Types.ObjectId[], channel: string, since: Date) =>
  AssistantSession.aggregate([
    { $match: { companyId: { $in: ids }, channel, updatedAt: { $gte: since } } },
    { $unwind: '$history' },
    { $match: { 'history.role': 'user', 'history.at': { $gte: since } } },
    { $count: 'n' },
  ]).then((r) => r[0]?.n ?? 0);

/**
 * How much the businesses on one bill used each paid feature since [since]
 * (the trial start, at most 30 days back). Used to say which plan fits and why.
 */
export async function featureUsage(ids: Types.ObjectId[], since: Date): Promise<Usage> {
  const created = { $gte: since };
  const [face, waSlips, waAssistant, branches, ca, runs, slips, advances, assistant] = await Promise.all([
    Attendance.aggregate([
      { $match: { companyId: { $in: ids }, updatedAt: created } },
      { $unwind: '$punches' },
      { $match: { 'punches.face.result': { $ne: null }, 'punches.serverTime': created } },
      { $count: 'n' },
    ]).then((r) => r[0]?.n ?? 0),
    Notification.countDocuments({ companyId: { $in: ids }, channel: 'whatsapp', template: 'payslip_ready', status: { $ne: 'failed' }, createdAt: created }),
    userMessages(ids, 'whatsapp', since),
    Branch.countDocuments({ companyId: { $in: ids } }),
    Membership.countDocuments({ companyId: { $in: ids }, role: 'ca', status: 'active' }),
    PayrollRun.countDocuments({ companyId: { $in: ids }, createdAt: created }),
    Payslip.countDocuments({ companyId: { $in: ids }, createdAt: created }),
    Advance.countDocuments({ companyId: { $in: ids }, createdAt: created }),
    userMessages(ids, 'assistant', since),
  ]);
  return {
    face_match: face,
    whatsapp_payslips: waSlips,
    whatsapp_assistant: waAssistant,
    // One branch per business comes free; more than that is the feature.
    branches: branches > ids.length ? branches : 0,
    ca_access: ca,
    payroll: runs,
    payslips: slips,
    advances,
    assistant,
  };
}

export const usageSince = (sub: { status?: string; createdAt?: Date } | null | undefined, now = new Date()) => {
  const monthAgo = new Date(now.getTime() - 30 * DAY);
  return sub?.status === 'trialing' && sub.createdAt && sub.createdAt > monthAgo ? sub.createdAt : monthAgo;
};

export interface Recommendation {
  planCode: string;
  /** Why, most telling first: staff fit, then paid features used that cheaper plans lack. */
  reasons: ({ kind: 'staff'; staff: number; limit: number } | { kind: 'feature'; feature: string; count: number })[];
  /** The next cheaper plan that still holds the staff, and what would stop there. */
  cheaper: { planCode: string; loses: { feature: string; count: number }[] } | null;
}

const fitsStaff = (p: PlanView, staff: number) => staff <= p.staffLimit || (p.extraStaffPricePaise > 0 && staff <= p.maxStaffHardCap);

/** The cheapest plan that holds every staff member and covers every paid feature in use. */
export function recommend(plans: PlanView[], staff: number, usage: Usage): Recommendation | null {
  if (!plans.length) return null;
  const sorted = [...plans].sort((a, b) => a.priceMonthlyPaise - b.priceMonthlyPaise);
  const used = Object.entries(usage)
    .filter(([f, n]) => (n ?? 0) > 0 && sorted.some((p) => p.features.includes(f)))
    .sort((a, b) => (b[1] ?? 0) - (a[1] ?? 0))
    .map(([f, n]) => ({ feature: f, count: n ?? 0 }));
  const best = sorted.find((p) => fitsStaff(p, staff) && used.every((u) => p.features.includes(u.feature))) ?? sorted[sorted.length - 1];
  const below = sorted[sorted.indexOf(best) - 1];
  const reasons: Recommendation['reasons'] = [{ kind: 'staff', staff, limit: best.staffLimit }];
  for (const u of used) if (below && !below.features.includes(u.feature) && best.features.includes(u.feature)) reasons.push({ kind: 'feature', ...u });
  const cheaperPlan = sorted.filter((p) => p.priceMonthlyPaise < best.priceMonthlyPaise && fitsStaff(p, staff)).pop();
  return {
    planCode: best.code,
    reasons: reasons.slice(0, 3),
    cheaper: cheaperPlan ? { planCode: cheaperPlan.code, loses: used.filter((u) => !cheaperPlan.features.includes(u.feature)) } : null,
  };
}
