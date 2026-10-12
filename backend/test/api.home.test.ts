import { describe, expect, it } from 'vitest';
import { api, auth, V, createOwner, addEmployee, employeeSession, nextPhone, mocks } from './helpers.js';
import { Employee } from '../src/models/index.js';

describe('owner Home (redesign)', () => {
  it('checklist ticks itself; rows say who has not joined; Remind re-sends only stale invites', async () => {
    await mocks();
    const owner = await createOwner({ plan: 'growth' });
    let dash = await api().get(`${V}/dashboard/today`).set(auth(owner.token)).expect(200);
    expect(dash.body.data.setup).toMatchObject({ done: 1, total: 5, staff: 0, steps: { business: true, staffAdded: false, staffJoined: false, salarySet: false, teamAdded: false } });

    const p1 = nextPhone();
    const a = await addEmployee(owner, { phone: p1, name: 'Pooja Singh' });
    const b = await addEmployee(owner, { name: 'Suresh Yadav', ratePaise: 0 });
    await employeeSession(p1); // Pooja opens the app
    dash = await api().get(`${V}/dashboard/today`).set(auth(owner.token)).expect(200);
    expect(dash.body.data.setup).toMatchObject({ staff: 2, joined: 1, notJoined: 1, steps: { staffAdded: true, salarySet: false } });

    const today = dash.body.data.date;
    const rows = (await api().get(`${V}/attendance`).query({ date: today }).set(auth(owner.token)).expect(200)).body.data;
    const suresh = rows.find((r: any) => r.employee.id === b.id);
    expect(suresh.employee).toMatchObject({ linked: false });
    expect(suresh.employee.invitedAt).toBeTruthy();
    expect(rows.find((r: any) => r.employee.id === a.id).employee.linked).toBe(true);

    // Invited moments ago → nothing re-sent; an old invite is re-sent.
    let r = await api().post(`${V}/employees/remind-invites`).set(auth(owner.token)).expect(200);
    expect(r.body.data).toEqual({ sent: 0, skipped: 1 });
    await Employee.updateOne({ _id: b.id }, { invitedAt: new Date(Date.now() - 3600_000) }).setOptions({ skipTenant: true });
    r = await api().post(`${V}/employees/remind-invites`).set(auth(owner.token)).expect(200);
    expect(r.body.data).toEqual({ sent: 1, skipped: 0 });

    // Setting the last salary ticks that step.
    await api().patch(`${V}/employees/${b.id}`).set(auth(owner.token)).send({ ratePaise: 900000 }).expect(200);
    dash = await api().get(`${V}/dashboard/today`).set(auth(owner.token)).expect(200);
    expect(dash.body.data.setup.steps.salarySet).toBe(true);
  });

  it('a leave request shows the effect of saying yes; a day can be changed without a reason', async () => {
    await mocks();
    const owner = await createOwner({ plan: 'growth' });
    const phone = nextPhone();
    const emp = await addEmployee(owner, { phone, name: 'Amit Verma' });
    const e = await employeeSession(phone);
    await api().put(`${V}/leave-balances/${emp.id}`).set(auth(owner.token)).send({ year: 2026, paid: 4, sick: 2 }).expect(200);
    await api().post(`${V}/leaves`).set(auth(e.token)).send({ type: 'paid', from: '2026-10-14', to: '2026-10-15', reason: 'Sister’s wedding' }).expect(201);
    const dash = await api().get(`${V}/dashboard/today`).set(auth(owner.token)).expect(200);
    expect(dash.body.data.needsAction.leaveRequests[0]).toMatchObject({ employeeName: 'Amit Verma', days: 2, balance: { left: 4, after: 2 } });

    const o = await api().post(`${V}/attendance/override`).set(auth(owner.token)).send({ employeeId: emp.id, date: '2026-10-12', status: 'absent' }).expect(200);
    expect(o.body.data).toMatchObject({ status: 'absent', overridden: true, overrideReason: null, overriddenBy: owner.userId });
  });

  it('holiday rows carry the holiday name', async () => {
    const owner = await createOwner();
    await addEmployee(owner);
    await api().post(`${V}/holidays`).set(auth(owner.token)).send({ date: '2026-11-17', name: 'Shop anniversary' }).expect(201);
    const rows = (await api().get(`${V}/attendance`).query({ date: '2026-11-17' }).set(auth(owner.token)).expect(200)).body.data;
    expect(rows[0]).toMatchObject({ displayStatus: 'holiday', holidayName: 'Shop anniversary' });
  });
});

describe('Team & access', () => {
  it('Make manager: own branch by default or all branches; the person is told; back to staff tells them too', async () => {
    await mocks();
    const owner = await createOwner({ plan: 'growth' });
    const phone = nextPhone();
    const emp = await addEmployee(owner, { phone, name: 'Ramesh Kumar' });
    const e = await employeeSession(phone);

    const r = await api().post(`${V}/employees/${emp.id}/role`).set(auth(owner.token)).send({ role: 'manager', allBranches: true }).expect(200);
    expect(r.body.data.appRole).toBe('manager');
    const { Membership, Notification } = await import('../src/models/index.js');
    const m = await Membership.findOne({ companyId: owner.companyId, employeeId: emp.id }).lean();
    expect(m).toMatchObject({ role: 'manager', branchIds: [] });
    expect(await Notification.findOne({ companyId: owner.companyId, template: 'role_manager', channel: 'in_app' }).lean()).toBeTruthy();
    // Their open session is ended so the app refreshes into the manager view.
    expect((await api().get(`${V}/attendance`).set(auth(e.token))).status).toBe(401);

    // Same role again: no second message.
    await api().post(`${V}/employees/${emp.id}/role`).set(auth(owner.token)).send({ role: 'manager' }).expect(200);
    expect(await Notification.countDocuments({ companyId: owner.companyId, template: 'role_manager', channel: 'in_app' })).toBe(1);

    await api().post(`${V}/employees/${emp.id}/role`).set(auth(owner.token)).send({ role: 'employee' }).expect(200);
    expect(await Notification.findOne({ companyId: owner.companyId, template: 'role_employee', channel: 'in_app' }).lean()).toBeTruthy();
    expect((await api().post(`${V}/employees/${emp.id}/role`).set(auth(owner.token)).send({ role: 'owner' })).status).toBe(400);
  });
});
