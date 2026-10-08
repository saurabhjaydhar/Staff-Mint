import { describe, expect, it } from 'vitest';
import { Types } from 'mongoose';
import { api, auth, V, createOwner, addEmployee } from './helpers.js';
import { Attendance, Company, Plan, Subscription } from '../src/models/index.js';

const binary = (res: any, cb: any) => {
  const chunks: Buffer[] = [];
  res.on('data', (c: Buffer) => chunks.push(c));
  res.on('end', () => cb(null, Buffer.concat(chunks)));
};

describe('billing (dynamic plans)', () => {
  it('plans come from the DB and can change without a release', async () => {
    const r = await api().get(`${V}/billing/plans`);
    expect(r.body.data.map((p: any) => p.code)).toEqual(['free', 'starter', 'growth', 'pro']);
    expect(r.body.data[1]).toMatchObject({ priceMonthlyPaise: 49900, staffLimit: 15 });
    await api().put(`${V}/admin/plans/starter`).set('x-admin-key', 'dev-admin-key').send({ name: 'Starter', priceMonthlyPaise: 39900, priceYearlyPaise: 399000, staffLimit: 20, features: ['attendance', 'payroll'] }).expect(200);
    expect((await api().get(`${V}/billing/plans`)).body.data[1]).toMatchObject({ priceMonthlyPaise: 39900, staffLimit: 20 });
    expect((await api().put(`${V}/admin/plans/starter`).send({})).status).toBe(401);
    await Plan.deleteMany({});
  });

  it('subscribe → checkout → webhook activates; duplicate events are idempotent; cancel keeps export', async () => {
    const owner = await createOwner();
    const s = await api().post(`${V}/billing/subscribe`).set(auth(owner.token)).send({ planCode: 'growth', interval: 'yearly' });
    expect(s.body.data).toMatchObject({ provider: 'mock', amountPaise: 999000 });
    const url = new URL(s.body.data.checkoutUrl);
    await api().get(url.pathname + url.search).expect(200);
    const sum = await api().get(`${V}/billing/subscription`).set(auth(owner.token));
    expect(sum.body.data).toMatchObject({ plan: { code: 'growth' }, subscription: { status: 'active', interval: 'yearly' } });
    expect(new Date(sum.body.data.subscription.priceLockedUntil).getTime()).toBeGreaterThan(Date.now() + 700 * 86400_000);
    const ev = { id: 'evt_1', event: 'subscription.charged', subscriptionId: s.body.data.subscriptionId };
    await api().post(`${V}/webhooks/payments/mock`).send(ev).expect(200);
    await api().post(`${V}/webhooks/payments/mock`).send(ev).expect(200);
    expect(await Subscription.countDocuments({ companyId: owner.companyId, status: 'active' })).toBe(1);
    await api().post(`${V}/billing/cancel`).set(auth(owner.token)).expect(200);
    const c = await Company.findById(owner.companyId).lean();
    expect(c!.exportAvailableUntil!.getTime()).toBeGreaterThan(Date.now() + 29 * 86400_000);
    // Still on paid plan until the period ends
    expect((await api().get(`${V}/billing/subscription`).set(auth(owner.token))).body.data.plan.code).toBe('growth');
    // Export works regardless of plan
    const ex = await api().get(`${V}/export`).set(auth(owner.token)).buffer(true).parse(binary);
    expect(ex.status).toBe(200);
    expect(ex.body.subarray(0, 2).toString()).toBe('PK');
    const exUrl = await api().get(`${V}/export?delivery=url`).set(auth(owner.token));
    expect(exUrl.body.data.url).toContain('/files/exports/');
  });

  it('rejects payment webhooks with a bad signature (razorpay)', async () => {
    const r = await api().post(`${V}/webhooks/payments/razorpay`).set('x-razorpay-signature', 'bad').send({ event: 'subscription.activated' });
    expect(r.status).toBe(401);
  });
});

describe('reports', () => {
  it('attendance report as XLSX and PDF, or a signed URL', async () => {
    const owner = await createOwner();
    const emp = await addEmployee(owner, { name: 'Ramesh', joiningDate: '2026-01-01' });
    await Attendance.create({ companyId: new Types.ObjectId(owner.companyId), employeeId: emp.id, date: '2026-09-01', status: 'present', lateMinutes: 20 });
    const x = await api().get(`${V}/reports/attendance?month=2026-09&format=xlsx`).set(auth(owner.token)).buffer(true).parse(binary);
    expect(x.headers['content-type']).toContain('spreadsheetml');
    expect(x.body.subarray(0, 2).toString()).toBe('PK');
    const p = await api().get(`${V}/reports/late?month=2026-09&format=pdf`).set(auth(owner.token)).buffer(true).parse(binary);
    expect(p.body.subarray(0, 5).toString()).toBe('%PDF-');
    const u = await api().get(`${V}/reports/advances?month=2026-09&delivery=url`).set(auth(owner.token));
    expect(u.body.data.url).toContain('/files/reports/');
    expect((await api().get(`${V}/reports/salary?month=2026-09`).set(auth(owner.token))).status).toBe(404);
  });
});
