import { describe, expect, it } from 'vitest';
import { api, auth, V, createOwner, addEmployee, otpLogin, nextPhone } from './helpers.js';
import { Employee, Membership, User } from '../src/models/index.js';
import { normalizePhone } from '../src/lib/phone.js';

describe('staff numbers never land in "create your business"', () => {
  it('a number that opened the app before being added becomes staff when the owner adds it', async () => {
    const owner = await createOwner();
    const phone = nextPhone();
    const early = await otpLogin(phone);
    expect(early.res.body.data).toMatchObject({ needsCompanySetup: true, user: { role: 'owner', companyId: null } });

    const emp = await addEmployee(owner, { phone, name: 'Suresh Yadav' });
    const login = await User.findOne({ phone: normalizePhone(phone) }).lean();
    expect(login).toMatchObject({ role: 'employee', employeeId: expect.anything() });
    expect(String(login!.companyId)).toBe(owner.companyId);

    const again = await otpLogin(phone);
    expect(again.res.body.data).toMatchObject({ needsCompanySetup: false, user: { role: 'employee', employeeId: emp.id, name: 'Suresh Yadav' } });
    // The phone that first logs in as staff is the bound one.
    expect((await Membership.findOne({ companyId: owner.companyId, employeeId: emp.id }).lean())!.deviceIds).toEqual([again.deviceId]);
  });

  it('older data (added before this fix) is repaired at login, and on "check again" (token refresh)', async () => {
    const owner = await createOwner();
    // Login exists first, staff record added without linking (old behaviour).
    const p1 = nextPhone();
    await otpLogin(p1);
    await Employee.create({ companyId: owner.companyId, name: 'Amit', phone: normalizePhone(p1)! });
    const r1 = await otpLogin(p1);
    expect(r1.res.body.data).toMatchObject({ needsCompanySetup: false, user: { role: 'employee' } });

    const p2 = nextPhone();
    const waiting = await otpLogin(p2);
    await Employee.create({ companyId: owner.companyId, name: 'Raju', phone: normalizePhone(p2)! });
    const refreshed = await api().post(`${V}/auth/refresh`).send({ refreshToken: waiting.refreshToken }).expect(200);
    const me = await api().get(`${V}/me`).set(auth(refreshed.body.data.accessToken)).expect(200);
    expect(me.body.data).toMatchObject({ user: { role: 'employee' }, employee: { name: 'Raju' }, company: { id: owner.companyId } });
  });

  it("refuses only this business's own owner number; people from other businesses get one more account", async () => {
    const owner = await createOwner();
    const other = await createOwner();
    const ownPhone = (await User.findById(owner.userId).lean())!.phone;
    let r = await api().post(`${V}/employees`).set(auth(owner.token)).send({ name: 'Me', phone: ownPhone });
    expect(r.status).toBe(409);
    expect(r.body.error.details.reason).toBe('owner_number');

    // Another business's owner can be staff here too.
    const otherOwnerPhone = (await User.findById(other.userId).lean())!.phone;
    r = await api().post(`${V}/employees`).set(auth(owner.token)).send({ name: 'Mohan', phone: otherOwnerPhone });
    expect(r.status).toBe(201);
    expect(await Membership.countDocuments({ userId: other.userId, status: 'active' })).toBe(2);
    // Their own session stays in their own business.
    const me = await api().get(`${V}/me`).set(auth(other.token)).expect(200);
    expect(me.body.data).toMatchObject({ user: { role: 'owner' }, company: { id: other.companyId } });
  });

  it('changing a staff phone to a number that is waiting links that login', async () => {
    const owner = await createOwner();
    const emp = await addEmployee(owner, { phone: nextPhone(), name: 'Kamal' });
    const fresh = nextPhone();
    await otpLogin(fresh);
    await api().patch(`${V}/employees/${emp.id}`).set(auth(owner.token)).send({ phone: fresh }).expect(200);
    const r = await otpLogin(fresh);
    expect(r.res.body.data).toMatchObject({ needsCompanySetup: false, user: { role: 'employee', employeeId: emp.id } });
  });
});
