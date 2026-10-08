import { describe, expect, it } from 'vitest';
import { Types } from 'mongoose';
import { createOwner, addEmployee, api, auth, V, mocks } from './helpers.js';
import { Attendance, Company, PayrollRun, Notification } from '../src/models/index.js';
import { schedulerTick } from '../src/jobs/handlers.js';

describe('scheduler', () => {
  it('on the 1st at 10:00 IST: closes yesterday, sends the digest, drafts last month — once', async () => {
    const { push } = await mocks();
    const owner = await createOwner();
    await api().post(`${V}/me/push-token`).set(auth(owner.token)).send({ token: 'owner-token-abcdef', platform: 'android' }).expect(200);
    const emp = await addEmployee(owner, { joiningDate: '2026-08-01' });
    const cid = new Types.ObjectId(owner.companyId);
    await Company.collection.updateOne({ _id: cid }, { $set: { createdAt: new Date('2026-08-01') } });
    const { Employee } = await import('../src/models/index.js');
    await Employee.collection.updateMany({ companyId: cid }, { $set: { createdAt: new Date('2026-08-01') } });

    const now = new Date('2026-10-01T04:30:00Z'); // 10:00 IST
    const s1 = await schedulerTick(now);
    expect(s1).toMatchObject({ closed: 1, digests: 1, drafts: 1 });
    expect(await Attendance.findOne({ companyId: cid, employeeId: emp.id, date: '2026-09-30' }).lean()).toMatchObject({ status: 'absent', autoMarked: true });
    expect(await PayrollRun.countDocuments({ companyId: cid, month: '2026-09' })).toBe(1);
    expect(push.sent.some((p) => p.msg.title === 'Today at a glance' || p.msg.title === 'आज की हाज़िरी')).toBe(true);
    expect(await Notification.countDocuments({ companyId: cid, template: 'salary_ready' })).toBeGreaterThan(0);

    const s2 = await schedulerTick(new Date('2026-10-01T04:35:00Z'));
    expect(s2).toMatchObject({ closed: 0, digests: 0, drafts: 0 });
  });

  it('does not draft payroll for companies that signed up this month', async () => {
    const owner = await createOwner();
    await addEmployee(owner);
    const s = await schedulerTick(new Date());
    expect(s.drafts).toBe(0);
    expect(await PayrollRun.countDocuments({ companyId: owner.companyId })).toBe(0);
  });
});
