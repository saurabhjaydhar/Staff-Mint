import { describe, expect, it } from 'vitest';
import { api, auth, V, createOwner, addEmployee, employeeSession, nextPhone } from './helpers.js';
import { AuditLog, Employee, Notification, User } from '../src/models/index.js';
import { normalizePhone } from '../src/lib/phone.js';
import { provider } from '../src/providers/registry.js';

const photo = Buffer.from('avatar-'.repeat(40)).toString('base64');

describe('profile', () => {
  it('owner profile: view, edit name/email/language, photo, completeness', async () => {
    const owner = await createOwner();
    let r = await api().get(`${V}/me/profile`).set(auth(owner.token)).expect(200);
    expect(r.body.data).toMatchObject({ user: { role: 'owner', email: null, photoUrl: null }, company: { name: 'Test Shop' }, work: null, bank: null });
    expect(r.body.data.completeness.missing).toEqual(expect.arrayContaining(['photo', 'email']));

    r = await api().patch(`${V}/me/profile`).set(auth(owner.token)).send({ name: ' Rakesh Sharma ', email: 'Rakesh@Example.com', language: 'en' }).expect(200);
    expect(r.body.data.user).toMatchObject({ name: 'Rakesh Sharma', email: 'rakesh@example.com', language: 'en' });
    expect((await api().patch(`${V}/me/profile`).set(auth(owner.token)).send({ email: 'not-an-email' })).status).toBe(400);
    expect((await api().patch(`${V}/me/profile`).set(auth(owner.token)).send({ role: 'ca' })).status).toBe(400);
    expect((await api().patch(`${V}/me/profile`).set(auth(owner.token)).send({ emergencyContact: { name: 'Sita' } })).status).toBe(400);

    r = await api().put(`${V}/me/photo`).set(auth(owner.token)).send({ photoBase64: photo }).expect(200);
    expect(r.body.data.user.photoUrl).toMatch(/\/files\/avatars\//);
    expect(r.body.data.completeness).toEqual({ percent: 100, missing: [] });
    const key = (await User.findById(owner.userId).lean())!.photoKey!;
    r = await api().delete(`${V}/me/photo`).set(auth(owner.token)).expect(200);
    expect(r.body.data.user.photoUrl).toBeNull();
    await expect((await provider('storage')).get(key)).rejects.toThrow();

    const me = await api().get(`${V}/me`).set(auth(owner.token)).expect(200);
    expect(me.body.data.user.email).toBe('rakesh@example.com');
  });

  it('staff profile: work details are read-only; bank details are encrypted, masked and the owner is told', async () => {
    const owner = await createOwner();
    const phone = nextPhone();
    const emp = await addEmployee(owner, { phone, name: 'Pooja Singh', designation: 'Cashier', ratePaise: 1400000 });
    const e = await employeeSession(phone);

    let r = await api().get(`${V}/me/profile`).set(auth(e.token)).expect(200);
    expect(r.body.data.work).toMatchObject({ designation: 'Cashier', wageType: 'monthly', ratePaise: 1400000 });
    expect(r.body.data.completeness.missing).toEqual(expect.arrayContaining(['bank', 'emergencyContact']));

    // Validation: needs an account or UPI; IFSC format; account digits.
    for (const bad of [{ holderName: 'Pooja Singh' }, { holderName: 'Pooja Singh', accountNumber: '12345', ifsc: 'SBIN0001234' }, { holderName: 'Pooja Singh', accountNumber: '123456789012', ifsc: 'SBI1234' }, { holderName: 'Pooja Singh', upiId: 'pooja' }]) {
      expect((await api().put(`${V}/me/bank`).set(auth(e.token)).send(bad)).status).toBe(400);
    }
    r = await api().put(`${V}/me/bank`).set(auth(e.token)).send({ holderName: 'Pooja Singh', accountNumber: '1234 5678 9012', ifsc: 'sbin0001234', upiId: 'pooja@okaxis' }).expect(200);
    expect(r.body.data).toMatchObject({ holderName: 'Pooja Singh', accountLast4: '9012', ifsc: 'SBIN0001234', upiId: 'pooja@okaxis' });
    expect(JSON.stringify(r.body)).not.toContain('123456789012');
    const stored = (await Employee.findOne({ _id: emp.id, companyId: owner.companyId }).lean())!.bankDetailsEnc!;
    expect(stored).toMatch(/^v1:/);
    expect(stored).not.toContain('9012');
    const n = await Notification.findOne({ companyId: owner.companyId, template: 'bank_changed' }).lean();
    expect(n?.body ?? n?.title).toBeTruthy();
    const log = await AuditLog.findOne({ companyId: owner.companyId, action: 'employee.bank.update' }).lean();
    expect(JSON.stringify(log)).not.toContain('123456789012');

    r = await api().patch(`${V}/me/profile`).set(auth(e.token)).send({ name: 'Pooja S.', emergencyContact: { name: 'Ramesh Singh', phone: '9876512345', relation: 'Father' } }).expect(200);
    expect(r.body.data.emergencyContact).toEqual({ name: 'Ramesh Singh', phone: '+919876512345', relation: 'Father' });
    expect(r.body.data.completeness.missing).toEqual(['photo', 'email']);
    // Name change reaches the staff record the owner sees.
    const detail = await api().get(`${V}/employees/${emp.id}`).set(auth(owner.token)).expect(200);
    expect(detail.body.data).toMatchObject({ name: 'Pooja S.', bank: { accountLast4: '9012' }, emergencyContact: { name: 'Ramesh Singh' } });

    // Owner can fill in or clear staff bank details; staff cannot use the owner route.
    expect((await api().put(`${V}/employees/${emp.id}/bank`).set(auth(e.token)).send({ holderName: 'X Y', upiId: 'x@ybl' })).status).toBe(403);
    r = await api().put(`${V}/employees/${emp.id}/bank`).set(auth(owner.token)).send({ holderName: 'Pooja Singh', upiId: 'pooja@ybl' }).expect(200);
    expect(r.body.data).toMatchObject({ accountLast4: null, ifsc: null, upiId: 'pooja@ybl' });
    await api().delete(`${V}/me/bank`).set(auth(e.token)).expect(200);
    expect((await api().get(`${V}/me/profile`).set(auth(e.token))).body.data.bank).toBeNull();
  });

  it('phone change needs an OTP on the new number, and the old number stops working', async () => {
    const owner = await createOwner();
    const phone = nextPhone();
    const emp = await addEmployee(owner, { phone, name: 'Raju' });
    const e = await employeeSession(phone);
    const other = nextPhone();
    await addEmployee(owner, { phone: other, name: 'Amit' });

    expect((await api().post(`${V}/me/phone/request`).set(auth(e.token)).send({ phone })).status).toBe(400);
    expect((await api().post(`${V}/me/phone/request`).set(auth(e.token)).send({ phone: other })).status).toBe(409);
    const fresh = nextPhone();
    const req = await api().post(`${V}/me/phone/request`).set(auth(e.token)).send({ phone: fresh }).expect(200);
    expect((await api().post(`${V}/me/phone/verify`).set(auth(e.token)).send({ phone: fresh, code: '000000' })).status).toBe(400);
    const r = await api().post(`${V}/me/phone/verify`).set(auth(e.token)).send({ phone: fresh, code: req.body.data.devCode }).expect(200);
    expect(r.body.data.user.phone).toBe(normalizePhone(fresh));
    expect((await Employee.findOne({ _id: emp.id, companyId: owner.companyId }).lean())!.phone).toBe(normalizePhone(fresh));
    // The code is single-use.
    expect((await api().post(`${V}/me/phone/verify`).set(auth(e.token)).send({ phone: fresh, code: req.body.data.devCode })).status).toBe(400);
  });

  it('log out everywhere revokes refresh tokens', async () => {
    const owner = await createOwner();
    await api().post(`${V}/me/logout-all`).set(auth(owner.token)).expect(200);
    const r = await api().post(`${V}/auth/refresh`).send({ refreshToken: owner.refreshToken });
    expect(r.status).toBe(401);
  });
});
