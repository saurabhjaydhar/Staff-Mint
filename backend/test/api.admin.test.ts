import { describe, expect, it } from 'vitest';
import { api, auth, V, createOwner, addEmployee, setPlan } from './helpers.js';
import { AdminAction, AdminUser, Notification, Subscription } from '../src/models/index.js';
import { createAdmin } from '../src/modules/admin/service.js';

const PASSWORD = 'mint-admin-2026';
let seq = 0;

async function adminSession(role: 'admin' | 'viewer' = 'admin') {
  const email = `ops${++seq}-${Date.now()}@staffmint.app`;
  await createAdmin({ email, role, password: PASSWORD, name: 'Ops' });
  const step1 = await api().post(`${V}/admin-auth/login`).send({ email, password: PASSWORD }).expect(200);
  const step2 = await api().post(`${V}/admin-auth/verify`).send({ ticket: step1.body.data.ticket, code: step1.body.data.devCode }).expect(200);
  return { email, token: step2.body.data.accessToken as string, admin: step2.body.data.admin };
}

describe('Admin app: sign-in', () => {
  it('email + password, then the emailed code; wrong steps fail; logout ends the session', async () => {
    const email = `owner-${Date.now()}@staffmint.app`;
    await createAdmin({ email, role: 'admin', password: PASSWORD });
    // Unknown email and wrong password look the same.
    const unknown = await api().post(`${V}/admin-auth/login`).send({ email: 'nobody@x.com', password: PASSWORD });
    const wrong = await api().post(`${V}/admin-auth/login`).send({ email, password: 'wrong-pass-1' });
    expect(unknown.status).toBe(401);
    expect(wrong.status).toBe(401);
    expect(unknown.body.error.message).toBe(wrong.body.error.message);

    const s1 = await api().post(`${V}/admin-auth/login`).send({ email: email.toUpperCase(), password: PASSWORD }).expect(200);
    expect(s1.body.data.sentTo).toMatch(/^o•+@staffmint\.app$/);
    expect(s1.body.data.devCode).toMatch(/^\d{6}$/);
    const bad = await api().post(`${V}/admin-auth/verify`).send({ ticket: s1.body.data.ticket, code: s1.body.data.devCode === '000000' ? '111111' : '000000' });
    expect(bad.body.error.code).toBe('OTP_INVALID');
    const ok = await api().post(`${V}/admin-auth/verify`).send({ ticket: s1.body.data.ticket, code: s1.body.data.devCode }).expect(200);
    expect(ok.body.data.admin).toMatchObject({ email, role: 'admin' });
    // The code works once.
    expect((await api().post(`${V}/admin-auth/verify`).send({ ticket: s1.body.data.ticket, code: s1.body.data.devCode })).status).toBe(401);

    const token = ok.body.data.accessToken;
    expect((await api().get(`${V}/admin/me`).set(auth(token)).expect(200)).body.data.email).toBe(email);
    await api().post(`${V}/admin/logout`).set(auth(token)).expect(200);
    expect((await api().get(`${V}/admin/me`).set(auth(token))).status).toBe(401);
  });

  it('locks for 15 minutes after 5 wrong passwords; a business owner token is not an admin token', async () => {
    const email = `lock-${Date.now()}@staffmint.app`;
    await createAdmin({ email, role: 'admin', password: PASSWORD });
    for (let i = 0; i < 5; i++) await api().post(`${V}/admin-auth/login`).send({ email, password: 'wrong-pass-1' }).expect(401);
    const locked = await api().post(`${V}/admin-auth/login`).send({ email, password: PASSWORD });
    expect(locked.status).toBe(429);
    const owner = await createOwner();
    expect((await api().get(`${V}/admin/stats`).set(auth(owner.token))).status).toBe(401);
    expect((await api().get(`${V}/admin/stats`)).status).toBe(401);
  });

  it('weak passwords are refused', async () => {
    await expect(createAdmin({ email: `weak-${Date.now()}@x.com`, role: 'admin', password: 'short1' })).rejects.toThrow(/10 characters/);
  });
});

