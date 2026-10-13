import { describe, expect, it } from 'vitest';
import { DateTime } from 'luxon';
import { api, auth, V, createOwner, addEmployee, employeeSession, nextPhone, mocks, setPlan } from './helpers.js';
import { AuditLog, Company, Employee, Notification, VerificationCheck, VerificationRequest } from '../src/models/index.js';
import { nameMatch } from '../src/modules/verification/service.js';
import { purgeRetention } from '../src/jobs/handlers.js';
import { setProvider } from '../src/providers/registry.js';
import { MockVerificationProvider } from '../src/providers/verification/mock.js';
import { decryptField } from '../src/lib/crypto.js';

const AADHAAR = '234567891234';

async function setup(plan = 'growth') {
  setProvider('verification', new MockVerificationProvider());
  const owner = await createOwner({ plan });
  const phone = nextPhone();
  const emp = await addEmployee(owner, { name: 'Ramesh Kumar', phone });
  const staff = await employeeSession(phone);
  return { owner, emp, staff };
}
const ask = (token: string, id: string, kinds = ['aadhaar', 'pan', 'bank']) => api().post(`${V}/verification/employees/${id}`).set(auth(token)).send({ kinds });
const mine = (token: string) => api().get(`${V}/verification/mine`).set(auth(token)).expect(200);
const step = (token: string, path: string, body: Record<string, unknown> = {}) => api().post(`${V}/verification/mine/${path}`).set(auth(token)).send(body);
const check = (data: any, kind: string) => data.checks.find((c: any) => c.kind === kind);

describe('name matching', () => {
  it('ignores case, order, titles; initials count; a missing surname is a partial match', () => {
    expect(nameMatch('Ramesh Kumar', 'RAMESH KUMAR')).toBe(100);
    expect(nameMatch('Ramesh Kumar', 'Kumar Ramesh')).toBe(100);
    expect(nameMatch('Shri Ramesh Kumar', 'R Kumar')).toBe(100);
    expect(nameMatch('Ramesh Kumar', 'Ramesh')).toBe(67);
    expect(nameMatch('Ramesh Kumar', 'Suresh Yadav')).toBe(0);
  });
});

