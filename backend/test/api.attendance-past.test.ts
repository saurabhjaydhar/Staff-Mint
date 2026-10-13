import { describe, expect, it } from 'vitest';
import { api, auth, V, createOwner, addEmployee } from './helpers.js';
import { Employee, SalaryStructure } from '../src/models/index.js';
import { addDays, todayIn } from '../src/lib/dates.js';

const today = () => todayIn('Asia/Kolkata');
const mark = (token: string, employeeId: string, date: string, status: string) => api().post(`${V}/attendance/override`).set(auth(token)).send({ employeeId, date, status });
const slipOf = (run: any, employeeId: string) => run.payslips.find((p: any) => p.employeeId === employeeId);

describe('marking past and future days', () => {
  it('past days can be marked; present, absent and half day cannot be marked ahead, leave and holidays can', async () => {
    const owner = await createOwner({ plan: 'growth' });
    const emp = await addEmployee(owner);
    await mark(owner.token, emp.id, addDays(today(), -3), 'present').expect(200);
    for (const status of ['present', 'absent', 'half_day']) {
      const r = await mark(owner.token, emp.id, addDays(today(), 1), status);
      expect(r.status).toBe(400);
      expect(r.body.error.details).toMatchObject({ reason: 'future_date' });
    }
    await mark(owner.token, emp.id, addDays(today(), 2), 'leave').expect(200);
    await mark(owner.token, emp.id, addDays(today(), 3), 'holiday').expect(200);
  });

  it('staff added today show on earlier days; marking one moves their joining date and first salary back', async () => {
    const owner = await createOwner({ plan: 'growth' });
    const emp = await addEmployee(owner, { name: 'Naya Staff', wageType: 'daily', ratePaise: 60000, joiningDate: today() });
    const earlier = addDays(today(), -3);
    const day = (await api().get(`${V}/attendance`).query({ date: earlier }).set(auth(owner.token)).expect(200)).body.data;
    const row = day.find((x: any) => x.employee.id === emp.id);
    expect(row).toMatchObject({ displayStatus: 'not_marked', joinsOn: today() });
    // Too long before joining: not listed.
    const longAgo = (await api().get(`${V}/attendance`).query({ date: addDays(today(), -60) }).set(auth(owner.token)).expect(200)).body.data;
    expect(longAgo.some((x: any) => x.employee.id === emp.id)).toBe(false);

    await mark(owner.token, emp.id, earlier, 'present').expect(200);
    const e = (await Employee.findOne({ _id: emp.id, companyId: owner.companyId }).lean())!;
    expect(e.joiningDate).toBe(earlier);
    expect((await SalaryStructure.findOne({ companyId: owner.companyId, employeeId: emp.id }).lean())!.effectiveFrom).toBe(earlier);
    const after = (await api().get(`${V}/attendance`).query({ date: earlier }).set(auth(owner.token)).expect(200)).body.data;
    expect(after.find((x: any) => x.employee.id === emp.id)).toMatchObject({ displayStatus: 'present', joinsOn: null });

    // The day counts for salary.
    const run = (await api().post(`${V}/payroll/runs`).set(auth(owner.token)).send({ month: earlier.slice(0, 7) }).expect(200)).body.data;
    expect(slipOf(run, emp.id).netPaise).toBe(60000);
  });
});

describe('salary draft', () => {
  it('shows today’s numbers when opened: attendance marked and staff added after it was prepared', async () => {
    const owner = await createOwner({ plan: 'growth' });
    const a = await addEmployee(owner, { name: 'Pehle Wala', wageType: 'daily', ratePaise: 50000, joiningDate: addDays(today(), -10) });
    const month = today().slice(0, 7);
    const prepared = (await api().post(`${V}/payroll/runs`).set(auth(owner.token)).send({ month }).expect(200)).body.data;
    expect(slipOf(prepared, a.id).netPaise).toBe(0);

    await mark(owner.token, a.id, today(), 'present').expect(200);
    const b = await addEmployee(owner, { name: 'Baad Wala', wageType: 'daily', ratePaise: 40000, joiningDate: today() });
    await mark(owner.token, b.id, today(), 'present').expect(200);

    // Opening it (list, then detail) shows the new numbers without pressing "prepare" again.
    const list = (await api().get(`${V}/payroll/runs`).query({ month }).set(auth(owner.token)).expect(200)).body.data;
    expect(list[0].totals).toMatchObject({ netPaise: 90000, employees: 2 });
    const detail = (await api().get(`${V}/payroll/runs/${prepared.id}`).set(auth(owner.token)).expect(200)).body.data;
    expect(slipOf(detail, a.id).netPaise).toBe(50000);
    expect(slipOf(detail, b.id).netPaise).toBe(40000);
    expect(detail.payslips).toHaveLength(2);

    // Two screens opening it at once don't double the payslips.
    await Promise.all([1, 2, 3].map(() => api().get(`${V}/payroll/runs/${prepared.id}`).set(auth(owner.token)).expect(200)));
    const again = (await api().get(`${V}/payroll/runs/${prepared.id}`).set(auth(owner.token)).expect(200)).body.data;
    expect(again.payslips).toHaveLength(2);

    // Approved salary doesn't change any more.
    await api().post(`${V}/payroll/runs/${prepared.id}/approve`).set(auth(owner.token)).expect(200);
    await mark(owner.token, a.id, addDays(today(), -1), 'present').expect(200);
    const locked = (await api().get(`${V}/payroll/runs/${prepared.id}`).set(auth(owner.token)).expect(200)).body.data;
    expect(slipOf(locked, a.id).netPaise).toBe(50000);
  });
});
