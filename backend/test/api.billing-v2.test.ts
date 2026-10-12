import { describe, expect, it } from 'vitest';
import { Types } from 'mongoose';
import { api, auth, V, createOwner, addEmployee } from './helpers.js';
import { Attendance, Notification, Receipt } from '../src/models/index.js';
import { recommend } from '../src/modules/billing/usage.js';
import { DEFAULT_PLANS } from '../src/modules/config/defaults.js';

const plans = DEFAULT_PLANS.map((p: any) => ({ ...p, currency: 'INR', extraStaffPricePaise: p.extraStaffPricePaise ?? 0, maxStaffHardCap: p.maxStaffHardCap ?? p.staffLimit }));

describe('which plan fits (recommend)', () => {
  it('the cheapest plan that holds the staff when no paid feature is used', () => {
    expect(recommend(plans, 3, {})).toMatchObject({ planCode: 'free', cheaper: null, reasons: [{ kind: 'staff', staff: 3, limit: 5 }] });
    expect(recommend(plans, 9, {})).toMatchObject({ planCode: 'starter', cheaper: null });
  });

  it('features used in the trial move it up, with reasons and what a cheaper plan loses', () => {
    const r = recommend(plans, 9, { face_match: 85, whatsapp_payslips: 12, payroll: 1 })!;
    expect(r.planCode).toBe('growth');
    expect(r.reasons).toEqual([
      { kind: 'staff', staff: 9, limit: 30 },
      { kind: 'feature', feature: 'face_match', count: 85 },
      { kind: 'feature', feature: 'whatsapp_payslips', count: 12 },
    ]);
    expect(r.cheaper).toEqual({ planCode: 'starter', loses: [{ feature: 'face_match', count: 85 }, { feature: 'whatsapp_payslips', count: 12 }] });
  });

  it('staff count alone can need a bigger plan; Pro takes more than 50 with extra staff', () => {
    expect(recommend(plans, 20, { payroll: 2 })).toMatchObject({ planCode: 'growth', cheaper: null, reasons: [{ kind: 'staff', staff: 20, limit: 30 }] });
    expect(recommend(plans, 70, {})).toMatchObject({ planCode: 'pro' });
    expect(recommend(plans, 9, { ca_access: 1 })).toMatchObject({ planCode: 'pro', reasons: [{ kind: 'staff' }, { kind: 'feature', feature: 'ca_access', count: 1 }] });
  });
});

describe('billing summary and receipts', () => {
  it('counts what the shop used and recommends a plan', async () => {
    const owner = await createOwner();
    const emp = await addEmployee(owner, { name: 'Raju' });
    const companyId = new Types.ObjectId(owner.companyId);
    const now = new Date();
    await Attendance.create({
      companyId,
      employeeId: emp.id,
      date: now.toISOString().slice(0, 10),
      status: 'present',
      punches: [
        { type: 'in', clientTime: now, serverTime: now, face: { result: 'match', similarity: 97 } },
        { type: 'out', clientTime: now, serverTime: now, face: { result: 'unsure', similarity: 70 } },
      ],
    });
    await Notification.create({ companyId, channel: 'whatsapp', template: 'payslip_ready', status: 'sent', to: '+919876500001' });
    const r = await api().get(`${V}/billing/subscription`).set(auth(owner.token)).expect(200);
    expect(r.body.data.usage).toMatchObject({ face_match: 2, whatsapp_payslips: 1, branches: 0 });
    expect(r.body.data.billStaffCount).toBe(1);
    expect(r.body.data.priceLockMonths).toBe(24);
    expect(r.body.data.recommendation).toMatchObject({ planCode: 'growth', cheaper: { planCode: 'starter' } });
  });

  it('a payment becomes one receipt even when two webhooks report it', async () => {
    const owner = await createOwner();
    const s = await api().post(`${V}/billing/subscribe`).set(auth(owner.token)).send({ planCode: 'starter', interval: 'monthly' });
    const url = new URL(s.body.data.checkoutUrl);
    await api().get(url.pathname + url.search).expect(200);
    const subId = s.body.data.subscriptionId;
    await api().post(`${V}/webhooks/payments/mock`).send({ id: 'e1', event: 'subscription.charged', subscriptionId: subId, paymentId: 'pay_2', amountPaise: 49900 }).expect(200);
    await api().post(`${V}/webhooks/payments/mock`).send({ id: 'e2', event: 'payment.succeeded', subscriptionId: subId, paymentId: 'pay_2', amountPaise: 49900 }).expect(200);
    expect(await Receipt.countDocuments({ companyId: owner.companyId })).toBe(2); // checkout + this month
    const list = await api().get(`${V}/billing/receipts`).set(auth(owner.token)).expect(200);
    expect(list.body.data[0]).toMatchObject({ planCode: 'starter', planName: 'Starter', amountPaise: 49900, hasInvoice: false });
    // The mock gateway makes no invoices.
    await api().get(`${V}/billing/receipts/${list.body.data[0].id}/link`).set(auth(owner.token)).expect(404);
    // Another business never sees these.
    const other = await createOwner();
    expect((await api().get(`${V}/billing/receipts`).set(auth(other.token))).body.data).toEqual([]);
    await api().get(`${V}/billing/receipts/${list.body.data[0].id}/link`).set(auth(other.token)).expect(404);
  });

  it('starting checkout in a trial keeps the trial until it is paid, and the first charge waits for the trial end', async () => {
    const owner = await createOwner();
    const before = (await api().get(`${V}/billing/subscription`).set(auth(owner.token))).body.data;
    expect(before.trial?.active).toBe(true);
    const s = await api().post(`${V}/billing/subscribe`).set(auth(owner.token)).send({ planCode: 'starter', interval: 'monthly' }).expect(200);
    expect(new Date(s.body.data.firstChargeAt).toISOString()).toBe(new Date(before.trial.endsAt).toISOString());
    // Checkout left half-way: still on the trial plan.
    const after = (await api().get(`${V}/billing/subscription`).set(auth(owner.token))).body.data;
    expect(after.plan.code).toBe(before.plan.code);
    expect(after.trial?.active).toBe(true);
  });
});