describe('background verification', () => {
  it('owner asks → staff agrees → Aadhaar OTP, PAN, bank → verified, with nothing kept in full', async () => {
    const { messaging } = await mocks();
    const { owner, emp, staff } = await setup();
    const asked = (await ask(owner.token, emp.id).expect(201)).body.data;
    expect(asked).toMatchObject({ badge: 'asked', request: { status: 'asked', consented: false }, quota: { used: 1, limit: 3, extraPricePaise: 14900 } });
    expect(asked.checks.map((c: any) => [c.kind, c.status])).toEqual([
      ['aadhaar', 'waiting'],
      ['pan', 'waiting'],
      ['bank', 'waiting'],
    ]);
    // The staff member has the app: a push, not WhatsApp.
    expect(await Notification.exists({ companyId: owner.companyId, template: 'verification_request', channel: 'in_app' })).toBeTruthy();
    expect(messaging.outbox.filter((m) => m.template === 'verification_request')).toHaveLength(0);
    // Asking twice is refused.
    expect((await ask(owner.token, emp.id)).status).toBe(409);

    let me = (await mine(staff.token)).body.data;
    expect(me.consentText.en[1]).toMatch(/never save your full Aadhaar/);
    // Nothing is checked before they agree.
    expect((await step(staff.token, 'pan', { pan: 'ABCDE1234F' })).status).toBe(403);
    me = (await step(staff.token, 'consent').expect(200)).body.data;
    expect(me.request).toMatchObject({ consented: true, status: 'in_progress' });
    expect((await Employee.findOne({ _id: emp.id, companyId: owner.companyId }).lean())!.verification?.status).toBe('in_progress');

    // Aadhaar: OTP, a wrong one, then the right one.
    me = (await step(staff.token, 'aadhaar/otp', { aadhaar: '2345 6789 1234' }).expect(200)).body.data;
    expect(check(me, 'aadhaar')).toMatchObject({ status: 'otp_sent', last4: '1234' });
    const wrong = await step(staff.token, 'aadhaar/verify', { otp: '000000' });
    expect(wrong.status).toBe(400);
    expect(wrong.body.error.code).toBe('OTP_INVALID');
    me = (await step(staff.token, 'aadhaar/verify', { otp: '123456' }).expect(200)).body.data;
    expect(check(me, 'aadhaar')).toMatchObject({ status: 'verified', last4: '1234', details: null });

    me = (await step(staff.token, 'pan', { pan: 'abcde1234f' }).expect(200)).body.data;
    expect(check(me, 'pan')).toMatchObject({ status: 'verified', nameOnRecord: 'RAMESH KUMAR', matchScore: 100 });
    // A real PAN fills the profile (for salary slips) when it was empty.
    expect(decryptField((await Employee.findOne({ _id: emp.id, companyId: owner.companyId }).lean())!.panEnc!)).toBe('ABCDE1234F');

    me = (await step(staff.token, 'bank', { accountNumber: '123456781234', ifsc: 'sbin0001234' }).expect(200)).body.data;
    expect(check(me, 'bank')).toMatchObject({ status: 'verified', last4: '1234' });
    expect(me.request.status).toBe('done');
    // The checked account became their salary account (and the owner heard about it, as with any change).
    expect(me.savedBank).toEqual({ last4: '1234', ifsc: 'SBIN0001234' });
    expect(await Notification.exists({ companyId: owner.companyId, template: 'bank_changed' })).toBeTruthy();

    const view = (await api().get(`${V}/verification/employees/${emp.id}`).set(auth(owner.token)).expect(200)).body.data;
    expect(view.badge).toBe('verified');
    // The owner sees what Aadhaar said (encrypted at rest), never the number.
    expect(check(view, 'aadhaar').details).toEqual({ dob: '1995-04-12', gender: 'M', state: 'Delhi' });
    const done = await Notification.findOne({ companyId: owner.companyId, template: 'verification_done', channel: 'in_app' }).lean();
    expect(done?.title).toMatch(/Ramesh Kumar के दस्तावेज़ सही निकले|Ramesh Kumar's documents are verified/);
    const staffList = (await api().get(`${V}/employees`).set(auth(owner.token)).expect(200)).body.data;
    expect(staffList.find((e: any) => e.id === emp.id).verification).toBe('verified');

    // No full Aadhaar or account number anywhere in what we store.
    const stored = JSON.stringify(await VerificationCheck.find({ companyId: owner.companyId }).lean()) + JSON.stringify(await AuditLog.find({ companyId: owner.companyId }).lean());
    expect(stored).not.toContain(AADHAAR);
    expect(stored).not.toContain('123456781234');
  });

  it('a name that doesn’t match: the owner accepts it; not found: staff retry, or the owner asks again', async () => {
    const { owner, emp, staff } = await setup();
    await ask(owner.token, emp.id, ['pan', 'bank']).expect(201);
    await step(staff.token, 'consent').expect(200);
    let me = (await step(staff.token, 'pan', { pan: 'ABCDE1234Z' }).expect(200)).body.data;
    expect(check(me, 'pan')).toMatchObject({ status: 'mismatch', nameOnRecord: 'Rajesh Kumar Sharma', matchScore: 40 });
    // Someone else's PAN isn't saved to their profile.
    expect((await Employee.findOne({ _id: emp.id, companyId: owner.companyId }).lean())!.panEnc).toBeNull();
    me = (await step(staff.token, 'bank', { accountNumber: '111122220000', ifsc: 'SBIN0001234' }).expect(200)).body.data;
    expect(check(me, 'bank').status).toBe('not_found');
    expect(me.request.status).toBe('done');
    expect((await Employee.findOne({ _id: emp.id, companyId: owner.companyId }).lean())!.verification?.status).toBe('needs_attention');
    expect(await Notification.exists({ companyId: owner.companyId, template: 'verification_done' })).toBeTruthy();

    // Staff can fix a typo themselves.
    me = (await step(staff.token, 'bank', { accountNumber: '111122223333', ifsc: 'SBIN0001234' }).expect(200)).body.data;
    expect(check(me, 'bank').status).toBe('verified');

    // The owner looks at the PAN name and accepts it.
    const view = (await api().get(`${V}/verification/employees/${emp.id}`).set(auth(owner.token)).expect(200)).body.data;
    const pan = check(view, 'pan');
    expect((await api().post(`${V}/verification/checks/${check(view, 'bank').id}/accept`).set(auth(owner.token)).send({ reason: 'x' })).status).toBe(409);
    const accepted = (await api().post(`${V}/verification/checks/${pan.id}/accept`).set(auth(owner.token)).send({ reason: 'Father’s name is on his PAN' }).expect(200)).body.data;
    expect(check(accepted, 'pan').override).toMatchObject({ reason: 'Father’s name is on his PAN' });
    expect(accepted.badge).toBe('verified');
    expect(await AuditLog.exists({ companyId: owner.companyId, action: 'verification.accept' })).toBeTruthy();

    // Ask again sends one step back to the staff member.
    await Employee.updateOne({ _id: emp.id, companyId: owner.companyId }, { $set: { 'verification.status': 'verified' } });
    const again = (await api().post(`${V}/verification/checks/${pan.id}/ask-again`).set(auth(owner.token))).status;
    expect(again).toBe(409); // already accepted
  });

  it('owner asks again after "not found"; the provider being down is "try again", not a result', async () => {
    const { owner, emp, staff } = await setup();
    await ask(owner.token, emp.id, ['pan']).expect(201);
    await step(staff.token, 'consent').expect(200);
    let me = (await step(staff.token, 'pan', { pan: 'ZZCDE1234F' }).expect(200)).body.data;
    expect(check(me, 'pan').status).toBe('not_found');
    const view = (await api().get(`${V}/verification/employees/${emp.id}`).set(auth(owner.token)).expect(200)).body.data;
    const back = (await api().post(`${V}/verification/checks/${check(view, 'pan').id}/ask-again`).set(auth(owner.token)).expect(200)).body.data;
    expect(check(back, 'pan').status).toBe('waiting');
    expect(back.request.status).toBe('in_progress');
    expect(await Notification.exists({ companyId: owner.companyId, template: 'verification_again' })).toBeTruthy();

    const down = new MockVerificationProvider();
    down.verifyPan = async () => {
      throw new Error('ECONNRESET');
    };
    setProvider('verification', down);
    me = (await step(staff.token, 'pan', { pan: 'ABCDE1234F' }).expect(200)).body.data;
    expect(check(me, 'pan').status).toBe('failed');
    expect(me.request.status).toBe('in_progress');
    setProvider('verification', new MockVerificationProvider());
    me = (await step(staff.token, 'pan', { pan: 'ABCDE1234F' }).expect(200)).body.data;
    expect(check(me, 'pan').status).toBe('verified');
    // Bad input never reaches the provider.
    expect((await step(staff.token, 'aadhaar/otp', { aadhaar: '123456789012' })).status).toBe(400);
  });

  it('monthly allowance by plan; cancelling gives it back; Starter has no checks', async () => {
    const { owner, emp } = await setup('growth');
    const others = [await addEmployee(owner, { name: 'A' }), await addEmployee(owner, { name: 'B' }), await addEmployee(owner, { name: 'C' })];
    await ask(owner.token, emp.id).expect(201);
    await ask(owner.token, others[0].id).expect(201);
    await ask(owner.token, others[1].id).expect(201);
    const fourth = await ask(owner.token, others[2].id);
    expect(fourth.status).toBe(402);
    expect(fourth.body.error).toMatchObject({ code: 'PLAN_LIMIT', details: { used: 3, limit: 3, extraPricePaise: 14900 } });
    await api().delete(`${V}/verification/employees/${emp.id}`).set(auth(owner.token)).expect(200);
    expect((await Employee.findOne({ _id: emp.id, companyId: owner.companyId }).lean())!.verification?.status).toBe('none');
    await ask(owner.token, others[2].id).expect(201);

    await setPlan(owner.companyId, 'starter');
    const r = await ask(owner.token, emp.id);
    expect(r.status).toBe(402);
    expect(r.body.error.code).toBe('FEATURE_NOT_IN_PLAN');
  });

  it('only the owner sees results; staff can only do their own', async () => {
    const { owner, emp, staff } = await setup();
    await ask(owner.token, emp.id).expect(201);
    expect((await api().get(`${V}/verification/employees/${emp.id}`).set(auth(staff.token))).status).toBe(403);
    const other = await createOwner({ plan: 'growth' });
    expect((await api().get(`${V}/verification/employees/${emp.id}`).set(auth(other.token))).status).toBe(404);
    // Staff of another business have nothing to do here.
    const p2 = nextPhone();
    await addEmployee(other, { name: 'X', phone: p2 });
    const s2 = await employeeSession(p2);
    expect((await step(s2.token, 'consent')).status).toBe(404);
  });

  it('results are deleted 180 days after someone leaves', async () => {
    const { owner, emp, staff } = await setup();
    await ask(owner.token, emp.id, ['pan']).expect(201);
    await step(staff.token, 'consent').expect(200);
    await step(staff.token, 'pan', { pan: 'ABCDE1234F' }).expect(200);
    const company = await Company.findById(owner.companyId).lean();
    const left = DateTime.now().minus({ days: 200 }).toISODate();
    await Employee.updateOne({ _id: emp.id, companyId: owner.companyId }, { $set: { exitDate: left } });
    await purgeRetention(company, new Date());
    expect(await VerificationCheck.countDocuments({ companyId: owner.companyId })).toBe(0);
    expect(await VerificationRequest.countDocuments({ companyId: owner.companyId })).toBe(0);
    expect((await Employee.findOne({ _id: emp.id, companyId: owner.companyId }).lean())!.verification?.status).toBe('none');
  });
});
