import { describe, expect, it } from 'vitest';
import { api, auth, V, createOwner, addEmployee } from './helpers.js';
import { Employee } from '../src/models/index.js';

describe('tenant isolation', () => {
  it('company B cannot read or modify company A data', async () => {
    const a = await createOwner();
    const b = await createOwner();
    const empA = await addEmployee(a, { name: 'Secret A' });
    expect((await api().get(`${V}/employees/${empA.id}`).set(auth(b.token))).status).toBe(404);
    expect((await api().patch(`${V}/employees/${empA.id}`).set(auth(b.token)).send({ name: 'Hacked' })).status).toBe(404);
    expect((await api().post(`${V}/attendance/override`).set(auth(b.token)).send({ employeeId: empA.id, date: '2026-10-01', status: 'absent', reason: 'x y' })).status).toBe(404);
    expect((await api().post(`${V}/advances`).set(auth(b.token)).send({ employeeId: empA.id, amountPaise: 100, date: '2026-10-01' })).status).toBe(404);
    const listB = await api().get(`${V}/employees`).set(auth(b.token));
    expect(listB.body.data).toEqual([]);
    const auditB = await api().get(`${V}/audit-logs`).set(auth(b.token));
    expect(auditB.body.data.every((l: any) => l.entityId !== empA.id)).toBe(true);
    // companyId in body is ignored (always from token)
    const r = await api().post(`${V}/employees`).set(auth(b.token)).send({ name: 'X', phone: '9811111111', companyId: a.companyId });
    expect(r.status).toBe(201);
    expect((await Employee.findById(r.body.data.id).setOptions({ skipTenant: true }).lean())!.companyId.toString()).not.toBe(a.companyId);
  });

  it('the ODM tenant guard rejects queries without companyId', async () => {
    await expect(Employee.find({ name: 'x' }).lean()).rejects.toThrow(/Tenant guard/);
    await expect(Employee.find({ name: 'x' }).setOptions({ skipTenant: true }).lean()).resolves.toEqual([]);
  });

  it('employees cannot call owner endpoints', async () => {
    const { employeeSession, nextPhone } = await import('./helpers.js');
    const owner = await createOwner();
    const phone = nextPhone();
    await addEmployee(owner, { phone });
    const e = await employeeSession(phone);
    expect((await api().get(`${V}/employees`).set(auth(e.token))).status).toBe(403);
    expect((await api().post(`${V}/payroll/runs`).set(auth(e.token)).send({ month: '2026-09' })).status).toBe(403);
    expect((await api().get(`${V}/audit-logs`).set(auth(e.token))).status).toBe(403);
  });
});
