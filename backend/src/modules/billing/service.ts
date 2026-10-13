import { Types } from 'mongoose';
import { AppError } from '../../lib/errors.js';
import type { Ctx } from '../../lib/context.js';
import { Company, Plan, Receipt, Subscription, User, WebhookEvent } from '../../models/index.js';
import { provider } from '../../providers/registry.js';
import type { PaymentEvent, PaymentInfo, PaymentProvider } from '../../providers/types.js';
import { activeStaffCount, billingGroupIds, billingStaffCount, companyPlan, getPlan, listPlans, type PlanView } from './plans.js';
import { featureUsage, recommend, usageSince } from './usage.js';
import { getConfig, setConfig } from '../config/service.js';
import { trialFromSubscription } from './trial.js';
import { audit } from '../audit/service.js';
import { systemCtx } from '../../lib/context.js';
import { logger } from '../../lib/logger.js';

export async function subscriptionSummary(ctx: Ctx) {
  const { plan, subscription } = await companyPlan({ _id: ctx.companyId });
  const company = await Company.findById(ctx.companyId).select('country').lean();
  const [ids, billStaff, plans, lockMonths] = await Promise.all([
    billingGroupIds(ctx.companyId),
    billingStaffCount(ctx.companyId),
    listPlans(company?.country ?? 'IN'),
    getConfig<number>('billing.priceLockMonths'),
  ]);
  const usage = await featureUsage(ids, usageSince(subscription as any));
  return {
    plan,
    subscription: subscription
      ? {
          status: subscription.status,
          planCode: subscription.planCode,
          interval: subscription.interval,
          trialEndsAt: subscription.trialEndsAt ?? null,
          currentPeriodEnd: subscription.currentPeriodEnd ?? null,
          priceLockedUntil: subscription.priceLockedUntil ?? null,
          pricePaise: subscription.pricePaise ?? null,
          provider: subscription.provider,
        }
      : null,
    staffCount: await activeStaffCount(ctx.companyId),
    trial: await trialFromSubscription(subscription),
    /** Staff across every business on the bill (what the plan limit counts). */
    billStaffCount: billStaff,
    /** Paid features used since the trial started (at most 30 days back). */
    usage,
    /** The cheapest plan that fits the staff and what they use, and why. */
    recommendation: recommend(plans, billStaff, usage),
    priceLockMonths: lockMonths ?? 0,
    /** Paid together with another business (one bill); manage the plan there. */
    billedTo: await payerOf(ctx.companyId),
  };
}

async function payerOf(companyId: Types.ObjectId) {
  const c = await Company.findById(companyId).select('billedTo').lean();
  if (!c?.billedTo) return null;
  const payer = await Company.findById(c.billedTo).select('name').lean();
  return payer ? { companyId: String(payer._id), name: payer.name } : null;
}

export async function subscribe(ctx: Ctx, planCode: string, interval: 'monthly' | 'yearly') {
  const plan = await getPlan(planCode);
  if (plan.code !== planCode || plan.priceMonthlyPaise <= 0) throw new AppError('VALIDATION_ERROR', 'Choose a paid plan');
  const company = await Company.findById(ctx.companyId).lean();
  if (company?.billedTo) throw new AppError('CONFLICT', 'This business is paid together with another one. Change the plan there.', { reason: 'billed_elsewhere' });
  const owner = await User.findById(company!.ownerUserId).lean();
  // One bill: staff across every business on it, plus a small price per extra business.
  const group = await billingGroupIds(ctx.companyId);
  const staff = await billingStaffCount(ctx.companyId);
  if (staff > plan.maxStaffHardCap) throw new AppError('PLAN_LIMIT', `${plan.name} supports up to ${plan.maxStaffHardCap} staff`);
  const yearly = interval === 'yearly' ? 10 : 1;
  const extra = Math.max(0, staff - plan.staffLimit) * plan.extraStaffPricePaise * yearly;
  const extraBusinesses = (group.length - 1) * (await getConfig<number>('billing.extraBusinessPricePaise')) * yearly;
  const amountPaise = (interval === 'yearly' ? plan.priceYearlyPaise : plan.priceMonthlyPaise) + extra + extraBusinesses;
  // During a free trial the first charge waits until the trial ends: nothing is taken today.
  const { subscription: current } = await companyPlan({ _id: ctx.companyId });
  const trial = await trialFromSubscription(current);
  const trialDays = trial?.active ? trial.daysLeft : 0;
  const payments = await provider('payments', company!.paymentProvider);
  const planDoc = await Plan.findOne({ code: planCode }).lean();
  const providerPlanId = await providerPlanFor(payments, plan, interval, amountPaise, (planDoc?.providerPlanIds as any)?.[payments.name]?.[interval]);
  const created = await payments.createSubscription({
    planCode,
    providerPlanId,
    interval,
    amountPaise,
    currency: plan.currency,
    customer: { name: company!.name, phone: owner?.phone ?? '', companyId: String(ctx.companyId) },
    trialDays: trialDays || undefined,
  });
  const lockMonths = await getConfig<number>('billing.priceLockMonths');
  await Subscription.create({
    companyId: ctx.companyId,
    provider: payments.name,
    providerSubId: created.providerSubId,
    planCode,
    interval,
    status: 'pending',
    pricePaise: amountPaise,
    currency: plan.currency,
    priceLockedUntil: new Date(Date.now() + lockMonths * 30 * 86400_000),
  });
  await audit(ctx, { action: 'billing.subscribe', entity: 'subscription', after: { planCode, interval, amountPaise, provider: payments.name } });
  return {
    provider: payments.name,
    subscriptionId: created.providerSubId,
    checkoutUrl: created.checkoutUrl,
    keyId: created.keyId ?? null,
    amountPaise,
    /** First charge date: the trial end while a trial runs, otherwise now. */
    firstChargeAt: trial?.active ? trial.endsAt : new Date(),
  };
}

