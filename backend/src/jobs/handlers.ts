import { Types } from 'mongoose';
import { DateTime } from 'luxon';
import { Attendance, Company, Employee, RosterRepeat } from '../models/index.js';
import { purgeDocuments, remindExpiring } from '../modules/verification/documents.js';
import { purgeVerification } from '../modules/verification/service.js';
import { trackingTick, travelSummary } from '../modules/tracking/service.js';
import { getConfig } from '../modules/config/service.js';
import { logger } from '../lib/logger.js';
import { previousMonth, todayIn, addDays } from '../lib/dates.js';
import { closeDay, dashboardToday } from '../modules/attendance/service.js';
import { autoDraftForCompany } from '../modules/payroll/service.js';
import { generateRunPdfs } from '../modules/payslips/service.js';
import { notifyOwners } from '../modules/notifications/service.js';
import { trialNotices } from '../modules/billing/trial.js';
import { provider } from '../providers/registry.js';
import { systemCtx } from '../lib/context.js';
import { canRepeat, fillWeek } from '../modules/roster/repeat.js';
import { sendWeek, weekView } from '../modules/roster/service.js';

export type JobName = 'payslips.pdf' | 'scheduler.tick' | 'attendance.closeDay' | 'digest.send';

export const handlers: Record<JobName, (data: any) => Promise<unknown>> = {
  'payslips.pdf': async ({ companyId, runId }) => generateRunPdfs(new Types.ObjectId(companyId), new Types.ObjectId(runId)),
  'attendance.closeDay': async ({ companyId, date }) => closeDay(new Types.ObjectId(companyId), date),
  'digest.send': async ({ companyId }) => sendDigest(new Types.ObjectId(companyId)),
  'scheduler.tick': async ({ now } = {}) => schedulerTick(now ? new Date(now) : new Date()),
};

/** 9:30 AM owner digest (PRD §10 #2): "15/18 present, 2 late, 1 leave". */
export async function sendDigest(companyId: Types.ObjectId) {
  const d = await dashboardToday(systemCtx(companyId));
  const c = d.counts;
  const pending = d.needsAction.leaveRequests.length + d.needsAction.punchApprovals.length;
  // Field staff: yesterday's travel, a few names at most.
  const travel = (await travelSummary(companyId, addDays(d.date, -1))).filter((t) => t.km > 0).slice(0, 3);
  const travelEn = travel.length ? ` Yesterday: ${travel.map((t) => `${t.name} ${t.km} km, ${t.stops} ${t.stops === 1 ? 'stop' : 'stops'}`).join('; ')}.` : '';
  const travelHi = travel.length ? ` कल: ${travel.map((t) => `${t.name} ${t.km} किमी, ${t.stops} रुकाव`).join('; ')}।` : '';
  const en = `${c.present}/${c.total} present, ${c.late} late, ${c.onLeave} on leave, ${c.notMarked} not marked.${pending ? ` ${pending} need your action.` : ''}${travelEn}`;
  const hi = `${c.total} में से ${c.present} हाज़िर, ${c.late} लेट, ${c.onLeave} छुट्टी पर, ${c.notMarked} की हाज़िरी नहीं लगी।${pending ? ` ${pending} काम आपकी मंज़ूरी के लिए।` : ''}${travelHi}`;
  await notifyOwners(
    companyId,
    {
      template: 'daily_digest',
      title: 'Today at a glance',
      titleHi: 'आज की हाज़िरी',
      body: en,
      bodyHi: hi,
      data: { type: 'digest', date: d.date },
      whatsapp: { template: 'daily_digest', params: [String(c.present), String(c.total), String(c.late), String(c.onLeave), String(pending)] },
    },
    { includeManagers: false },
  );
  return c;
}

/** Remove selfies and precise locations past their retention (PRD §13, §19). */
export async function purgeRetention(company: any, now: Date) {
  const storage = await provider('storage');
  const selfieCutoff = DateTime.fromJSDate(now).minus({ days: company.settings?.selfieRetentionDays ?? 90 }).toISODate()!;
  const old = await Attendance.find({ companyId: company._id, date: { $lt: selfieCutoff }, 'punches.selfieKey': { $ne: null } }).limit(500);
  let removed = 0;
  for (const r of old) {
    for (const p of r.punches as any[]) {
      if (p.selfieKey) {
        await storage.delete(p.selfieKey).catch(() => undefined);
        p.selfieKey = null;
        removed++;
      }
    }
    await r.save();
  }
  const geoCutoff = DateTime.fromJSDate(now).minus({ months: company.settings?.locationRetentionMonths ?? 12 }).toISODate()!;
  await Attendance.updateMany({ companyId: company._id, date: { $lt: geoCutoff }, 'punches.geo.lat': { $exists: true } }, { $unset: { 'punches.$[].geo': '' } });
  // Background checks and documents: gone 180 days after the person leaves (DPDP).
  const leftBefore = DateTime.fromJSDate(now).minus({ days: await getConfig<number>('verification.retentionDays', company._id) }).toISODate()!;
  const leftIds = (await Employee.find({ companyId: company._id, exitDate: { $ne: null, $lt: leftBefore } }).select('_id').lean()).map((e) => e._id);
  await purgeDocuments(company._id, leftIds);
  const gone = await Employee.find({ companyId: company._id, exitDate: { $ne: null, $lt: leftBefore }, 'verification.status': { $ne: 'none' } }).select('_id').lean();
  if (gone.length) {
    const ids = gone.map((e) => e._id);
    await purgeVerification(company._id, ids);
    await Employee.updateMany({ companyId: company._id, _id: { $in: ids } }, { $set: { verification: { status: 'none', at: now } } });
  }
  return removed;
}

