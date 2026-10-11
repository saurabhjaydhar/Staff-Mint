import { describe, expect, it } from 'vitest';
import { api, auth, V, createOwner, addEmployee, mocks, otpLogin } from './helpers.js';
import { Company, Notification, Subscription, User } from '../src/models/index.js';
import { schedulerTick } from '../src/jobs/handlers.js';

const DAY = 86400_000;
const admin = { 'x-admin-key': 'dev-admin-key' };
/** 11:00 IST on the given offset from now, so trial messages (sent 10 AM–8 PM) are due. */
const daytime = (offsetDays: number) => {
  const d = new Date(Date.now() + offsetDays * DAY);
  d.setUTCHours(5, 30, 0, 0);
  return d;
};

describe('Free trial: every new owner tries all features for 14 days', () => {
  it('a new business gets 14 days of Pro, with a countdown in /me and billing', async () => {
    const owner = await createOwner();
    const me = await api().get(`${V}/me`).set(auth(owner.token)).expect(200);
    expect(me.body.data.company.plan.code).toBe('pro');
    expect(me.body.data.company.plan.features).toEqual(expect.arrayContaining(['payroll', 'branches', 'face_match', 'ca_access']));
    expect(me.body.data.company.trial).toMatchObject({ planCode: 'pro', planName: 'Pro', daysLeft: 14, active: true, ended: false });
    expect(me.body.data.company.trial.paidFeatures).toContain('payroll');
    expect(me.body.data.company.trial.paidFeatures).not.toContain('attendance');
    const bill = await api().get(`${V}/billing/subscription`).set(auth(owner.token)).expect(200);
    expect(bill.body.data.trial).toMatchObject({ daysLeft: 14, active: true });
    // Pro features work during the trial (branches is Growth+).
    await api().post(`${V}/branches`).set(auth(owner.token)).send({ name: 'Second', location: { lat: 28.62, lng: 77.21 }, radiusM: 100 }).expect(201);
  });

  it('one trial per owner: a later business shares the running trial, and starts on Free after it ended', async () => {
    const owner = await createOwner({ setup: { name: 'First' } });
    const firstEnds = (await User.findById(owner.userId).lean())!.trialEndsAt!;
    const body = { businessType: 'shop', location: { lat: 28.6, lng: 77.2 }, openingTime: '09:00', weeklyOff: [0] };
    const second = await api().post(`${V}/company`).set(auth(owner.token)).send({ name: 'Second', ...body }).expect(201);
    expect(second.body.data.company.subscription.status).toBe('trialing');
    expect(new Date(second.body.data.company.trial.endsAt).getTime()).toBe(firstEnds.getTime());
    // The owner's trial runs out; the third business starts on Free.
    await User.updateOne({ _id: owner.userId }, { trialEndsAt: new Date(Date.now() - DAY) });
    const third = await api().post(`${V}/company`).set(auth(second.body.data.accessToken)).send({ name: 'Third', ...body }).expect(201);
    expect(third.body.data.company).toMatchObject({ plan: { code: 'free' }, subscription: { status: 'free' }, trial: null });
  });

  it('owners from before this change: a past trial on a business they own counts', async () => {
    const owner = await createOwner();
    await User.updateOne({ _id: owner.userId }, { trialEndsAt: null });
    await Subscription.updateMany({ companyId: owner.companyId }, { trialEndsAt: new Date(Date.now() - 40 * DAY) });
    const r = await api()
      .post(`${V}/company`)
      .set(auth(owner.token))
      .send({ name: 'Later', businessType: 'shop', location: { lat: 28.6, lng: 77.2 }, openingTime: '09:00', weeklyOff: [0] })
      .expect(201);
    expect(r.body.data.company.plan.code).toBe('free');
  });

  it('reminds at 3 days and 1 day, then says what continues and what stops; data and staff stay', async () => {
    const { messaging } = await mocks();
    const owner = await createOwner({ setup: { name: 'Gupta Sweets' } });
    await User.updateOne({ _id: owner.userId }, { language: 'en' });
    for (let i = 0; i < 7; i++) await addEmployee(owner, { name: `Staff ${i}` });
    await api().patch(`${V}/company/settings`).set(auth(owner.token)).send({ faceMatchPolicy: 'review' }).expect(200);
    // Trial ends at 5 AM IST in 14 days, so 11 AM ticks fall 3 days and 1 day before it.
    const ends = new Date(daytime(14).getTime() - 6 * 3600_000);
    await Subscription.updateMany({ companyId: owner.companyId }, { trialEndsAt: ends });
    const messages = async () => (await Notification.find({ companyId: owner.companyId, channel: 'in_app', template: /^trial_/ }).sort({ createdAt: 1 }).lean()).map((n) => n.title);
    const tick = async (at: Date) => {
      await Company.updateMany({ _id: { $ne: owner.companyId } }, { deletedAt: new Date() }); // only this business
      await schedulerTick(at);
    };

    await tick(daytime(5));
    await tick(daytime(10));
    expect(await messages()).toEqual([]);
    await tick(daytime(11));
    await tick(new Date(daytime(11).getTime() + 60_000)); // not twice
    // Not at night.
    await tick(new Date(daytime(13).getTime() - 3 * 3600_000)); // 8 AM IST, 1 day left
    expect(await messages()).toEqual(['Gupta Sweets: 3 days of free trial left']);
    await tick(daytime(13));
    expect((await messages()).at(-1)).toBe('Gupta Sweets: free trial ends tomorrow');
    expect(messaging.outbox.filter((m) => m.template === 'trial_reminder').map((m) => m.params)).toEqual([
      ['Gupta Sweets', '3', expect.any(String)],
      ['Gupta Sweets', '1', expect.any(String)],
    ]);

    // After the end: one "trial ended" message, Free plan, face check off, staff kept.
    await tick(daytime(15));
    await tick(daytime(16));
    const all = await Notification.find({ companyId: owner.companyId, channel: 'in_app', template: 'trial_ended' }).lean();
    expect(all).toHaveLength(1);
    expect(all[0].body).toMatch(/Free plan now\. Attendance, leave and the daily summary keep working/);
    expect(all[0].body).toMatch(/Paused until you pick a plan: salary calculation, .*face check/);
    expect(messaging.outbox.filter((m) => m.template === 'trial_ended')).toHaveLength(1);
    const company = await Company.findById(owner.companyId).lean();
    expect(company!.settings!.faceMatchPolicy).toBe('off');
    await Company.updateMany({}, { deletedAt: null });
  });

  it('after the trial: Free, a "trial ended" banner, paid features locked, staff over the limit kept', async () => {
    const owner = await createOwner();
    for (let i = 0; i < 6; i++) await addEmployee(owner, { name: `Staff ${i}` });
    await Subscription.updateMany({ companyId: owner.companyId }, { trialEndsAt: new Date(Date.now() - DAY) });
    const me = await api().get(`${V}/me`).set(auth(owner.token)).expect(200);
    expect(me.body.data.company.plan.code).toBe('free');
    expect(me.body.data.company.trial).toMatchObject({ active: false, ended: true, daysLeft: 0 });
    const month = new Date().toISOString().slice(0, 7);
    const locked = await api().post(`${V}/payroll/runs`).set(auth(owner.token)).send({ month });
    expect(locked.body.error?.code).toBe('FEATURE_NOT_IN_PLAN');
    // All 6 staff are still there; adding a 7th is blocked by the Free limit.
    const list = await api().get(`${V}/employees`).set(auth(owner.token)).expect(200);
    expect(list.body.data.length).toBe(6);
    const more = await api().post(`${V}/employees`).set(auth(owner.token)).send({ name: 'Extra', phone: '9811122233', ratePaise: 1000000 });
    expect(more.status).toBeGreaterThanOrEqual(400);
    // Long after, the banner goes away.
    await Subscription.updateMany({ companyId: owner.companyId }, { trialEndsAt: new Date(Date.now() - 31 * DAY) });
    expect((await api().get(`${V}/me`).set(auth(owner.token))).body.data.company.trial).toBeNull();
  });

  it('admin can give a business (or every business of a phone) a fresh trial, or end it now', async () => {
    const owner = await createOwner();
    await Subscription.updateMany({ companyId: owner.companyId }, { trialEndsAt: new Date(Date.now() - 40 * DAY) });
    expect((await api().post(`${V}/admin/trials`).send({ companyId: owner.companyId })).status).toBe(401);
    const r = await api().post(`${V}/admin/trials`).set(admin).send({ phone: owner.phone }).expect(200);
    expect(r.body.data).toMatchObject([{ companyId: owner.companyId, planCode: 'pro' }]);
    let me = await api().get(`${V}/me`).set(auth(owner.token));
    expect(me.body.data.company).toMatchObject({ plan: { code: 'pro' }, trial: { daysLeft: 14, active: true } });
    // days: 0 ends it now (to see the "trial ended" screens).
    await api().post(`${V}/admin/trials`).set(admin).send({ companyId: owner.companyId, days: 0 }).expect(200);
    me = await api().get(`${V}/me`).set(auth(owner.token));
    expect(me.body.data.company).toMatchObject({ plan: { code: 'free' }, trial: { ended: true } });
    // A business on a paid plan is left alone; unknown plans and businesses are refused.
    const paid = await createOwner({ plan: 'growth' });
    const skip = await api().post(`${V}/admin/trials`).set(admin).send({ companyId: paid.companyId }).expect(200);
    expect(skip.body.data[0].skipped).toBe('paid_plan');
    expect((await api().post(`${V}/admin/trials`).set(admin).send({ companyId: owner.companyId, planCode: 'gold' })).status).toBe(400);
    expect((await api().post(`${V}/admin/trials`).set(admin).send({ phone: '9000000001' })).status).toBe(404);
    expect((await api().post(`${V}/admin/trials`).set(admin).send({ days: 14 })).status).toBe(400);
  });

  it('staff do not get a trial of their own until they start a business', async () => {
    const owner = await createOwner();
    const emp = await addEmployee(owner, { name: 'Suresh' });
    const login = await otpLogin(emp.phone);
    expect((await User.findById(login.user.id).lean())!.trialEndsAt).toBeNull();
  });
});
