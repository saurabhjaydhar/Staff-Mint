import { describe, expect, it } from 'vitest';
import { Types } from 'mongoose';
import { api, auth, V, createOwner, addEmployee, employeeSession, nextPhone, mocks, setPlan } from './helpers.js';
import { Advance, Attendance, Payslip } from '../src/models/index.js';
import { monthDays, weekdayOf } from '../src/lib/dates.js';

async function fillMonth(companyId: string, employeeId: string, month: string, absent: string[] = []) {
  for (const d of monthDays(month)) {
    const status = weekdayOf(d) === 0 ? 'week_off' : absent.includes(d) ? 'absent' : 'present';
    await Attendance.create({ companyId, employeeId, date: d, status });
  }
}

describe('payroll lifecycle', () => {
  it('draft → approve → revise → send, with advances, bonus, PDFs and employee view', async () => {
    const { messaging } = await mocks();
    const owner = await createOwner({ plan: 'growth' });
    const phone = nextPhone();
    const emp = await addEmployee(owner, { phone, name: 'Pooja Singh', ratePaise: 3000000, joiningDate: '2026-01-01' });
    // September 2026: 30 days, Sundays 6/13/20/27. Two absences → 28 payable of 30 → ₹28,000.
    await fillMonth(owner.companyId, emp.id, '2026-09', ['2026-09-08', '2026-09-09']);
    await api().post(`${V}/advances`).set(auth(owner.token)).send({ employeeId: emp.id, amountPaise: 500000, date: '2026-09-10', mode: 'full_next' }).expect(201);
    await api().post(`${V}/adjustments`).set(auth(owner.token)).send({ employeeId: emp.id, month: '2026-09', type: 'bonus', amountPaise: 100000, note: 'Festival' }).expect(201);

    const draft = await api().post(`${V}/payroll/runs`).set(auth(owner.token)).send({ month: '2026-09' });
    expect(draft.status).toBe(200);
    expect(draft.body.data).toMatchObject({ status: 'draft', revision: 1, totals: { grossPaise: 2900000, deductionsPaise: 500000, netPaise: 2400000, employees: 1 } });
    const slip = draft.body.data.payslips[0];
    expect(slip).toMatchObject({ payableDays: 28, divisor: 30, netPaise: 2400000 });
    expect(slip.lines.map((l: any) => l.code)).toEqual(['basic', 'bonus', 'advance']);
    expect(slip.lines[0].explanation).toContain('÷ 30 × 28');

    // Recompute picks up changes while still draft
    await api().post(`${V}/attendance/override`).set(auth(owner.token)).send({ employeeId: emp.id, date: '2026-09-08', status: 'present', reason: 'Was on delivery duty' }).expect(200);
    const re = await api().post(`${V}/payroll/runs/${draft.body.data.id}/recompute`).set(auth(owner.token));
    expect(re.body.data.totals.netPaise).toBe(2500000);

    const approved = await api().post(`${V}/payroll/runs/${draft.body.data.id}/approve`).set(auth(owner.token));
    expect(approved.body.data.status).toBe('approved');
    expect(approved.body.data.payslips[0].status).toBe('final');
    expect(approved.body.data.payslips[0].pdfUrl).toMatch(/\/files\/payslips\//);
    const adv = await Advance.findOne({ companyId: owner.companyId }).lean();
    expect(adv).toMatchObject({ status: 'closed' });
    expect(adv!.repayments).toHaveLength(1);

    // Locked month
    expect((await api().post(`${V}/adjustments`).set(auth(owner.token)).send({ employeeId: emp.id, month: '2026-09', type: 'bonus', amountPaise: 100 })).status).toBe(409);
    expect((await api().post(`${V}/payroll/runs`).set(auth(owner.token)).send({ month: '2026-09' })).status).toBe(409);

    // Send payslips → app push + WhatsApp document (Growth plan)
    const sent = await api().post(`${V}/payslips/send`).set(auth(owner.token)).send({ runId: draft.body.data.id });
    expect(sent.body.data).toEqual({ queued: 1, viaWhatsApp: true });
    const wa = messaging.outbox.find((m) => m.template === 'payslip_ready');
    expect(wa?.to).toBe(`+91${phone}`);
    expect(wa?.url).toContain('/files/payslips/');
    // Immutable after sending
    await expect(Payslip.updateOne({ companyId: owner.companyId, _id: approved.body.data.payslips[0].id }, { $set: { netPaise: 1 } })).rejects.toThrow(/immutable/);

    // Revision: correction creates rev 2; approving it supersedes rev 1 and replaces (not doubles) advance recovery
    const corr = await api().post(`${V}/attendance/override`).set(auth(owner.token)).send({ employeeId: emp.id, date: '2026-09-09', status: 'present', reason: 'Correction' }).expect(200);
    const rev = await api().post(`${V}/payroll/runs/${draft.body.data.id}/revise`).set(auth(owner.token));
    expect(rev.body.data).toMatchObject({ revision: 2, status: 'draft' });
    expect(rev.body.data.totals.netPaise).toBe(2600000);
    void corr;
    // The correction draft reopens the month for bonus/deduction
    const adj = await api().post(`${V}/adjustments`).set(auth(owner.token)).send({ employeeId: emp.id, month: '2026-09', type: 'deduction', amountPaise: 10000, note: 'Correction' });
    expect(adj.status).toBe(201);
    await api().delete(`${V}/adjustments/${adj.body.data.id}`).set(auth(owner.token)).expect(200);
    await api().post(`${V}/payroll/runs/${rev.body.data.id}/approve`).set(auth(owner.token)).expect(200);
    const runs = await api().get(`${V}/payroll/runs?month=2026-09`).set(auth(owner.token));
    expect(runs.body.data.map((r: any) => [r.revision, r.status])).toEqual([
      [2, 'approved'],
      [1, 'superseded'],
    ]);
    const adv2 = await Advance.findOne({ companyId: owner.companyId }).lean();
    expect(adv2!.repayments).toHaveLength(1);
    await api().post(`${V}/payroll/runs/${rev.body.data.id}/mark-paid`).set(auth(owner.token)).expect(200);

    // Employee sees only the latest revision, with explanation
    const e = await employeeSession(phone);
    const mine = await api().get(`${V}/payslips`).set(auth(e.token));
    expect(mine.body.data).toHaveLength(1);
    expect(mine.body.data[0]).toMatchObject({ revision: 2, netPaise: 2600000 });
    const ex = await api().get(`${V}/payslips/${mine.body.data[0].id}/explain`).set(auth(e.token)).set('Accept-Language', 'hi');
    expect(ex.body.data.text).toContain('हाथ में वेतन');
    const other = await addEmployee(owner, { name: 'Other' });
    const otherSlips = await api().get(`${V}/payslips?employeeId=${other.id}`).set(auth(e.token));
    expect(otherSlips.body.data.every((s: any) => s.employeeId === e.user.employeeId)).toBe(true);
    const sal = await api().get(`${V}/me/salary`).set(auth(e.token));
    expect(sal.body.data.estimate).toBeTruthy();
    expect(sal.body.data.payslips).toHaveLength(1);
  });

  it('parallel-run compare explains differences against the old app report', async () => {
    const owner = await createOwner();
    const emp = await addEmployee(owner, { name: 'Ramesh Kumar', ratePaise: 3000000, joiningDate: '2026-01-01' });
    await fillMonth(owner.companyId, emp.id, '2026-09', ['2026-09-08', '2026-09-09']);
    const run = await api().post(`${V}/payroll/runs`).set(auth(owner.token)).send({ month: '2026-09' });
    // Old app divided by 26 working days: 30000/26 × 24 = 27692
    const csv = 'Staff Name,Paid Days,Gross Salary,Net Salary\nRamesh Kumar,24,27692,27692\nGhost Worker,26,10000,10000\n';
    const r = await api().post(`${V}/payroll/runs/${run.body.data.id}/compare`).set(auth(owner.token)).attach('file', Buffer.from(csv), 'old.csv');
    expect(r.status).toBe(200);
    const row = r.body.data.rows.find((x: any) => x.employeeName === 'Ramesh Kumar');
    expect(row.diffPaise).toBe(2800000 - 2769200);
    expect(row.reasons.join(' ')).toMatch(/Payable days differ/);
    expect(r.body.data.rows.find((x: any) => x.employeeName === 'Ghost Worker').reasons[0]).toMatch(/Not found/);
  });

  it('payroll is gated by plan and cannot run for future months', async () => {
    const owner = await createOwner({ plan: 'free' });
    const r = await api().post(`${V}/payroll/runs`).set(auth(owner.token)).send({ month: '2026-09' });
    expect(r.status).toBe(402);
    expect(r.body.error.code).toBe('FEATURE_NOT_IN_PLAN');
    await setPlan(owner.companyId, 'starter');
    expect((await api().post(`${V}/payroll/runs`).set(auth(owner.token)).send({ month: '2099-01' })).status).toBe(400);
  });

  it('enforces plan staff limits', async () => {
    const owner = await createOwner({ plan: 'free' });
    for (let i = 0; i < 5; i++) await addEmployee(owner, { name: `S${i}` });
    const r = await api().post(`${V}/employees`).set(auth(owner.token)).send({ name: 'Sixth', phone: nextPhone() });
    expect(r.status).toBe(402);
    expect(r.body.error.code).toBe('PLAN_LIMIT');
    void Types;
  });
  it('anomaly flags follow the reader\'s language, not the language used to compute', async () => {
    const owner = await createOwner({ plan: 'growth' });
    const emp = await addEmployee(owner, { phone: nextPhone(), name: 'Suresh Yadav', ratePaise: 1400000, joiningDate: '2026-01-01' });
    // Only the first 20 days are marked, so the rest of September (bar weekly offs) is unmarked.
    for (const d of monthDays('2026-09').slice(0, 20)) await Attendance.create({ companyId: owner.companyId, employeeId: emp.id, date: d, status: 'present' });
    const hi = await api().post(`${V}/payroll/runs`).set(auth(owner.token)).set('Accept-Language', 'hi').send({ month: '2026-09' }).expect(200);
    const flag = (r: any) => r.body.data.anomalies.find((a: any) => a.code === 'unmarked_days')?.message;
    expect(flag(hi)).toMatch(/^\d+ दिन की हाज़िरी नहीं लगी$/);
    const en = await api().get(`${V}/payroll/runs/${hi.body.data.id}`).set(auth(owner.token)).set('Accept-Language', 'en').expect(200);
    expect(flag(en)).toMatch(/^\d+ day\(s\) have no attendance$/);
  });
});
