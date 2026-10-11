import { describe, expect, it } from 'vitest';
import { api, auth, V, nextPhone, otpLogin, createOwner, addEmployee, employeeSession } from './helpers.js';
import { OtpRequest, Membership } from '../src/models/index.js';

describe('auth', () => {
  it('OTP login creates an owner who must set up a company', async () => {
    const phone = nextPhone();
    const r = await otpLogin(phone);
    expect(r.res.status).toBe(200);
    expect(r.needsCompanySetup).toBe(true);
    expect(r.user).toMatchObject({ role: 'owner', companyId: null, phone: `+91${phone}` });
    const me = await api().get(`${V}/me`).set(auth(r.accessToken));
    expect(me.body.data.company).toBeNull();
    const blocked = await api().get(`${V}/employees`).set(auth(r.accessToken));
    expect(blocked.body.error.code).toBe('COMPANY_SETUP_REQUIRED');
  });

  it('rejects wrong OTP and locks after 5 attempts', async () => {
    const phone = nextPhone();
    await api().post(`${V}/auth/otp/request`).send({ phone });
    for (let i = 0; i < 5; i++) {
      const r = await api().post(`${V}/auth/otp/verify`).send({ phone, code: '000000', deviceId: 'dev-1234' });
      expect(r.body.error.code).toBe('OTP_INVALID');
    }
    const r = await api().post(`${V}/auth/otp/verify`).send({ phone, code: '123456', deviceId: 'dev-1234' });
    expect(r.body.error.code).toBe('RATE_LIMITED');
  });

  it('throttles OTP requests', async () => {
    const phone = nextPhone();
    expect((await api().post(`${V}/auth/otp/request`).send({ phone })).status).toBe(200);
    const again = await api().post(`${V}/auth/otp/request`).send({ phone });
    expect(again.status).toBe(429);
  });

  it('stores only a hash of the OTP', async () => {
    const phone = nextPhone();
    await api().post(`${V}/auth/otp/request`).send({ phone });
    const doc = await OtpRequest.findOne({ phone: `+91${phone}` }).lean();
    expect(doc!.codeHash).not.toContain('123456');
  });

  it('rotates refresh tokens and revokes the family on reuse', async () => {
    const owner = await createOwner();
    const r1 = await api().post(`${V}/auth/refresh`).send({ refreshToken: owner.refreshToken });
    expect(r1.status).toBe(200);
    const r2 = await api().post(`${V}/auth/refresh`).send({ refreshToken: r1.body.data.refreshToken });
    expect(r2.status).toBe(200);
    // Reusing the first (rotated) token kills the family, including the latest token.
    expect((await api().post(`${V}/auth/refresh`).send({ refreshToken: owner.refreshToken })).status).toBe(401);
    expect((await api().post(`${V}/auth/refresh`).send({ refreshToken: r2.body.data.refreshToken })).status).toBe(401);
  });

  it('rejects invalid and missing access tokens', async () => {
    expect((await api().get(`${V}/me`)).status).toBe(401);
    expect((await api().get(`${V}/me`).set(auth('garbage'))).body.error.code).toBe('UNAUTHORIZED');
  });

  it('employee phone logs in as employee, binds device, blocks other devices until reset', async () => {
    const owner = await createOwner();
    const phone = nextPhone();
    const emp = await addEmployee(owner, { phone, name: 'Suresh' });
    const s = await employeeSession(phone, 'device-A-1');
    expect(s.user).toMatchObject({ role: 'employee', employeeId: emp.id, companyId: owner.companyId });
    // Another phone gets in, but with no business open: the staff account is offered as "locked to another phone".
    const other = await otpLogin(phone, 'device-B-1');
    expect(other).toMatchObject({ needsCompanySetup: true, activeMembershipId: null });
    expect(other.blockedAccounts).toHaveLength(1);
    // Web login never binds/blocks
    const web = await otpLogin(phone, 'web-abc123');
    expect(web.res.status).toBe(200);
    await api().post(`${V}/employees/${emp.id}/reset-device`).set(auth(owner.token)).expect(200);
    const again = await otpLogin(phone, 'device-B-1');
    expect(again.res.status).toBe(200);
    const m = await Membership.findOne({ companyId: owner.companyId, employeeId: emp.id }).lean();
    expect(m!.deviceIds).toEqual(['device-B-1']);
  });

  it('deactivated staff lose the business at once, and log in with no business', async () => {
    const owner = await createOwner();
    const phone = nextPhone();
    const emp = await addEmployee(owner, { phone });
    const s = await employeeSession(phone, 'device-A-1');
    await api().post(`${V}/employees/${emp.id}/deactivate`).set(auth(owner.token)).send({}).expect(200);
    const old = await api().get(`${V}/me`).set(auth(s.token));
    expect(old.status).toBe(401);
    const r = await otpLogin(phone, 'device-A-1');
    expect(r.res.status).toBe(200);
    expect(r).toMatchObject({ needsCompanySetup: true, memberships: [], user: { companyId: null } });
  });
});

describe('company setup', () => {
  it('creates company with defaults, branch, shift, holidays and a trial', async () => {
    const owner = await createOwner();
    const c = await api().get(`${V}/company`).set(auth(owner.token));
    expect(c.body.data.settings).toMatchObject({ graceMinutes: 15, halfDayHours: 4, monthDivisor: 'days_in_month', missingCheckoutPolicy: 'half_day' });
    expect(c.body.data.subscription.status).toBe('trialing');
    expect(c.body.data.plan.code).toBe('pro');
    const b = await api().get(`${V}/branches`).set(auth(owner.token));
    expect(b.body.data[0]).toMatchObject({ radiusM: 100, location: { lat: 28.6139, lng: 77.209 } });
    const h = await api().get(`${V}/holidays?year=2026`).set(auth(owner.token));
    expect(h.body.data.length).toBeGreaterThan(5);
    const rules = await api().get(`${V}/company/rules`).set(auth(owner.token)).set('Accept-Language', 'hi');
    expect(rules.body.data.rules.length).toBe(9);
    const s = await api().patch(`${V}/company/settings`).set(auth(owner.token)).send({ graceMinutes: 10, monthDivisor: '26' });
    expect(s.body.data.settings).toMatchObject({ graceMinutes: 10, monthDivisor: '26' });
    const bad = await api().patch(`${V}/company/settings`).set(auth(owner.token)).send({ unknownSetting: 1 });
    expect(bad.status).toBe(400);
  });

  it('an owner can add a second business; this device moves into it', async () => {
    const owner = await createOwner();
    const r = await api()
      .post(`${V}/company`)
      .set(auth(owner.token))
      .send({ name: 'Second Shop', businessType: 'shop', location: { lat: 1, lng: 1 }, openingTime: '09:00', weeklyOff: [0], refreshToken: owner.refreshToken });
    expect(r.status).toBe(201);
    expect(r.body.data.memberships).toHaveLength(2);
    const me = await api().get(`${V}/me`).set(auth(r.body.data.accessToken)).expect(200);
    expect(me.body.data.company.name).toBe('Second Shop');
    // The old session token was retired; the first business is still one switch away.
    await api().post(`${V}/auth/refresh`).send({ refreshToken: owner.refreshToken }).expect(401);
    expect(me.body.data.memberships.map((m: any) => m.companyName).sort()).toEqual(['Second Shop', 'Test Shop']);
  });
});