/**
 * The gateway plan to bill against. A plan id set by admin is used for the plain plan price; any other
 * price (extra staff, more businesses on one bill) or a missing id gets a gateway plan made once and remembered.
 */
export async function providerPlanFor(
  payments: PaymentProvider,
  plan: PlanView,
  interval: 'monthly' | 'yearly',
  amountPaise: number,
  adminSetId?: string,
): Promise<string | undefined> {
  const base = interval === 'yearly' ? plan.priceYearlyPaise : plan.priceMonthlyPaise;
  if (adminSetId && amountPaise === base) return adminSetId;
  if (!payments.createPlan) return adminSetId;
  const key = `${payments.name}:${plan.code}:${interval}:${amountPaise}`;
  const known = (await getConfig<Record<string, string>>(PROVIDER_PLANS_KEY)) ?? {};
  if (known[key]) return known[key];
  const id = await payments.createPlan({ planCode: plan.code, name: plan.name, interval, amountPaise, currency: plan.currency });
  // Re-read before saving so two owners subscribing at once don't drop each other's entry.
  const latest = (await getConfig<Record<string, string>>(PROVIDER_PLANS_KEY)) ?? {};
  await setConfig(PROVIDER_PLANS_KEY, { ...latest, [key]: id });
  return id;
}
const PROVIDER_PLANS_KEY = 'billing.providerPlans';

export async function cancel(ctx: Ctx) {
  const sub = await Subscription.findOne({ companyId: ctx.companyId, status: { $in: ['active', 'past_due', 'trialing', 'pending'] } }).sort({ createdAt: -1 });
  if (!sub) throw new AppError('NOT_FOUND', 'No active subscription');
  if (sub.providerSubId && sub.provider !== 'internal') await (await provider('payments', sub.provider)).cancelSubscription(sub.providerSubId);
  sub.status = 'cancelled';
  sub.cancelledAt = new Date();
  await sub.save();
  const exportDays = await getConfig<number>('billing.exportWindowDays');
  await Company.updateOne({ _id: ctx.companyId }, { cancelledAt: new Date(), exportAvailableUntil: new Date(Date.now() + exportDays * 86400_000) });
  await audit(ctx, { action: 'billing.cancel', entity: 'subscription', entityId: sub._id, after: { status: 'cancelled' } });
  return sub;
}

const addPeriod = (from: Date, interval: string) => {
  const d = new Date(from);
  if (interval === 'yearly') d.setFullYear(d.getFullYear() + 1);
  else d.setMonth(d.getMonth() + 1);
  return d;
};

