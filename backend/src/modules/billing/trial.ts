import { Types } from 'mongoose';
import { DateTime } from 'luxon';
import { AppError, notFound } from '../../lib/errors.js';
import { normalizePhone } from '../../lib/phone.js';
import { Company, Subscription, User } from '../../models/index.js';
import { getConfig } from '../config/service.js';
import { notifyOwners, sendWhatsApp } from '../notifications/service.js';
import { companyPlan, getPlan } from './plans.js';

const DAY = 86400_000;

/** How long "Your trial ended" stays on the home screen after the trial runs out. */
const ENDED_NOTICE_DAYS = 30;

/** Features as owners know them, for "what stops" after the trial. */
const FEATURE_LABELS: Record<string, { en: string; hi: string }> = {
  payroll: { en: 'salary calculation', hi: 'सैलरी हिसाब' },
  advances: { en: 'advances', hi: 'एडवांस' },
  payslips: { en: 'payslips', hi: 'सैलरी स्लिप' },
  assistant: { en: 'the assistant', hi: 'असिस्टेंट' },
  reports: { en: 'reports', hi: 'रिपोर्ट' },
  roster: { en: 'the roster', hi: 'रोस्टर' },
  roster_repeat: { en: 'repeating the roster', hi: 'रोस्टर दोहराना' },
  roster_swaps: { en: 'shift swaps', hi: 'शिफ़्ट अदला-बदली' },
  verification: { en: 'background checks', hi: 'बैकग्राउंड जाँच' },
  branches: { en: 'more branches', hi: 'ज़्यादा ब्रांच' },
  whatsapp_payslips: { en: 'payslips on WhatsApp', hi: 'WhatsApp पर सैलरी स्लिप' },
  whatsapp_assistant: { en: 'the WhatsApp assistant', hi: 'WhatsApp असिस्टेंट' },
  face_match: { en: 'face check', hi: 'चेहरा मिलान' },
  ca_access: { en: 'accountant access', hi: 'अकाउंटेंट एक्सेस' },
  priority_support: { en: 'priority support', hi: 'प्राथमिकता सहायता' },
};

export interface TrialView {
  planCode: string;
  planName: string;
  endsAt: Date;
  /** Whole days left, counting today's part as one (0 once it has ended). */
  daysLeft: number;
  active: boolean;
  /** Ended and nothing bought since: the business is on Free. Shown for 30 days. */
  ended: boolean;
  /** Paid features that stop when the trial ends (keys from plan.features). */
  paidFeatures: string[];
}

export const daysLeftOf = (endsAt: Date, now = new Date()) => Math.max(0, Math.ceil((endsAt.getTime() - now.getTime()) / DAY));

/** Trial state of a business (its payer's, when on one bill). Null when there is no trial to show. */
export async function trialView(company: { _id: Types.ObjectId }, now = new Date()): Promise<TrialView | null> {
  const { subscription } = await companyPlan(company, now);
  return trialFromSubscription(subscription, now);
}

export async function trialFromSubscription(sub: any, now = new Date()): Promise<TrialView | null> {
  if (!sub || sub.status !== 'trialing' || !sub.trialEndsAt) return null;
  const endsAt: Date = sub.trialEndsAt;
  const active = endsAt > now;
  if (!active && now.getTime() - endsAt.getTime() > ENDED_NOTICE_DAYS * DAY) return null;
  const [plan, free] = await Promise.all([getPlan(sub.planCode), getPlan('free')]);
  return {
    planCode: plan.code,
    planName: plan.name,
    endsAt,
    daysLeft: daysLeftOf(endsAt, now),
    active,
    ended: !active,
    paidFeatures: plan.features.filter((f) => !free.features.includes(f)),
  };
}

/**
 * The trial a new business gets. Each owner gets one trial: a business created
 * while their trial runs shares its end date; after it has ended, new businesses start on Free.
 */
