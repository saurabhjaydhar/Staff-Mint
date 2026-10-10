import { describe, expect, it } from 'vitest';
import { api, auth, V, createOwner, addEmployee, otpLogin, setPlan, mocks } from './helpers.js';
import { Membership, PayrollRun, User } from '../src/models/index.js';

const phoneOf = async (userId: string) => (await User.findById(userId).lean())!.phone.replace('+91', '');

describe('F14 Phase 4: scale', () => {
  it('accounts can be pinned; accountants see all clients with last month’s payroll', async () => {
    const ca = await createOwner({ setup: { name: 'Own Practice' } });
    const caPhone = await phoneOf(ca.userId);
    const clients = [];
    for (const name of ['Zeta Foods', 'Alpha Medical', 'Beta Salon']) {
      const c = await createOwner({ plan: 'pro', setup: { name } });
      await api().post(`${V}/company/accountants`).set(auth(c.token)).send({ phone: caPhone, name: 'CA' }).expect(201);
      clients.push(c);
    }
    const month = new Date(new Date().getFullYear(), new Date().getMonth() - 1, 15).toISOString().slice(0, 7);
    await PayrollRun.create({ companyId: clients[1].companyId, month, status: 'approved', engineVersion: 'test', totals: { netPaise: 5000000 } });
    const login = await otpLogin(caPhone);
    const zeta = login.memberships.find((m: any) => m.companyName === 'Zeta Foods');
    await api().patch(`${V}/me/accounts/${zeta.id}`).set(auth(login.accessToken)).send({ pinned: true }).expect(200);
    const me = await api().get(`${V}/me`).set(auth(login.accessToken)).expect(200);
    expect(me.body.data.memberships.find((m: any) => m.id === zeta.id).pinned).toBe(true);
    const list = await api().get(`${V}/me/clients`).set(auth(login.accessToken)).expect(200);
    // Pinned first, then by name; only CA accounts.
    expect(list.body.data.map((c: any) => c.companyName)).toEqual(['Zeta Foods', 'Alpha Medical', 'Beta Salon']);
    expect(list.body.data[1]).toMatchObject({ month, payrollStatus: 'approved', netPaise: 5000000 });
    expect(list.body.data[2]).toMatchObject({ payrollStatus: 'not_started' });
    // Someone else's account cannot be pinned.
    const other = await Membership.findOne({ userId: clients[0].userId }).lean();
    expect((await api().patch(`${V}/me/accounts/${other!._id}`).set(auth(login.accessToken)).send({ pinned: true })).status).toBe(404);
  });

  it('WhatsApp asks "Which business?" for a number with several, remembers it, and can switch', async () => {
    const { messaging } = await mocks();
    const a = await createOwner({ setup: { name: 'Gupta Sweets' } });
    const b = await createOwner({ setup: { name: 'Sharma Medical' } });
    await setPlan(a.companyId, 'growth');
    await setPlan(b.companyId, 'growth');
    const phone = await phoneOf(a.userId);
    await api().post(`${V}/company/owners`).set(auth(b.token)).send({ phone, name: 'Partner' }).expect(201);
    await addEmployee(b, { name: 'Suresh Yadav' });
    await User.updateOne({ _id: a.userId }, { language: 'en' });
    messaging.outbox.length = 0;
    const send = (body: Record<string, unknown>) => api().post(`${V}/webhooks/messaging/mock`).send({ from: `+91${phone}`, id: `wamid.${Math.random()}`, ...body }).expect(200);
    const wait = async (n: number) => {
      for (let i = 0; i < 60 && messaging.outbox.length < n; i++) await new Promise((r) => setTimeout(r, 20));
    };
    await send({ text: 'Suresh aaj nahi aaya' });
    await wait(1);
    expect(messaging.outbox[0]).toMatchObject({ kind: 'buttons' });
    expect(messaging.outbox[0].buttons!.map((x) => x.title).sort()).toEqual(['Gupta Sweets', 'Sharma Medical']);
    // Picking a business runs the message that was waiting, labelled with the business.
    await send({ buttonId: `biz:${b.companyId}` });
    await wait(3);
    expect(messaging.outbox[1].text).toMatch(/Now using Sharma Medical/);
    expect(messaging.outbox[2].text).toMatch(/^\*Sharma Medical\* · /);
    expect(String((await User.findById(a.userId).lean())!.whatsappCompanyId)).toBe(b.companyId);
    // "switch to gupta" changes it without asking.
    await send({ text: 'switch to gupta' });
    await wait(4);
    expect(messaging.outbox[3].text).toMatch(/Now using Gupta Sweets/);
    // "switch" alone asks again; a number reply picks from the list.
    await send({ text: 'switch' });
    await wait(5);
    expect(messaging.outbox[4].kind).toBe('buttons');
    const order = messaging.outbox[4].buttons!.map((x) => x.title);
    await send({ text: String(order.indexOf('Sharma Medical') + 1) });
    await wait(6);
    expect(messaging.outbox[5].text).toMatch(/Now using Sharma Medical/);
  });

  it('one bill for several businesses: the payer’s plan covers them, staff and price add up', async () => {
    const owner = await createOwner({ setup: { name: 'Main Shop' } });
    await setPlan(owner.companyId, 'growth');
    const second = await api()
      .post(`${V}/company`)
      .set(auth(owner.token))
      .send({ name: 'Second Shop', businessType: 'shop', location: { lat: 28.6, lng: 77.2 }, openingTime: '09:00', weeklyOff: [0] })
      .expect(201);
    const secondId = second.body.data.company.id;
    const secondToken = second.body.data.accessToken;
    // The owner's phone is now in Second Shop; act on the payer with its own session.
    const mainLogin = await otpLogin(owner.phone, 'main-dev');
    const mainM = mainLogin.memberships.find((m: any) => m.companyId === owner.companyId);
    const main = (await api().post(`${V}/auth/switch`).set(auth(mainLogin.accessToken)).send({ membershipId: mainM.id, deviceId: 'main-dev' }).expect(200)).body.data;
    let g = await api().get(`${V}/billing/group`).set(auth(main.accessToken)).expect(200);
    expect(g.body.data).toMatchObject({ isPayer: true, members: [], candidates: [{ companyId: secondId, name: 'Second Shop' }] });
    // Second Shop is on its own free trial; it can join.
    g = await api().post(`${V}/billing/group/members`).set(auth(main.accessToken)).send({ companyId: secondId }).expect(200);
    expect(g.body.data.members).toMatchObject([{ companyId: secondId }]);
    // Second Shop now uses the payer's plan and cannot subscribe on its own.
    const sum = await api().get(`${V}/billing/subscription`).set(auth(secondToken)).expect(200);
    expect(sum.body.data).toMatchObject({ plan: { code: 'growth' }, billedTo: { companyId: owner.companyId, name: 'Main Shop' } });
    const own = await api().post(`${V}/billing/subscribe`).set(auth(secondToken)).send({ planCode: 'growth' });
    expect(own.body.error.details.reason).toBe('billed_elsewhere');
    // Staff across both count together.
    await addEmployee(owner, { name: 'A' });
    await api().post(`${V}/employees`).set(auth(secondToken)).send({ name: 'B', phone: '9812345670', ratePaise: 1000000 }).expect(201);
    expect((await api().get(`${V}/billing/group`).set(auth(main.accessToken))).body.data.totalStaff).toBe(2);
    // The subscription price includes the extra business.
    const priced = await api().post(`${V}/billing/subscribe`).set(auth(main.accessToken)).send({ planCode: 'growth' }).expect(200);
    const base = (await api().get(`${V}/billing/plans`)).body.data.find((p: any) => p.code === 'growth').priceMonthlyPaise;
    expect(priced.body.data.amountPaise).toBe(base + 19900);
    // Taking it off the bill returns it to its own plan.
    await api().delete(`${V}/billing/group/members/${secondId}`).set(auth(main.accessToken)).expect(200);
    expect((await api().get(`${V}/billing/subscription`).set(auth(secondToken))).body.data.billedTo).toBeNull();
    // Someone else's business cannot be added.
    const stranger = await createOwner();
    expect((await api().post(`${V}/billing/group/members`).set(auth(main.accessToken)).send({ companyId: stranger.companyId })).status).toBe(403);
  });
});
