import { describe, expect, it } from 'vitest';
import { api, auth, V, createOwner, addEmployee, employeeSession, nextPhone } from './helpers.js';
import { Attendance, Notification, Payslip } from '../src/models/index.js';
import { monthDays } from '../src/lib/dates.js';
import { payslipHtml } from '../src/modules/payslips/templates.js';
import { buildReport } from '../src/modules/reports/service.js';
import { systemCtx } from '../src/lib/context.js';

/** September 2026, present every day (30 payable of 30). */
async function fullMonth(companyId: string, employeeId: string) {
  for (const d of monthDays('2026-09')) await Attendance.create({ companyId, employeeId, date: d, status: 'present' });
}

describe('salary slips', () => {
  it('small shop: formal slip with Gross, Deductions, Net in words, and "Paid on … by …" after marking paid', async () => {
    const owner = await createOwner({ plan: 'growth', setup: { name: 'Sharma Medical Store' } });
    const phone = nextPhone();
    const emp = await addEmployee(owner, { phone, name: 'Pooja Singh', ratePaise: 1200000, designation: 'Cashier', joiningDate: '2026-01-05' });
    await employeeSession(phone); // Pooja uses the app, so she gets the "salary paid" message
    await fullMonth(owner.companyId, emp.id);
    await api().post(`${V}/advances`).set(auth(owner.token)).send({ employeeId: emp.id, amountPaise: 200000, date: '2026-09-09', mode: 'full_next' }).expect(201);
    await api().patch(`${V}/employees/${emp.id}/statutory`).set(auth(owner.token)).send({ employeeCode: 'SM-014' }).expect(200);
    const draft = await api().post(`${V}/payroll/runs`).set(auth(owner.token)).send({ month: '2026-09' }).expect(200);
    const runId = draft.body.data.id;
    await api().post(`${V}/payroll/runs/${runId}/approve`).set(auth(owner.token)).expect(200);

    let slip = await Payslip.findOne({ companyId: owner.companyId, runId }).lean();
    expect(slip!.lines.map((l) => l.code)).toEqual(['basic', 'advance']);
    expect(slip!.employerContributions).toEqual([]);
    expect(slip!.employeeInfo).toMatchObject({ code: 'SM-014', designation: 'Cashier', joiningDate: '2026-01-05', language: 'hi' });
    let html = payslipHtml(slip, { name: 'Sharma Medical Store', currency: 'INR' });
    expect(html).toContain('सैलरी स्लिप');
    expect(html).toContain('Salary Slip');
    expect(html).toContain('कुल कमाई'); // Gross earnings
    expect(html).toContain('कुल कटौती'); // Total deductions
    expect(html).toContain('दस हज़ार रुपये'); // ₹10,000 in words
    expect(html).toContain('अभी भुगतान नहीं हुआ'); // not paid yet
    expect(html).not.toContain('PF UAN');
    expect(html).not.toContain('मालिक द्वारा जमा'); // no employer box

    // Mark paid by UPI on 3 Oct: run, slip and PDF show it; staff are told.
    const paid = await api().post(`${V}/payroll/runs/${runId}/mark-paid`).set(auth(owner.token)).send({ paidOn: '2026-10-03', method: 'upi' }).expect(200);
    expect(paid.body.data).toMatchObject({ status: 'paid', paidOn: '2026-10-03', paymentMethod: 'upi' });
    expect(paid.body.data.payslips[0]).toMatchObject({ paidOn: '2026-10-03', paymentMethod: 'upi' });
    slip = await Payslip.findOne({ companyId: owner.companyId, runId }).lean();
    html = payslipHtml(slip, { name: 'Sharma Medical Store', currency: 'INR' });
    expect(html).toContain('भुगतान हो गया');
    expect(html).toContain('3 अक्टूबर 2026');
    const told = await Notification.findOne({ companyId: owner.companyId, template: 'salary_paid', channel: 'in_app' }).lean();
    expect(told!.body).toMatch(/₹10,000.*2026-10-03.*UPI/);
    // A bad method is refused.
    expect((await api().post(`${V}/payroll/runs/${runId}/mark-paid`).set(auth(owner.token)).send({ method: 'cheque' })).status).toBe(400);
  });

  it('shop with PF, ESI and PT: Basic/HRA, statutory lines, employer box, UAN/ESIC/PAN masked', async () => {
    const owner = await createOwner({ plan: 'pro', setup: { name: 'Gupta Sweets' } });
    const emp = await addEmployee(owner, { phone: nextPhone(), name: 'Ramesh Kumar', ratePaise: 2000000 });
    await api().patch(`${V}/employees/${emp.id}`).set(auth(owner.token)).send({ language: 'en' }).expect(200);
    await fullMonth(owner.companyId, emp.id);

    // Settings: PF + ESI + PT ₹200; staff details. Bad numbers are refused with a reason.
    const st = await api()
      .patch(`${V}/company/statutory`)
      .set(auth(owner.token))
      .send({ pfEnabled: true, pfNumber: 'dlcpm1234567000', esiEnabled: true, esiNumber: '12345678901234567', ptEnabled: true, ptState: 'Maharashtra', ptMonthlyPaise: 20000 })
      .expect(200);
    expect(st.body.data).toMatchObject({ pfEnabled: true, pfNumber: 'DLCPM1234567000', basicPercent: 50, pfRatePercent: 12, esiEmployeePercent: 0.75, ptState: 'Maharashtra' });
    expect((await api().patch(`${V}/employees/${emp.id}/statutory`).set(auth(owner.token)).send({ uan: '123' })).body.error.message).toMatch(/12 digits/);
    expect((await api().patch(`${V}/employees/${emp.id}/statutory`).set(auth(owner.token)).send({ pan: 'abc' })).body.error.message).toMatch(/PAN/);
    const det = await api().patch(`${V}/employees/${emp.id}/statutory`).set(auth(owner.token)).send({ uan: '1001 2345 6789', esicNumber: '3112345678', pan: 'abcde1234f' }).expect(200);
    expect(det.body.data).toEqual({ employeeCode: null, uan: '100123456789', esicNumber: '3112345678', panMasked: 'ABXXXXX34F', pfExempt: false, esiExempt: false });
    const view = await api().get(`${V}/employees/${emp.id}`).set(auth(owner.token)).expect(200);
    expect(view.body.data.statutory.panMasked).toBe('ABXXXXX34F');
    expect(JSON.stringify(view.body.data)).not.toContain('ABCDE1234F');

    const draft = await api().post(`${V}/payroll/runs`).set(auth(owner.token)).send({ month: '2026-09' }).expect(200);
    const slipView = draft.body.data.payslips[0];
    // ₹20,000: Basic 10,000 + HRA 10,000; PF 1,200; ESI 150; PT 200 → net 18,450.
    expect(slipView.lines.map((l: any) => [l.code, l.amountPaise])).toEqual([
      ['basic', 1000000],
      ['allowance', 1000000],
      ['pf', 120000],
      ['esi', 15000],
      ['pt', 20000],
    ]);
    expect(slipView.netPaise).toBe(1845000);
    expect(slipView.employerContributions.map((c: any) => [c.code, c.amountPaise])).toEqual([
      ['pf', 120000],
      ['esi', 65000],
    ]);

    await api().post(`${V}/payroll/runs/${draft.body.data.id}/approve`).set(auth(owner.token)).expect(200);
    const slip = await Payslip.findOne({ companyId: owner.companyId, runId: draft.body.data.id }).lean();
    const html = payslipHtml(slip, { name: 'Gupta Sweets', currency: 'INR', pfNumber: 'DLCPM1234567000', esiNumber: '12345678901234567' });
    for (const text of ['Salary Slip', 'Gross earnings', 'Total deductions', 'Provident Fund (PF)', 'ESI', 'Professional Tax', 'HRA &amp; allowances', '100123456789', '3112345678', 'ABXXXXX34F', 'Paid by the employer on top of salary', 'Employer PF', 'Rupees Eighteen Thousand Four Hundred Fifty Only', 'PF: DLCPM1234567000']) {
      expect(html).toContain(text);
    }
    expect(html).not.toContain('ABCDE1234F');

    // Salary register gets PF / ESI / Prof. tax columns only because this shop uses them.
    const reg = await buildReport(systemCtx(owner.companyId), 'salary', '2026-09');
    expect(reg.headers).toEqual(['Name', 'Type', 'Rate', 'Paid days', 'Earned', 'Bonus', 'Gross', 'PF', 'ESI', 'Prof. tax', 'Deductions', 'Advance', 'Net pay']);
    expect(reg.rows[0].slice(4, 10)).toEqual(['₹20,000', '₹0', '₹20,000', '₹1,200', '₹150', '₹200']);

    // Staff outside PF/ESI: next month's draft has neither.
    await api().patch(`${V}/employees/${emp.id}/statutory`).set(auth(owner.token)).send({ pfExempt: true, esiExempt: true }).expect(200);
    for (const d of monthDays('2026-10')) await Attendance.create({ companyId: owner.companyId, employeeId: emp.id, date: d, status: 'present' });
    const oct = await api().post(`${V}/payroll/runs`).set(auth(owner.token)).send({ month: '2026-10' }).expect(200);
    expect(oct.body.data.payslips[0].lines.map((l: any) => l.code)).toEqual(['basic', 'pt']);
  });

  it('only the owner changes statutory settings; staff details are owner-only too', async () => {
    const owner = await createOwner({ plan: 'pro' });
    const emp = await addEmployee(owner, { phone: nextPhone() });
    const strict = await api().patch(`${V}/company/statutory`).set(auth(owner.token)).send({ pfRatePercent: 50 });
    expect(strict.status).toBe(400); // rates are not owner-editable here
    const other = await createOwner({ plan: 'pro' });
    expect((await api().patch(`${V}/employees/${emp.id}/statutory`).set(auth(other.token)).send({ uan: '100123456789' })).status).toBe(404);
  });
});
