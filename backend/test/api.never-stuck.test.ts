import { describe, expect, it } from 'vitest';
import { api, auth, V, createOwner, addEmployee, otpLogin, nextPhone, mocks } from './helpers.js';
import { Company, Membership, Notification, User } from '../src/models/index.js';

const phoneOf = async (userId: string) => (await User.findById(userId).lean())!.phone.replace('+91', '');

/** Owner of "Test Shop" (A) who is also staff at "Gupta Sweets" (B), with this device open in B. */
async function ownerAlsoStaff() {
  const a = await createOwner();
  const b = await createOwner({ setup: { name: 'Gupta Sweets' } });
  const phone = await phoneOf(a.userId);
  const emp = await addEmployee(b, { phone });
  const login = await otpLogin(phone, 'phone-1');
  const staff = login.memberships.find((m: any) => m.role === 'employee');
  const sw = await api().post(`${V}/auth/switch`).set(auth(login.accessToken)).send({ membershipId: staff.id, deviceId: 'phone-1', refreshToken: login.refreshToken }).expect(200);
  return { a, b, phone, emp, staff, session: sw.body.data };
}

describe('F14 never stuck', () => {
  it('soft landing: removed from one shop, the phone moves to the next account with a reason', async () => {
    const { a, b, emp, session } = await ownerAlsoStaff();
    await api().post(`${V}/employees/${emp.id}/deactivate`).set(auth(b.token)).send({}).expect(200);
    const stale = await api().get(`${V}/me`).set(auth(session.accessToken));
    expect(stale.status).toBe(401);
    expect(stale.body.error).toMatchObject({ code: 'TOKEN_EXPIRED', details: { reason: 'account_changed' } });
    const r = await api().post(`${V}/auth/refresh`).send({ refreshToken: session.refreshToken }).expect(200);
    expect(r.body.data.accountChange).toMatchObject({ kind: 'ended', reason: 'removed', companyName: 'Gupta Sweets', role: 'owner' });
    const me = await api().get(`${V}/me`).set(auth(r.body.data.accessToken)).expect(200);
    expect(me.body.data.company.id).toBe(a.companyId);
  });

  it('removed from the only business: a notice says so until dismissed', async () => {
    const owner = await createOwner({ setup: { name: 'Gupta Sweets' } });
    const phone = nextPhone();
    const emp = await addEmployee(owner, { phone });
    const login = await otpLogin(phone, 'phone-2');
    await api().post(`${V}/employees/${emp.id}/deactivate`).set(auth(owner.token)).send({}).expect(200);
    const r = await api().post(`${V}/auth/refresh`).send({ refreshToken: login.refreshToken }).expect(200);
    expect(r.body.data.accountChange).toMatchObject({ kind: 'ended', role: null, activeMembershipId: null });
    const me = await api().get(`${V}/me`).set(auth(r.body.data.accessToken)).expect(200);
    expect(me.body.data.company).toBeNull();
    expect(me.body.data.endedNotices).toHaveLength(1);
    expect(me.body.data.endedNotices[0]).toMatchObject({ companyName: 'Gupta Sweets', endedReason: 'removed' });
    await api().post(`${V}/me/notices/${me.body.data.endedNotices[0].id}/dismiss`).set(auth(r.body.data.accessToken)).expect(200);
    const after = await api().get(`${V}/me`).set(auth(r.body.data.accessToken)).expect(200);
    expect(after.body.data.endedNotices).toHaveLength(0);
  });

  it('staff can leave a business; the owner is told; they stay out until re-invited', async () => {
    await mocks();
    const { a, b, emp, staff, session, phone } = await ownerAlsoStaff();
    const left = await api().post(`${V}/me/accounts/${staff.id}/leave`).set(auth(session.accessToken)).send({ deviceId: 'phone-1', refreshToken: session.refreshToken }).expect(200);
    expect(left.body.data).toMatchObject({ activeMembershipId: expect.any(String), user: { role: 'owner', companyId: a.companyId } });
    expect(left.body.data.memberships).toHaveLength(1);
    expect(await Notification.exists({ companyId: b.companyId, template: 'member_left' })).toBeTruthy();
    // Logging in again does not pull them back in.
    const again = await otpLogin(phone, 'phone-1');
    expect(again.memberships).toHaveLength(1);
    // Owner re-invites: they are back.
    await api().post(`${V}/employees/${emp.id}/invite`).set(auth(b.token)).expect(200);
    const back = await otpLogin(phone, 'phone-1');
    expect(back.memberships).toHaveLength(2);
    // Owners cannot leave their own business.
    const own = back.memberships.find((m: any) => m.role === 'owner');
    const r = await api().post(`${V}/me/accounts/${own.id}/leave`).set(auth(back.accessToken)).send({ deviceId: 'phone-1' });
    expect(r.status).toBe(409);
  });

  it('owner closes a business and can restore it within the window', async () => {
    await mocks();
    const owner = await createOwner({ setup: { name: 'Gupta Sweets' } });
    const phone = nextPhone();
    await addEmployee(owner, { phone });
    const staff = await otpLogin(phone, 'phone-3');
    const wrong = await api().post(`${V}/company/close`).set(auth(owner.token)).send({ confirmName: 'Wrong', deviceId: 'owner-dev' });
    expect(wrong.status).toBe(400);
    const closed = await api().post(`${V}/company/close`).set(auth(owner.token)).send({ confirmName: 'gupta sweets', deviceId: 'owner-dev', refreshToken: owner.refreshToken }).expect(200);
    expect(closed.body.data).toMatchObject({ activeMembershipId: null, needsCompanySetup: true });
    expect((await Company.findById(owner.companyId).lean())!.deletedAt).not.toBeNull();
    // Staff hear about it and land with no business.
    expect(await Notification.exists({ companyId: owner.companyId, template: 'business_closed' })).toBeTruthy();
    const r = await api().post(`${V}/auth/refresh`).send({ refreshToken: staff.refreshToken }).expect(200);
    expect(r.body.data.accountChange).toMatchObject({ kind: 'ended', reason: 'closed' });
    // Staff records of a closed business do not re-attach at login.
    expect((await otpLogin(phone, 'phone-3')).memberships).toHaveLength(0);
    // Owner sees it as restorable and restores it.
    const me = await api().get(`${V}/me`).set(auth(closed.body.data.accessToken)).expect(200);
    expect(me.body.data.closedBusinesses).toMatchObject([{ companyId: owner.companyId, companyName: 'Gupta Sweets' }]);
    const restored = await api().post(`${V}/me/businesses/${owner.companyId}/restore`).set(auth(closed.body.data.accessToken)).send({ deviceId: 'owner-dev' }).expect(200);
    expect(restored.body.data.user).toMatchObject({ role: 'owner', companyId: owner.companyId });
    expect((await otpLogin(phone, 'phone-3')).memberships).toHaveLength(1);
    // Only the main owner can close.
    const other = await createOwner();
    await Membership.create({ userId: other.userId, companyId: owner.companyId, role: 'owner' });
    const sw = await otpLogin(await phoneOf(other.userId));
    const co = sw.memberships.find((m: any) => m.companyId === owner.companyId);
    const coSession = await api().post(`${V}/auth/switch`).set(auth(sw.accessToken)).send({ membershipId: co.id, deviceId: 'co-dev' }).expect(200);
    const denied = await api().post(`${V}/company/close`).set(auth(coSession.body.data.accessToken)).send({ confirmName: 'Gupta Sweets', deviceId: 'co-dev' });
    expect(denied.status).toBe(403);
  });

  it('new phone: staff request a device change and the owner approves it in one tap', async () => {
    const owner = await createOwner();
    const phone = nextPhone();
    const emp = await addEmployee(owner, { phone });
    const old = await otpLogin(phone, 'old-phone');
    const fresh = await otpLogin(phone, 'new-phone');
    expect(fresh.blockedAccounts).toHaveLength(1);
    const me = await api().get(`${V}/me`).set(auth(fresh.accessToken)).expect(200);
    expect(me.body.data.blockedAccounts).toHaveLength(1);
    const req = await api().post(`${V}/me/device-requests`).set(auth(fresh.accessToken)).send({ membershipId: fresh.blockedAccounts[0].id, deviceId: 'new-phone', deviceName: 'Redmi 12' }).expect(201);
    expect(req.body.data.status).toBe('pending');
    const dash = await api().get(`${V}/dashboard/today`).set(auth(owner.token)).expect(200);
    expect(dash.body.data.needsAction.deviceRequests).toMatchObject([{ employeeId: emp.id, deviceName: 'Redmi 12' }]);
    await api().post(`${V}/device-requests/${req.body.data.request.id}/approve`).set(auth(owner.token)).expect(200);
    const sw = await api().post(`${V}/auth/switch`).set(auth(fresh.accessToken)).send({ membershipId: fresh.blockedAccounts[0].id, deviceId: 'new-phone' });
    expect(sw.status).toBe(200);
    // The old phone is out of that staff account.
    await api().post(`${V}/auth/refresh`).send({ refreshToken: old.refreshToken }).expect(401);
    expect((await api().get(`${V}/device-requests`).set(auth(owner.token))).body.data).toHaveLength(0);
  });

  it('owner lists and removes accountants; the accountant lands softly', async () => {
    const client = await createOwner({ plan: 'pro' });
    const ca = await createOwner();
    const phone = await phoneOf(ca.userId);
    await api().post(`${V}/company/accountants`).set(auth(client.token)).send({ phone, name: 'CA Gupta' }).expect(201);
    const list = await api().get(`${V}/company/accountants`).set(auth(client.token)).expect(200);
    expect(list.body.data).toMatchObject([{ phone: `+91${phone}` }]);
    const login = await otpLogin(phone, 'ca-dev');
    const caAcc = login.memberships.find((m: any) => m.role === 'ca');
    const sw = await api().post(`${V}/auth/switch`).set(auth(login.accessToken)).send({ membershipId: caAcc.id, deviceId: 'ca-dev' }).expect(200);
    await api().delete(`${V}/company/accountants/${list.body.data[0].id}`).set(auth(client.token)).expect(200);
    const r = await api().post(`${V}/auth/refresh`).send({ refreshToken: sw.body.data.refreshToken }).expect(200);
    expect(r.body.data.accountChange).toMatchObject({ kind: 'ended', role: 'owner' });
    expect((await api().get(`${V}/company/accountants`).set(auth(client.token))).body.data).toHaveLength(0);
  });

  it('new staff get a WhatsApp invite; resend is throttled; a waiting login is told it was added', async () => {
    const { messaging } = await mocks();
    const owner = await createOwner();
    const phone = nextPhone();
    const waiting = await otpLogin(phone, 'w-dev');
    const emp = await addEmployee(owner, { phone: nextPhone(), name: 'Pooja' });
    expect(emp.invitedAt).not.toBeNull();
    expect(messaging.outbox.find((m) => m.template === 'staff_invite')?.params?.[0]).toBe('Pooja');
    const again = await api().post(`${V}/employees/${emp.id}/invite`).set(auth(owner.token));
    expect(again.status).toBe(429);
    // A number already waiting gets "You've been added" instead of an invite.
    await addEmployee(owner, { phone, name: 'Raju' });
    expect(await Notification.exists({ companyId: owner.companyId, userId: waiting.user.id, template: 'staff_added' })).toBeTruthy();
    // Bulk imports do not message everyone.
    const sent = messaging.outbox.length;
    await api().post(`${V}/employees`).set(auth(owner.token)).send({ name: 'Quiet', phone: nextPhone(), invite: false }).expect(201);
    expect(messaging.outbox.length).toBe(sent);
  });
});