/** Apply internal payment events (adapters translate vendor webhooks into these). Idempotent by eventId. */
export async function handlePaymentEvents(providerName: string, events: PaymentEvent[]) {
  for (const ev of events) {
    try {
      await WebhookEvent.create({ provider: providerName, kind: ev.type, eventId: `${providerName}:${ev.eventId}`, payload: ev.raw });
    } catch (e: any) {
      if (e?.code === 11000) continue; // duplicate delivery
      throw e;
    }
    if (!ev.providerSubId) continue;
    const sub = await Subscription.findOne({ provider: providerName, providerSubId: ev.providerSubId }).setOptions({ skipTenant: true });
    if (!sub) {
      logger.warn({ ev: ev.type, sub: ev.providerSubId }, 'payment event for unknown subscription');
      continue;
    }
    const before = sub.toObject();
    switch (ev.type) {
      case 'subscription.activated':
      case 'subscription.charged':
      case 'payment.succeeded':
        sub.status = 'active';
        sub.currentPeriodEnd = ('currentPeriodEnd' in ev && ev.currentPeriodEnd) || addPeriod(new Date(), sub.interval);
        await Subscription.updateMany({ companyId: sub.companyId, _id: { $ne: sub._id }, status: { $in: ['trialing', 'active', 'pending', 'past_due', 'free'] } }, { status: 'cancelled', cancelledAt: new Date() });
        await Company.updateOne({ _id: sub.companyId }, { planCode: sub.planCode, cancelledAt: null });
        break;
      case 'subscription.pending':
      case 'subscription.halted':
      case 'payment.failed':
        if (sub.status === 'active') sub.status = 'past_due';
        break;
      case 'subscription.cancelled':
      case 'subscription.completed':
        sub.status = 'cancelled';
        sub.cancelledAt = new Date();
        break;
    }
    await sub.save();
    const paid = ev.type === 'payment.succeeded' ? { id: ev.providerPaymentId, amountPaise: ev.amountPaise, invoiceId: ev.invoiceId ?? null } : 'payment' in ev ? ev.payment : undefined;
    if (paid && (ev.type === 'payment.succeeded' || ev.type === 'subscription.charged' || ev.type === 'subscription.activated')) await recordReceipt(sub, providerName, paid);
    await audit(systemCtx(sub.companyId as Types.ObjectId), { action: `billing.${ev.type}`, entity: 'subscription', entityId: sub._id, before, after: sub });
  }
}

/** One receipt per gateway payment; the same payment can arrive in two webhooks. */
async function recordReceipt(sub: any, providerName: string, pay: PaymentInfo) {
  await Receipt.updateOne(
    { companyId: sub.companyId, provider: providerName, providerPaymentId: pay.id },
    {
      $setOnInsert: {
        subscriptionId: sub._id,
        planCode: sub.planCode,
        interval: sub.interval,
        amountPaise: pay.amountPaise || sub.pricePaise || 0,
        currency: sub.currency ?? 'INR',
        paidAt: new Date(),
        periodEnd: sub.currentPeriodEnd ?? null,
      },
      ...(pay.invoiceId ? { $set: { invoiceId: pay.invoiceId } } : {}),
    },
    { upsert: true },
  );
}

export async function listReceipts(ctx: Ctx) {
  const rows = await Receipt.find({ companyId: ctx.companyId }).sort({ paidAt: -1 }).limit(36).lean();
  const plans = new Map<string, string>();
  for (const r of rows) if (r.planCode && !plans.has(r.planCode)) plans.set(r.planCode, (await getPlan(r.planCode)).name);
  return rows.map((r) => ({
    id: String(r._id),
    planCode: r.planCode ?? null,
    planName: r.planCode ? plans.get(r.planCode) ?? r.planCode : null,
    interval: r.interval ?? 'monthly',
    amountPaise: r.amountPaise,
    currency: r.currency ?? 'INR',
    paidAt: r.paidAt,
    periodEnd: r.periodEnd ?? null,
    hasInvoice: !!r.invoiceId,
  }));
}

/** The gateway's invoice for one receipt (GST invoice for Razorpay). */
export async function receiptLink(ctx: Ctx, id: string) {
  const r = Types.ObjectId.isValid(id) ? await Receipt.findOne({ _id: id, companyId: ctx.companyId }).lean() : null;
  if (!r) throw new AppError('NOT_FOUND', 'Receipt not found');
  const p = r.invoiceId ? await provider('payments', r.provider).catch(() => null) : null;
  const url = p?.invoiceUrl && r.invoiceId ? await p.invoiceUrl(r.invoiceId) : null;
  if (!url) throw new AppError('NOT_FOUND', 'No invoice for this payment yet');
  return { url };
}
