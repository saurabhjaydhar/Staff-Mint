import { describe, expect, it } from 'vitest';
import { api, auth, V, createOwner, addEmployee, otpLogin, nextPhone, punchBody } from './helpers.js';
import { Membership, User } from '../src/models/index.js';

const setup = (name: string, extra: Record<string, unknown> = {}) => ({ name, businessType: 'shop', location: { lat: 28.6139, lng: 77.209 }, openingTime: '09:00', weeklyOff: [0], ...extra });

/** Phone number (without +91) of a session's user. */
const phoneOf = async (userId: string) => (await User.findById(userId).lean())!.phone.replace('+91', '');

describe('one number, many businesses', () => {
  it('an owner who is also staff elsewhere chooses after login and switches any time', async () => {
    const a = await createOwner();
    const b = await createOwner();
    const phone = await phoneOf(a.userId);
    const emp = await addEmployee(b, { phone, name: 'Asha' });

    const login = await otpLogin(phone, 'phone-1');
    expect(login.res.status).toBe(200);
    expect(login.needsAccountChoice).toBe(true);
    expect(login.memberships).toHaveLength(2);
    expect(login.memberships.map((m: any) => m.role).sort()).toEqual(['employee', 'owner']);
    const staff = login.memberships.find((m: any) => m.role === 'employee');
    expect(staff.companyName).toBe('Test Shop');

    const sw = await api().post(`${V}/auth/switch`).set(auth(login.accessToken)).send({ membershipId: staff.id, deviceId: 'phone-1', refreshToken: login.refreshToken });
    expect(sw.status).toBe(200);
    expect(sw.body.data).toMatchObject({ activeMembershipId: staff.id, needsCompanySetup: false });
    const me = await api().get(`${V}/me`).set(auth(sw.body.data.accessToken)).expect(200);
    expect(me.body.data).toMatchObject({ user: { role: 'employee', employeeId: emp.id, companyId: b.companyId }, employee: { id: emp.id }, activeMembershipId: staff.id });
    // Staff access only: the owner screens of business B stay closed.
    expect((await api().get(`${V}/employees`).set(auth(sw.body.data.accessToken))).status).toBe(403);
    // The token used to switch was retired.
    await api().post(`${V}/auth/refresh`).send({ refreshToken: login.refreshToken }).expect(401);
    // The owner session on another device is untouched by the switch.
    const ownerMe = await api().get(`${V}/me`).set(auth(a.token)).expect(200);
    expect(ownerMe.body.data).toMatchObject({ user: { role: 'owner' }, company: { id: a.companyId } });

    // Refresh keeps the device in the business it switched to.
    const r = await api().post(`${V}/auth/refresh`).send({ refreshToken: sw.body.data.refreshToken }).expect(200);
    const me2 = await api().get(`${V}/me`).set(auth(r.body.data.accessToken)).expect(200);
    expect(me2.body.data.company.id).toBe(b.companyId);

    // The next login opens the most recently used account.
    const again = await otpLogin(phone, 'phone-1');
    expect(again.activeMembershipId).toBe(staff.id);
  });

  it('staff can create their own business from the staff account', async () => {
    const owner = await createOwner();
    const phone = nextPhone();
    const emp = await addEmployee(owner, { phone, name: 'Ravi' });
    const login = await otpLogin(phone, 'phone-ravi');
    expect(login).toMatchObject({ needsAccountChoice: false, user: { role: 'employee' } });

    const r = await api().post(`${V}/company`).set(auth(login.accessToken)).send(setup('Ravi Tea Stall', { deviceId: 'phone-ravi', refreshToken: login.refreshToken }));
    expect(r.status).toBe(201);
    expect(r.body.data.memberships).toHaveLength(2);
    const me = await api().get(`${V}/me`).set(auth(r.body.data.accessToken)).expect(200);
    expect(me.body.data).toMatchObject({ user: { role: 'owner' }, company: { name: 'Ravi Tea Stall' }, employee: null });
    expect((await api().get(`${V}/employees`).set(auth(r.body.data.accessToken))).status).toBe(200);

    // Switching back to the staff account works on the bound phone and keeps the staff record.
    const staff = r.body.data.memberships.find((m: any) => m.role === 'employee');
    const back = await api().post(`${V}/auth/switch`).set(auth(r.body.data.accessToken)).send({ membershipId: staff.id, deviceId: 'phone-ravi' }).expect(200);
    const me2 = await api().get(`${V}/me`).set(auth(back.body.data.accessToken)).expect(200);
    expect(me2.body.data.employee.id).toBe(emp.id);
    // The owner still sees Ravi as staff.
    const list = await api().get(`${V}/employees`).set(auth(owner.token)).expect(200);
    expect(list.body.data.find((e: any) => e.id === emp.id)).toMatchObject({ hasDevice: true });
  });

  it('phone binding is per business: a staff account is locked to its phone, the person’s own business is not', async () => {
    const shop = await createOwner();
    const phone = nextPhone();
    const emp = await addEmployee(shop, { phone });
    const first = await otpLogin(phone, 'phone-old');
    const own = await api().post(`${V}/company`).set(auth(first.accessToken)).send(setup('Own Shop', { deviceId: 'phone-old' })).expect(201);
    const staffId = own.body.data.memberships.find((m: any) => m.role === 'employee').id;

    // New phone: login opens the business it may use, the staff account stays locked.
    const second = await otpLogin(phone, 'phone-new');
    expect(second.res.status).toBe(200);
    expect(second.memberships).toHaveLength(2);
    expect(second.activeMembershipId).not.toBe(staffId);
    const blocked = await api().post(`${V}/auth/switch`).set(auth(second.accessToken)).send({ membershipId: staffId, deviceId: 'phone-new' });
    expect(blocked.body.error.code).toBe('DEVICE_NOT_BOUND');

    // Check-in from the wrong phone is refused even with a staff token.
    const staffOld = await api().post(`${V}/auth/switch`).set(auth(own.body.data.accessToken)).send({ membershipId: staffId, deviceId: 'phone-old' }).expect(200);
    await api().post(`${V}/me/consent`).set(auth(staffOld.body.data.accessToken)).send({ location: true }).expect(200);
    const wrong = await api().post(`${V}/attendance/check-in`).set(auth(staffOld.body.data.accessToken)).send(punchBody('phone-new'));
    expect(wrong.body.error.code).toBe('DEVICE_NOT_BOUND');

    // The owner resets the device: only that business's binding is cleared.
    await api().post(`${V}/employees/${emp.id}/reset-device`).set(auth(shop.token)).expect(200);
    await api().get(`${V}/me`).set(auth(staffOld.body.data.accessToken)).expect(200); // access token still valid until expiry
    await api().post(`${V}/auth/refresh`).send({ refreshToken: staffOld.body.data.refreshToken }).expect(401); // session ended
    const ok = await api().post(`${V}/auth/switch`).set(auth(second.accessToken)).send({ membershipId: staffId, deviceId: 'phone-new' });
    expect(ok.status).toBe(200);
    expect((await Membership.findById(staffId).lean())!.deviceIds).toEqual(['phone-new']);
  });

  it('removing staff ends that business only; the person keeps their other accounts', async () => {
    const a = await createOwner();
    const b = await createOwner();
    const phone = await phoneOf(a.userId);
    const emp = await addEmployee(b, { phone });
    const login = await otpLogin(phone, 'phone-x');
    const staff = login.memberships.find((m: any) => m.role === 'employee');
    const sw = await api().post(`${V}/auth/switch`).set(auth(login.accessToken)).send({ membershipId: staff.id, deviceId: 'phone-x' }).expect(200);

    await api().post(`${V}/employees/${emp.id}/deactivate`).set(auth(b.token)).send({}).expect(200);
    const gone = await api().get(`${V}/me`).set(auth(sw.body.data.accessToken));
    expect(gone.status).toBe(401);
    await api().get(`${V}/me`).set(auth(a.token)).expect(200);
    const again = await otpLogin(phone, 'phone-x');
    expect(again).toMatchObject({ needsAccountChoice: false, user: { role: 'owner', companyId: a.companyId } });
    expect(again.memberships).toHaveLength(1);

    // Reactivating brings the account back.
    await api().post(`${V}/employees/${emp.id}/reactivate`).set(auth(b.token)).send({}).expect(200);
    const back = await otpLogin(phone, 'phone-x');
    expect(back.memberships).toHaveLength(2);
  });

  it('promoting staff to manager updates that business only and ends its sessions', async () => {
    const owner = await createOwner();
    const phone = nextPhone();
    const emp = await addEmployee(owner, { phone });
    const login = await otpLogin(phone, 'phone-m');
    await api().post(`${V}/employees/${emp.id}/role`).set(auth(owner.token)).send({ role: 'manager' }).expect(200);
    await api().post(`${V}/auth/refresh`).send({ refreshToken: login.refreshToken }).expect(401);
    const again = await otpLogin(phone, 'phone-m');
    expect(again.user.role).toBe('manager');
    expect((await api().get(`${V}/employees`).set(auth(again.accessToken))).status).toBe(200);
  });

  it('an existing user can be added as accountant and gets one more account', async () => {
    const client = await createOwner({ plan: 'pro' });
    const ca = await createOwner();
    const phone = await phoneOf(ca.userId);
    const r = await api().post(`${V}/company/accountants`).set(auth(client.token)).send({ phone, name: 'CA Gupta' });
    expect(r.status).toBe(201);
    const dup = await api().post(`${V}/company/accountants`).set(auth(client.token)).send({ phone, name: 'CA Gupta' });
    expect(dup.status).toBe(409);
    const login = await otpLogin(phone);
    expect(login.memberships.map((m: any) => m.role).sort()).toEqual(['ca', 'owner']);
    // The accountant's number can't be added as this business's staff.
    const staff = await api().post(`${V}/employees`).set(auth(client.token)).send({ name: 'X Y', phone });
    expect(staff.body.error.details.reason).toBe('accountant_number');
  });

  it('cannot switch into someone else’s account, and caps owned businesses', async () => {
    const a = await createOwner();
    const b = await createOwner();
    const theirs = await Membership.findOne({ userId: b.userId }).lean();
    const r = await api().post(`${V}/auth/switch`).set(auth(a.token)).send({ membershipId: String(theirs!._id), deviceId: 'dev-1234' });
    expect(r.status).toBe(404);
    expect((await api().post(`${V}/auth/switch`).set(auth(a.token)).send({ membershipId: 'not-an-id', deviceId: 'dev-1234' })).status).toBe(400);

    const fake = Array.from({ length: 9 }, () => ({ userId: a.userId, companyId: theirs!.companyId, role: 'owner' }));
    // Unique (user, business): spread the fakes over fresh ids.
    const { Types } = await import('mongoose');
    await Membership.insertMany(fake.map((m) => ({ ...m, companyId: new Types.ObjectId() })));
    const over = await api().post(`${V}/company`).set(auth(a.token)).send(setup('Eleventh'));
    expect(over.status).toBe(409);
  });

  it('sessions made before memberships keep working and get a membership on refresh', async () => {
    const owner = await createOwner();
    await Membership.deleteMany({ userId: owner.userId });
    const r = await api().post(`${V}/auth/refresh`).send({ refreshToken: owner.refreshToken }).expect(200);
    const me = await api().get(`${V}/me`).set(auth(r.body.data.accessToken)).expect(200);
    expect(me.body.data).toMatchObject({ user: { role: 'owner' }, company: { id: owner.companyId } });
    expect(me.body.data.memberships).toHaveLength(1);
  });
});