/**
 * Thursday from 10 AM (company time): fill next week from "Repeat every week", then send it to staff when
 * the owner chose that, or remind owners to check and send. Returns the week handled (stored in jobState).
 */
export async function prepareNextRosterWeek(c: any, local: DateTime, lastWeek?: string) {
  if (local.weekday < 4 || (local.weekday === 4 && local.hour < 10)) return null;
  const next = local.startOf('week').plus({ weeks: 1 }).toISODate()!;
  if (lastWeek && lastWeek >= next) return null;
  if (!(await RosterRepeat.exists({ companyId: c._id }))) return null;
  if (!(await canRepeat(c._id))) return next;
  const ctx = systemCtx(c._id, c.settings?.language === 'en' ? 'en' : 'hi');
  await fillWeek(ctx, next);
  const autoSend = await RosterRepeat.exists({ companyId: c._id, autoSend: true });
  if (autoSend) {
    await sendWeek(ctx, next);
    return next;
  }
  const { notSent } = await weekView(ctx, next);
  if (!notSent) return next;
  const label = DateTime.fromISO(next).toFormat('d LLL');
  const labelHi = DateTime.fromISO(next).setLocale('hi').toFormat('d LLLL');
  await notifyOwners(c._id, {
    template: 'roster_ready',
    title: `Next week's roster is ready (from ${label})`,
    titleHi: `अगले हफ़्ते का रोस्टर तैयार है (${labelHi} से)`,
    body: 'It was filled in from "Repeat every week". Check it and send it to staff.',
    bodyHi: '"हर हफ़्ते दोहराएँ" से भरा गया है। देखकर स्टाफ़ को भेजें।',
    data: { type: 'roster', weekStart: next },
  });
  return next;
}

/** Runs every few minutes; decides per company (in its own timezone) what is due. Idempotent via company.jobState. */
export async function schedulerTick(now = new Date()) {
  const companies = await Company.find({ deletedAt: null }).lean();
  const summary = { companies: companies.length, closed: 0, digests: 0, drafts: 0 };
  for (const c of companies) {
    try {
      const local = DateTime.fromJSDate(now).setZone(c.timezone);
      const today = todayIn(c.timezone, now);
      const state: any = c.jobState ?? {};
      const hhmm = local.toFormat('HH:mm');
      const updates: Record<string, string> = {};

      // Nightly auto-absent at 11:59 PM (catch up yesterday if the server was down).
      const yesterday = addDays(today, -1);
      if (!state.lastAutoAbsentDate || state.lastAutoAbsentDate < yesterday) {
        await closeDay(c._id, yesterday);
        updates['jobState.lastAutoAbsentDate'] = yesterday;
        summary.closed++;
      }
      if (hhmm >= '23:59' && (updates['jobState.lastAutoAbsentDate'] ?? state.lastAutoAbsentDate) !== today) {
        await closeDay(c._id, today);
        updates['jobState.lastAutoAbsentDate'] = today;
        summary.closed++;
      }

      // Daily digest.
      const digestAt = c.settings?.digestTime ?? '09:30';
      if (hhmm >= digestAt && hhmm < '23:00' && state.lastDigestDate !== today) {
        await sendDigest(c._id);
        updates['jobState.lastDigestDate'] = today;
        summary.digests++;
      }

      // Payroll draft on the 1st for last month.
      const lastMonth = previousMonth(today.slice(0, 7));
      if (local.hour >= 6 && state.lastDraftMonth !== lastMonth) {
        const signedUpBefore = c.createdAt && todayIn(c.timezone, c.createdAt) < `${today.slice(0, 7)}-01`;
        const run = signedUpBefore ? await autoDraftForCompany(c._id, lastMonth) : null;
        updates['jobState.lastDraftMonth'] = lastMonth;
        if (run) summary.drafts++;
      }

      // Free trial: reminders 3 days and 1 day before it ends, then "trial ended".
      const trialKey = await trialNotices(c, now);
      if (trialKey) updates['jobState.lastTrialNotice'] = trialKey;

      // Roster "Repeat every week": on Thursday morning fill next week, then send it or remind the owner.
      const rosterWeek = await prepareNextRosterWeek(c, local, state.lastRosterWeek);
      if (rosterWeek) updates['jobState.lastRosterWeek'] = rosterWeek;

      // Documents running out within 30 days: remind once a day from 10 AM.
      if (local.hour >= 10 && state.lastDocExpiryDate !== today) {
        await remindExpiring(c, now);
        updates['jobState.lastDocExpiryDate'] = today;
      }

      // Field staff location: close sessions past shift end, tell owners when someone stopped updating.
      await trackingTick(c, now);

      // Retention purge at ~3 AM.
      if (local.hour === 3 && local.minute < 15) await purgeRetention(c, now);

      if (Object.keys(updates).length) await Company.updateOne({ _id: c._id }, { $set: updates });
    } catch (err) {
      logger.error({ err, companyId: String(c._id) }, 'scheduler tick failed for company');
    }
  }
  // Support recoveries whose 7-day hold ran out with nobody stopping them.
  try {
    const { completeRecoveries } = await import('../modules/accounts/identity.js');
    await completeRecoveries(now);
  } catch (err) {
    logger.error({ err }, 'recovery completion failed');
  }
  return summary;
}