export async function trialForNewBusiness(userId: Types.ObjectId, now = new Date()): Promise<{ planCode: string; endsAt: Date } | null> {
  const plan = await getPlan(await getConfig<string>('signup.trialPlan'));
  if (!(plan.trialDays > 0) || plan.code === 'free') return null;
  const used = await ownerTrialEnd(userId);
  if (used) return used > now ? { planCode: plan.code, endsAt: used } : null;
  const endsAt = new Date(now.getTime() + plan.trialDays * DAY);
  await User.updateOne({ _id: userId }, { trialEndsAt: endsAt });
  return { planCode: plan.code, endsAt };
}

/** When this person's own trial ends (or ended). Older accounts: the latest trial on a business they own. */
async function ownerTrialEnd(userId: Types.ObjectId): Promise<Date | null> {
  const user = await User.findById(userId).select('trialEndsAt').lean();
  if (user?.trialEndsAt) return user.trialEndsAt;
  const owned = await Company.find({ ownerUserId: userId }).select('_id').lean();
  if (!owned.length) return null;
  const sub = await Subscription.findOne({ companyId: { $in: owned.map((c) => c._id) }, trialEndsAt: { $ne: null } })
    .sort({ trialEndsAt: -1 })
    .setOptions({ skipTenant: true })
    .lean();
  return sub?.trialEndsAt ?? null;
}

const featureList = (keys: string[], lang: 'en' | 'hi') => {
  const names = keys.filter((k) => FEATURE_LABELS[k] && k !== 'priority_support').map((k) => FEATURE_LABELS[k][lang]);
  if (names.length < 2) return names.join('');
  return `${names.slice(0, -1).join(', ')} ${lang === 'hi' ? 'और' : 'and'} ${names[names.length - 1]}`;
};

/**
 * Daily trial messages for one business (from the scheduler): 3 days and 1 day
 * before the end, then once when it ends. Returns the jobState key it handled.
 */
export async function trialNotices(company: any, now = new Date()): Promise<string | null> {
  if (company.billedTo) return null; // the payer's trial; the payer gets the messages
  const sub = await Subscription.findOne({ companyId: company._id }).sort({ createdAt: -1 }).lean();
  const trial = await trialFromSubscription(sub, now);
  if (!trial) return null;
  const local = DateTime.fromJSDate(now).setZone(company.timezone ?? 'Asia/Kolkata');
  if (local.hour < 10 || local.hour >= 20) return null; // daytime only
  const reminderDays = (await getConfig<number[]>('trial.reminderDays')) ?? [3, 1];
  const stage = trial.ended ? 'ended' : reminderDays.includes(trial.daysLeft) ? String(trial.daysLeft) : null;
  if (!stage) return null;
  const key = `${trial.endsAt.toISOString()}|${stage}`;
  if (company.jobState?.lastTrialNotice === key) return null;
  // Only the last reminder before the end is sent if the server missed earlier ones.
  if (stage !== 'ended' && company.jobState?.lastTrialNotice?.startsWith(`${trial.endsAt.toISOString()}|`)) {
    const sent = company.jobState.lastTrialNotice.split('|')[1];
    if (sent === 'ended' || Number(sent) <= trial.daysLeft) return null;
  }

  const name = company.name as string;
  const endDate = DateTime.fromJSDate(trial.endsAt).setZone(company.timezone ?? 'Asia/Kolkata');
  const dateEn = endDate.setLocale('en-IN').toFormat('d LLL');
  const dateHi = endDate.setLocale('hi').toFormat('d LLL');
  const stopsEn = featureList(trial.paidFeatures, 'en');
  const stopsHi = featureList(trial.paidFeatures, 'hi');
  const owner = await User.findOne({ _id: company.ownerUserId, deletedAt: null }).lean();

  if (stage === 'ended') {
    // Face check is not on Free: turn it off so settings and staff rules say what really happens.
    const { plan } = await companyPlan(company, now);
    if (!plan.features.includes('face_match') && company.settings?.faceMatchPolicy === 'review') {
      await Company.updateOne({ _id: company._id }, { 'settings.faceMatchPolicy': 'off' });
    }
    await notifyOwners(
      company._id,
      {
        template: 'trial_ended',
        title: `${name}: free trial ended`,
        titleHi: `${name}: फ़्री ट्रायल ख़त्म`,
        body: `You are on the Free plan now. Attendance, leave and the daily summary keep working, and all your data is safe. ${stopsEn ? `Paused until you pick a plan: ${stopsEn}.` : ''}`.trim(),
        bodyHi: `अब आप Free प्लान पर हैं। हाज़िरी, छुट्टी और रोज़ की रिपोर्ट चलती रहेगी, आपका सारा डेटा सुरक्षित है। ${stopsHi ? `प्लान लेने तक रुका रहेगा: ${stopsHi}।` : ''}`.trim(),
        data: { type: 'trial_ended' },
      },
      { includeManagers: false },
    );
    if (owner) await sendWhatsApp(company._id, owner.phone, { template: 'trial_ended', params: [name] }, { userId: owner._id, language: owner.language as any });
  } else {
    const days = trial.daysLeft;
    await notifyOwners(
      company._id,
      {
        template: 'trial_reminder',
        title: days === 1 ? `${name}: free trial ends tomorrow` : `${name}: ${days} days of free trial left`,
        titleHi: days === 1 ? `${name}: फ़्री ट्रायल कल ख़त्म` : `${name}: फ़्री ट्रायल के ${days} दिन बाक़ी`,
        body: `Your ${trial.planName} trial ends on ${dateEn}. Pick a plan to keep ${stopsEn || 'all features'}. If you don't, you move to Free and keep your data.`,
        bodyHi: `आपका ${trial.planName} ट्रायल ${dateHi} को ख़त्म होगा। ${stopsHi || 'सब फ़ीचर'} चालू रखने के लिए प्लान चुनें। न चुनें तो आप Free पर आ जाएँगे, डेटा सुरक्षित रहेगा।`,
        data: { type: 'trial_reminder', daysLeft: String(days) },
      },
      { includeManagers: false },
    );
    if (owner) await sendWhatsApp(company._id, owner.phone, { template: 'trial_reminder', params: [name, String(days), dateEn] }, { userId: owner._id, language: owner.language as any });
  }
  return key;
}

