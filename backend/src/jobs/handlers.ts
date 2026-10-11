import { Types } from 'mongoose';
import { DateTime } from 'luxon';
import { Attendance, Company } from '../models/index.js';
import { logger } from '../lib/logger.js';
import { previousMonth, todayIn, addDays } from '../lib/dates.js';
import { closeDay, dashboardToday } from '../modules/attendance/service.js';
import { autoDraftForCompany } from '../modules/payroll/service.js';
import { generateRunPdfs } from '../modules/payslips/service.js';
import { notifyOwners } from '../modules/notifications/service.js';
import { trialNotices } from '../modules/billing/trial.js';
import { provider } from '../providers/registry.js';
import { systemCtx } from '../lib/context.js';

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
  const en = `${c.present}/${c.total} present, ${c.late} late, ${c.onLeave} on leave, ${c.notMarked} not marked.${pending ? ` ${pending} need your action.` : ''}`;
  const hi = `${c.total} में से ${c.present} हाज़िर, ${c.late} लेट, ${c.onLeave} छुट्टी पर, ${c.notMarked} की हाज़िरी नहीं लगी।${pending ? ` ${pending} काम आपकी मंज़ूरी के लिए।` : ''}`;
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
  return removed;
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