describe('Admin app: businesses and changes', () => {
  it('home numbers and the business list with status, search and filters', async () => {
    const { token } = await adminSession();
    const trial = await createOwner({ setup: { name: `Trial Sweets ${seq}` } });
    const paid = await createOwner({ plan: 'growth', setup: { name: `Paid Medical ${seq}` } });
    await addEmployee(paid, { name: 'A' });
    await addEmployee(paid, { name: 'B' });

    const stats = await api().get(`${V}/admin/stats`).set(auth(token)).expect(200);
    expect(stats.body.data.businesses.trial).toBeGreaterThanOrEqual(1);
    expect(stats.body.data.businesses.paid).toBeGreaterThanOrEqual(1);
    expect(stats.body.data.mrrPaise).toBeGreaterThan(0);
    expect(stats.body.data.signups.perDay).toHaveLength(30);
    expect(stats.body.data.signups.perDay.at(-1).count).toBeGreaterThanOrEqual(2);

    const byName = await api().get(`${V}/admin/companies`).query({ search: `Paid Medical ${seq}` }).set(auth(token)).expect(200);
    expect(byName.body.data.rows).toMatchObject([{ id: paid.companyId, status: 'paid', planCode: 'growth', staffCount: 2 }]);
    const byPhone = await api().get(`${V}/admin/companies`).query({ search: trial.phone }).set(auth(token)).expect(200);
    expect(byPhone.body.data.rows.map((r: any) => r.id)).toEqual([trial.companyId]);
    expect(byPhone.body.data.rows[0]).toMatchObject({ status: 'trial', planCode: 'pro', owner: { phone: `+91${trial.phone}` } });
    const trials = await api().get(`${V}/admin/companies`).query({ status: 'trial', limit: 100 }).set(auth(token)).expect(200);
    expect(trials.body.data.rows.every((r: any) => r.status === 'trial')).toBe(true);
    expect(trials.body.data.rows.some((r: any) => r.id === trial.companyId)).toBe(true);
    // Regex characters in a search are plain text.
    await api().get(`${V}/admin/companies`).query({ search: '(.*' }).set(auth(token)).expect(200);
  });

  it('business detail; put on a plan by hand; free; every change is logged', async () => {
    const { token, email } = await adminSession();
    const owner = await createOwner({ setup: { name: 'Gupta Sweets' } });
    const detail = await api().get(`${V}/admin/companies/${owner.companyId}`).set(auth(token)).expect(200);
    expect(detail.body.data).toMatchObject({ name: 'Gupta Sweets', status: 'trial', plan: { code: 'pro' }, trial: { active: true }, people: [{ role: 'owner', main: true }] });

    await api().post(`${V}/admin/companies/${owner.companyId}/plan`).set(auth(token)).send({ planCode: 'growth', months: 3, note: 'Launch offer' }).expect(200);
    let d = (await api().get(`${V}/admin/companies/${owner.companyId}`).set(auth(token))).body.data;
    expect(d).toMatchObject({ status: 'paid', plan: { code: 'growth' }, trial: null });
    const me = await api().get(`${V}/me`).set(auth(owner.token));
    expect(me.body.data.company.plan.code).toBe('growth');
    // Hand-given plans don't count as revenue.
    const sub = await Subscription.findOne({ companyId: owner.companyId, status: 'active' }).lean();
    expect(sub!.pricePaise).toBe(0);

    await api().post(`${V}/admin/companies/${owner.companyId}/plan`).set(auth(token)).send({ planCode: 'free' }).expect(200);
    d = (await api().get(`${V}/admin/companies/${owner.companyId}`).set(auth(token))).body.data;
    expect(d).toMatchObject({ status: 'free', plan: { code: 'free' } });
    expect(d.actions.map((a: any) => [a.action, a.actor])).toEqual([
      ['company.plan', email],
      ['company.plan', email],
    ]);
    expect(d.actions[1].details).toMatchObject({ planCode: 'growth', months: 3, note: 'Launch offer' });
    // A live Razorpay subscription must be cancelled there first.
    await Subscription.create({ companyId: owner.companyId, provider: 'razorpay', planCode: 'pro', status: 'active', currentPeriodEnd: new Date(Date.now() + 86400_000) });
    const blocked = await api().post(`${V}/admin/companies/${owner.companyId}/plan`).set(auth(token)).send({ planCode: 'starter' });
    expect(blocked.body.error.details.reason).toBe('provider_subscription');
    expect((await api().post(`${V}/admin/companies/${owner.companyId}/plan`).set(auth(token)).send({ planCode: 'gold' })).status).toBe(400);
  });

  it('viewers can look but not change anything', async () => {
    const { token } = await adminSession('viewer');
    await api().get(`${V}/admin/stats`).set(auth(token)).expect(200);
    await api().get(`${V}/admin/configs`).set(auth(token)).expect(200);
    const owner = await createOwner();
    expect((await api().post(`${V}/admin/companies/${owner.companyId}/plan`).set(auth(token)).send({ planCode: 'pro' })).status).toBe(403);
    expect((await api().put(`${V}/admin/configs/trial.reminderDays`).set(auth(token)).send({ value: [5] })).status).toBe(403);
    expect((await api().post(`${V}/admin/trials`).set(auth(token)).send({ companyId: owner.companyId })).status).toBe(403);
  });

  it('settings list with defaults; values keep their type; the API key still works for scripts', async () => {
    const { token } = await adminSession();
    const list = (await api().get(`${V}/admin/configs`).set(auth(token)).expect(200)).body.data;
    expect(list.find((c: any) => c.key === 'signup.trialPlan')).toMatchObject({ value: 'pro', defaultValue: 'pro', changed: false });
    const bad = await api().put(`${V}/admin/configs/accounts.restoreDays`).set(auth(token)).send({ value: 'thirty' });
    expect(bad.body.error.message).toMatch(/must be a number/);
    await api().put(`${V}/admin/configs/accounts.restoreDays`).set(auth(token)).send({ value: 45 }).expect(200);
    const after = (await api().get(`${V}/admin/configs`).set(auth(token))).body.data;
    expect(after.find((c: any) => c.key === 'accounts.restoreDays')).toMatchObject({ value: 45, changed: true });
    await api().put(`${V}/admin/configs/accounts.restoreDays`).set('x-admin-key', 'dev-admin-key').send({ value: 30 }).expect(200);
    const log = await AdminAction.find({ action: 'config.update', target: 'accounts.restoreDays' }).sort({ createdAt: 1 }).lean();
    expect(log.map((l) => l.actor).slice(-2)).toEqual([expect.stringContaining('@staffmint.app'), 'api-key']);
    expect((await api().get(`${V}/admin/plans`).set(auth(token))).body.data.map((p: any) => p.code)).toEqual(expect.arrayContaining(['free', 'pro']));
  });

  it('messages: failed WhatsApp sends across businesses', async () => {
    const { token } = await adminSession();
    const owner = await createOwner({ setup: { name: 'Sharma Medical' } });
    await Notification.create({ companyId: owner.companyId, channel: 'whatsapp', template: 'staff_invite', to: '+919800000001', status: 'failed', error: 'Template not approved' });
    await Notification.create({ companyId: owner.companyId, channel: 'in_app', title: 'x', status: 'delivered' });
    const r = await api().get(`${V}/admin/messages`).query({ status: 'failed', companyId: owner.companyId }).set(auth(token)).expect(200);
    expect(r.body.data.rows).toMatchObject([{ companyName: 'Sharma Medical', template: 'staff_invite', error: 'Template not approved' }]);
    const all = await api().get(`${V}/admin/messages`).query({ companyId: owner.companyId }).set(auth(token)).expect(200);
    expect(all.body.data.rows.every((m: any) => m.channel !== 'in_app')).toBe(true);
  });

  it('admin accounts: add a viewer, keep at least one admin, never lock yourself out', async () => {
    const { token, admin } = await adminSession();
    const created = await api().post(`${V}/admin/admins`).set(auth(token)).send({ email: `support-${Date.now()}@staffmint.app`, password: PASSWORD, role: 'viewer' }).expect(201);
    expect(created.body.data.role).toBe('viewer');
    expect((await api().post(`${V}/admin/admins`).set(auth(token)).send({ email: created.body.data.email, password: PASSWORD })).status).toBe(409);
    expect((await api().patch(`${V}/admin/admins/${admin.id}`).set(auth(token)).send({ active: false })).status).toBe(409);
    await api().patch(`${V}/admin/admins/${created.body.data.id}`).set(auth(token)).send({ active: false }).expect(200);
    expect((await AdminUser.findById(created.body.data.id).lean())!.active).toBe(false);
    // Password change signs out every session.
    await api().post(`${V}/admin/me/password`).set(auth(token)).send({ current: PASSWORD, next: 'new-admin-pass-9' }).expect(200);
    expect((await api().get(`${V}/admin/me`).set(auth(token))).status).toBe(401);
  });

  it('trials from the admin app are logged per business', async () => {
    const { token } = await adminSession();
    const owner = await createOwner();
    await setPlan(owner.companyId, 'free');
    await api().post(`${V}/admin/trials`).set(auth(token)).send({ companyId: owner.companyId, days: 7 }).expect(200);
    const log = await AdminAction.findOne({ companyId: owner.companyId, action: 'company.trial' }).lean();
    expect(log!.details).toMatchObject({ days: 7, planCode: 'pro' });
  });
});