/**
 * Support/testing: a fresh trial for one business, or for every business a phone owns.
 * days=0 ends the trial now (to see the "trial ended" state).
 */
export async function grantTrial(input: { companyId?: string; phone?: string; days: number; planCode: string }, now = new Date()) {
  const plan = await getPlan(input.planCode);
  if (plan.code !== input.planCode || plan.code === 'free') throw new AppError('VALIDATION_ERROR', `Unknown paid plan: ${input.planCode}`);
  let companies: any[];
  if (input.companyId) {
    if (!Types.ObjectId.isValid(input.companyId)) throw notFound('Company');
    companies = await Company.find({ _id: input.companyId, deletedAt: null }).lean();
  } else {
    const user = await User.findOne({ phone: normalizePhone(input.phone!) }).lean();
    companies = user ? await Company.find({ ownerUserId: user._id, deletedAt: null }).lean() : [];
  }
  if (!companies.length) throw notFound('Company');
  const endsAt = new Date(now.getTime() + input.days * DAY);
  const out = [];
  for (const c of companies) {
    const paid = await Subscription.findOne({ companyId: c._id, status: { $in: ['active', 'past_due'] }, $or: [{ currentPeriodEnd: null }, { currentPeriodEnd: { $gt: now } }] }).lean();
    if (paid) {
      out.push({ companyId: String(c._id), name: c.name, skipped: 'paid_plan' as const });
      continue;
    }
    await Subscription.updateMany({ companyId: c._id, status: { $in: ['trialing', 'free', 'pending'] } }, { status: 'cancelled', cancelledAt: now });
    await Subscription.create({ companyId: c._id, provider: 'internal', planCode: plan.code, status: 'trialing', trialEndsAt: endsAt, currency: c.currency ?? 'INR' });
    await Company.updateOne({ _id: c._id }, { $unset: { 'jobState.lastTrialNotice': '' } });
    out.push({ companyId: String(c._id), name: c.name, planCode: plan.code, trialEndsAt: endsAt });
  }
  return out;
}
