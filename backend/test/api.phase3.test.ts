import { describe, expect, it } from 'vitest';
import { Types } from 'mongoose';
import { api, auth, V, createOwner, addEmployee, otpLogin, nextPhone, mocks } from './helpers.js';
import { Company, Employee, Membership, Notification, OtpRequest, Payslip, RecoveryRequest, User } from '../src/models/index.js';
import { normalizePhone } from '../src/lib/phone.js';
import { completeRecoveries } from '../src/modules/accounts/identity.js';

const ADMIN = { 'x-admin-key': 'dev-admin-key' };

/** OTP code for an action on your own number (transfer, delete). */
async function ownCode(phone: string) {
  await OtpRequest.deleteMany({ phone: normalizePhone(phone) });
  const r = await api().post(`${V}/auth/otp/request`).send({ phone }).expect(200);
  return r.body.data.devCode as string;
}

/** Open [companyId] for this person on [deviceId] and return the session. */
async function openIn(phone: string, companyId: string, deviceId = `dev-${phone}`) {
  const login = await otpLogin(phone, deviceId);
  const m = login.memberships.find((x: any) => x.companyId === companyId);
  const r = await api().post(`${V}/auth/switch`).set(auth(login.accessToken)).send({ membershipId: m.id, deviceId }).expect(200);
  return r.body.data;
}

describe('F14 Phase 3: shared ownership & recovery', () => {
  it('co-owners: added by the main owner, billing only when allowed, cannot close, can leave', async () => {
    const shop = await createOwner({ setup: { name: 'Sharma Medical' } });
    const partnerPhone = nextPhone();
    let r = await api().post(`${V}/company/owners`).set(auth(shop.token)).send({ phone: partnerPhone, name: 'Anil Sharma' }).expect(201);
    expect(r.body.data).toMatchObject([{ isMain: true }, { isMain: false, canManageBilling: false, name: 'Anil Sharma' }]);
    const co = await openIn(partnerPhone, shop.companyId);
    expect(co.user.role).toBe('owner');
    // Co-owners run the business but billing waits for the main owner's OK.
    await api().get(`${V}/employees`).set(auth(co.accessToken)).expect(200);
    const billing = await api().get(`${V}/billing/subscription`).set(auth(co.accessToken));
    expect(billing.status).toBe(403);
    expect(billing.body.error.details.reason).toBe('billing_not_allowed');
    const coId = r.body.data[1].id;
    await api().patch(`${V}/company/owners/${coId}`).set(auth(shop.token)).send({ canManageBilling: true }).expect(200);
    await api().get(`${V}/billing/subscription`).set(auth(co.accessToken)).expect(200);
    // Only the main owner manages owners and closes the business.
    expect((await api().post(`${V}/company/owners`).set(auth(co.accessToken)).send({ phone: nextPhone(), name: 'X' })).status).toBe(403);
    expect((await api().post(`${V}/company/close`).set(auth(co.accessToken)).send({ confirmName: 'Sharma Medical', deviceId: 'x-dev' })).status).toBe(403);
    // Co-owner can step away; the main owner cannot.
    const left = await api().post(`${V}/me/accounts/${coId}/leave`).set(auth(co.accessToken)).send({ deviceId: `dev-${partnerPhone}` });
    expect(left.status).toBe(200);
    const mainM = (await Membership.findOne({ userId: shop.userId, companyId: shop.companyId }).lean())!;
    expect((await api().post(`${V}/me/accounts/${mainM._id}/leave`).set(auth(shop.token)).send({ deviceId: 'dev-main' })).status).toBe(409);
    // Staff numbers cannot be made co-owners by accident.
    const staffPhone = nextPhone();
    await addEmployee(shop, { phone: staffPhone });
    await otpLogin(staffPhone);
    r = await api().post(`${V}/company/owners`).set(auth(shop.token)).send({ phone: staffPhone, name: 'Staff' });
    expect(r.status).toBe(409);
  });

  it('transfer: the main owner hands over with their OTP; the new number accepts after its own login', async () => {
    await mocks();
    const shop = await createOwner({ setup: { name: 'Gupta Sweets' } });
    const buyer = nextPhone();
    const bad = await api().post(`${V}/company/transfer`).set(auth(shop.token)).send({ phone: buyer, keepAs: 'leave', code: '000000' });
    expect(bad.status).toBeGreaterThanOrEqual(400);
    const code = await ownCode(shop.phone);
    const t = await api().post(`${V}/company/transfer`).set(auth(shop.token)).send({ phone: buyer, keepAs: 'leave', code }).expect(201);
    expect(t.body.data).toMatchObject({ kind: 'transfer', status: 'pending', keepAs: 'leave' });
    const login = await otpLogin(buyer, 'buyer-dev');
    const me = await api().get(`${V}/me`).set(auth(login.accessToken)).expect(200);
    expect(me.body.data.pendingTransfers).toMatchObject([{ companyName: 'Gupta Sweets', kind: 'transfer' }]);
    const acc = await api().post(`${V}/me/transfers/${t.body.data.id}/accept`).set(auth(login.accessToken)).send({ deviceId: 'buyer-dev' }).expect(200);
    expect(acc.body.data.user).toMatchObject({ role: 'owner', companyId: shop.companyId });
    expect(String((await Company.findById(shop.companyId).lean())!.ownerUserId)).toBe(login.user.id);
    // The seller chose to leave: their access ended softly.
    expect((await Membership.findOne({ userId: shop.userId, companyId: shop.companyId }).lean())!.status).toBe('inactive');
    expect(await Notification.exists({ companyId: shop.companyId, template: 'ownership_moved' })).toBeTruthy();
  });

  it('owner lost their number: a co-owner moves main ownership to the new number', async () => {
    await mocks();
    const shop = await createOwner({ setup: { name: 'Verma Traders' } });
    const partner = nextPhone();
    await api().post(`${V}/company/owners`).set(auth(shop.token)).send({ phone: partner, name: 'Partner' }).expect(201);
    const co = await openIn(partner, shop.companyId);
    const newNumber = nextPhone();
    const t = await api().post(`${V}/company/owner-recovery`).set(auth(co.accessToken)).send({ newPhone: newNumber }).expect(201);
    expect(t.body.data.kind).toBe('recovery');
    // The main owner (if the number still works) sees it and could cancel.
    expect((await api().get(`${V}/company/transfer`).set(auth(shop.token))).body.data.kind).toBe('recovery');
    const n = await otpLogin(newNumber, 'new-dev');
    await api().post(`${V}/me/transfers/${t.body.data.id}/accept`).set(auth(n.accessToken)).send({ deviceId: 'new-dev' }).expect(200);
    expect(String((await Company.findById(shop.companyId).lean())!.ownerUserId)).toBe(n.user.id);
    // The old number keeps a co-owner account in case it comes back.
    expect((await Membership.findOne({ userId: shop.userId, companyId: shop.companyId }).lean())!.status).toBe('active');
  });

  it('recycled number: a long-idle number on a new phone asks "Is this you?"', async () => {
    const shop = await createOwner();
    const phone = nextPhone();
    const emp = await addEmployee(shop, { phone, name: 'Ramesh Kumar' });
    const first = await otpLogin(phone, 'ramesh-phone');
    await User.updateOne({ _id: first.user.id }, { lastLoginAt: new Date(Date.now() - 200 * 86400_000) });
    // Same phone as before: no question.
    expect((await otpLogin(phone, 'ramesh-phone')).accessToken).toBeTruthy();
    await User.updateOne({ _id: first.user.id }, { lastLoginAt: new Date(Date.now() - 200 * 86400_000) });
    const q = await otpLogin(phone, 'unknown-phone');
    expect(q.accessToken).toBeUndefined();
    expect(q.identityCheck.maskedName).toBe('R*** K***');
    // "Yes, it's me" continues.
    const yes = await api().post(`${V}/auth/identity/confirm`).send({ token: q.identityCheck.token }).expect(200);
    // It is them, on a new phone: the staff account stays locked to the old phone until the owner approves.
    expect(yes.body.data.blockedAccounts).toMatchObject([{ role: 'employee' }]);
    // Next time someone else has the number and says "No".
    await User.updateOne({ _id: first.user.id }, { lastLoginAt: new Date(Date.now() - 200 * 86400_000) });
    const q2 = await otpLogin(phone, 'stranger-phone');
    const no = await api().post(`${V}/auth/identity/reject`).send({ token: q2.identityCheck.token }).expect(200);
    expect(no.body.data).toMatchObject({ needsCompanySetup: true, memberships: [] });
    expect(no.body.data.user.id).not.toBe(first.user.id);
    expect((await Employee.findById(emp.id).setOptions({ skipTenant: true }).lean())!.phoneRecycledAt).not.toBeNull();
    expect(await Notification.exists({ companyId: shop.companyId, template: 'staff_number_recycled' })).toBeTruthy();
    // The stranger is not attached to Ramesh's staff record on later logins.
    expect((await otpLogin(phone, 'stranger-phone')).memberships).toHaveLength(0);
  });

  it('lost number with an email on the profile: the whole account moves to the new number', async () => {
    const shop = await createOwner({ setup: { name: 'Email Shop' } });
    await api().patch(`${V}/me/profile`).set(auth(shop.token)).send({ email: 'owner@example.com' }).expect(200);
    const newNumber = nextPhone();
    const n = await otpLogin(newNumber, 'new-dev');
    const req = await api().post(`${V}/me/recovery/email`).set(auth(n.accessToken)).send({ email: 'Owner@Example.com' }).expect(200);
    expect(req.body.data.sent).toBe(true);
    // Unknown emails get the same answer (no code).
    const unknown = await api().post(`${V}/me/recovery/email`).set(auth(n.accessToken)).send({ email: 'nobody@example.com' }).expect(200);
    expect(unknown.body.data.devCode).toBeUndefined();
    const moved = await api().post(`${V}/me/recovery/email/verify`).set(auth(n.accessToken)).send({ email: 'owner@example.com', code: req.body.data.devCode, deviceId: 'new-dev' }).expect(200);
    expect(moved.body.data.user).toMatchObject({ id: shop.userId, companyId: shop.companyId, phone: `+91${newNumber}` });
    // Old sessions (the lost phone) are over.
    await api().post(`${V}/auth/refresh`).send({ refreshToken: shop.refreshToken }).expect(401);
  });

  it('support recovery: 2 of 3 proofs, approval, a hold the business can stop, then completion', async () => {
    await mocks();
    const shop = await createOwner({ setup: { name: 'Hold Shop' } });
    const managerPhone = nextPhone();
    const mgr = await addEmployee(shop, { phone: managerPhone });
    await api().post(`${V}/employees/${mgr.id}/role`).set(auth(shop.token)).send({ role: 'manager' }).expect(200);
    const n = await otpLogin(nextPhone(), 'n-dev');
    const one = await api().post(`${V}/me/recovery-requests`).set(auth(n.accessToken)).send({ oldPhone: shop.phone, businessName: 'Hold Shop', gstin: '07ABCDE1234F1Z5' });
    expect(one.body.error.details.reason).toBe('need_two_proofs');
    const sub = await api()
      .post(`${V}/me/recovery-requests`)
      .set(auth(n.accessToken))
      .send({ oldPhone: shop.phone, businessName: 'Hold Shop', gstin: '07ABCDE1234F1Z5', paymentTxnId: 'pay_123' })
      .expect(201);
    const list = await api().get(`${V}/admin/recovery-requests?status=submitted`).set(ADMIN).expect(200);
    expect(list.body.data.find((x: any) => x.id === sub.body.data.id)).toMatchObject({ gstin: '07ABCDE1234F1Z5' });
    await api().post(`${V}/admin/recovery-requests/${sub.body.data.id}/approve`).set(ADMIN).expect(200);
    // The manager hears about it and can stop it.
    const m = await otpLogin(managerPhone, 'mgr-dev');
    const me = await api().get(`${V}/me`).set(auth(m.accessToken)).expect(200);
    expect(me.body.data.recoveryHolds).toMatchObject([{ id: sub.body.data.id, businessName: 'Hold Shop' }]);
    await api().post(`${V}/me/recovery-holds/${sub.body.data.id}/stop`).set(auth(m.accessToken)).expect(200);
    expect((await RecoveryRequest.findById(sub.body.data.id).lean())!.status).toBe('stopped');
    // A second request nobody stops completes after the hold.
    const sub2 = await api()
      .post(`${V}/me/recovery-requests`)
      .set(auth(n.accessToken))
      .send({ oldPhone: shop.phone, businessName: 'Hold Shop', paymentTxnId: 'pay_123', selfieVideoBase64: Buffer.from('video').toString('base64') })
      .expect(201);
    await api().post(`${V}/admin/recovery-requests/${sub2.body.data.id}/approve`).set(ADMIN).expect(200);
    expect(await completeRecoveries(new Date(Date.now() + 8 * 86400_000))).toBeGreaterThanOrEqual(1);
    expect((await User.findById(shop.userId).lean())!.phone).toBe(`+91${n.user.phone.replace('+91', '')}`);
  });

  it('delete my account: owners must hand over first; staff can delete after export', async () => {
    const shop = await createOwner();
    const code = await ownCode(shop.phone);
    const blocked = await api().post(`${V}/me/delete`).set(auth(shop.token)).send({ code });
    expect(blocked.status).toBe(409);
    expect(blocked.body.error.details.reason).toBe('owns_business');
    const phone = nextPhone();
    const emp = await addEmployee(shop, { phone });
    const s = await otpLogin(phone, 'del-dev');
    const exp = await api().get(`${V}/me/export`).set(auth(s.accessToken)).expect(200);
    expect(exp.body.data.accounts).toHaveLength(1);
    await api().post(`${V}/me/delete`).set(auth(s.accessToken)).send({ code: await ownCode(phone) }).expect(200);
    expect((await User.findById(s.user.id).lean())!.deletedAt).not.toBeNull();
    expect((await Employee.findById(emp.id).setOptions({ skipTenant: true }).lean())!.userId).toBeNull();
    await api().get(`${V}/me`).set(auth(s.accessToken)).expect(401);
  });

  it('ex-staff keep their own payslips for 12 months unless the owner turns it off', async () => {
    const shop = await createOwner({ setup: { name: 'Payslip Shop' } });
    const phone = nextPhone();
    const emp = await addEmployee(shop, { phone, name: 'Pooja' });
    const s = await otpLogin(phone, 'p-dev');
    await Payslip.create({ companyId: shop.companyId, runId: new Types.ObjectId(), employeeId: emp.id, employeeName: 'Pooja', month: '2026-09', status: 'final', wageType: 'monthly', ratePaise: 1200000 });
    expect((await api().get(`${V}/me/past-payslips`).set(auth(s.accessToken))).body.data).toHaveLength(0); // still working there
    await api().post(`${V}/employees/${emp.id}/deactivate`).set(auth(shop.token)).send({}).expect(200);
    const r = await api().post(`${V}/auth/refresh`).send({ refreshToken: s.refreshToken }).expect(200);
    const past = await api().get(`${V}/me/past-payslips`).set(auth(r.body.data.accessToken)).expect(200);
    expect(past.body.data).toMatchObject([{ companyName: 'Payslip Shop', payslips: [{ month: '2026-09' }] }]);
    await api().patch(`${V}/company/settings`).set(auth(shop.token)).send({ exStaffPayslips: false }).expect(200);
    expect((await api().get(`${V}/me/past-payslips`).set(auth(r.body.data.accessToken))).body.data).toHaveLength(0);
  });
});
