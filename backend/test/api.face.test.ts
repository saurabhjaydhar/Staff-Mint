import { describe, expect, it } from 'vitest';
import { api, auth, V, createOwner, addEmployee, employeeSession, nextPhone, punchBody } from './helpers.js';
import { Employee, Notification } from '../src/models/index.js';
import { classify } from '../src/modules/face/service.js';
import { provider } from '../src/providers/registry.js';

const photo = (marker = 'ramesh-reference') => Buffer.from(`${marker}-`.repeat(20)).toString('base64');

async function setup(plan = 'growth') {
  const owner = await createOwner({ plan });
  const phone = nextPhone();
  const emp = await addEmployee(owner, { phone, name: 'Ramesh Kumar' });
  const e = await employeeSession(phone);
  return { owner, emp, e };
}

const enableFace = (token: string) => api().patch(`${V}/company/settings`).set(auth(token)).send({ faceMatchPolicy: 'review' });
const enroll = (token: string, body: Record<string, unknown>) => api().post(`${V}/me/face`).set(auth(token)).send(body);

describe('face match', () => {
  it('classifies similarity with the configured thresholds', () => {
    expect(classify(99, 1)).toBe('match');
    expect(classify(90, 1)).toBe('match');
    expect(classify(80, 1)).toBe('unsure');
    expect(classify(40, 1)).toBe('mismatch');
    expect(classify(null, 0)).toBe('no_face');
    expect(classify(97, 2)).toBe('many_faces');
  });

  it('is off by default, needs the Growth plan, and enrolment needs explicit consent and one clear face', async () => {
    const starter = await setup('starter');
    const r = await enableFace(starter.owner.token);
    expect(r.status).toBe(402);
    expect(r.body.error.code).toBe('FEATURE_NOT_IN_PLAN');

    const { owner, e } = await setup();
    const settings = await api().get(`${V}/company`).set(auth(owner.token)).expect(200);
    expect(settings.body.data.settings.faceMatchPolicy).toBe('off');
    await enableFace(owner.token).expect(200);

    expect((await enroll(e.token, { photoBase64: photo() })).status).toBe(400);
    expect((await enroll(e.token, { consent: false, photoBase64: photo() })).status).toBe(400);
    const none = await enroll(e.token, { consent: true, photoBase64: photo('noface') });
    expect(none.status).toBe(422);
    expect(none.body.error).toMatchObject({ code: 'FACE_NOT_CLEAR', details: { reason: 'no_face' } });
    const two = await enroll(e.token, { consent: true, photoBase64: photo('twofaces') });
    expect(two.body.error.details.reason).toBe('many_faces');

    const ok = await enroll(e.token, { consent: true, photoBase64: photo() }).expect(201);
    expect(ok.body.data).toMatchObject({ status: 'pending' });
    expect(ok.body.data.photoUrl).toMatch(/\/files\/faces\//);
  });

  it('owner approves, then each selfie is compared: match passes, mismatch and unsure wait for approval', async () => {
    const { owner, emp, e } = await setup();
    await enableFace(owner.token).expect(200);
    const ref = photo();
    await enroll(e.token, { consent: true, photoBase64: ref }).expect(201);

    // Pending enrolment is on the owner's list; check-ins are not compared until approved.
    let dash = await api().get(`${V}/dashboard/today`).set(auth(owner.token)).expect(200);
    expect(dash.body.data.needsAction.faceEnrollments).toEqual([expect.objectContaining({ employeeId: emp.id, employeeName: 'Ramesh Kumar', status: 'pending' })]);
    const before = await api().post(`${V}/attendance/check-in`).set(auth(e.token)).send(punchBody(e.deviceId, { selfieBase64: ref })).expect(201);
    expect(before.body.data.punch.face).toBeNull();

    const approved = await api().post(`${V}/employees/${emp.id}/face/approve`).set(auth(owner.token)).expect(200);
    expect(approved.body.data.status).toBe('approved');
    expect((await api().post(`${V}/employees/${emp.id}/face/approve`).set(auth(owner.token))).status).toBe(409);
    const me = await api().get(`${V}/me`).set(auth(e.token)).expect(200);
    expect(me.body.data.employee.face.status).toBe('approved');

    const match = await api().post(`${V}/attendance/check-out`).set(auth(e.token)).send(punchBody(e.deviceId, { selfieBase64: ref })).expect(201);
    expect(match.body.data.punch).toMatchObject({ approval: 'not_required', face: { result: 'match', similarity: 99.9 }, flags: [] });

    const stranger = await api().post(`${V}/attendance/check-in`).set(auth(e.token)).send(punchBody(e.deviceId, { selfieBase64: photo('stranger') })).expect(201);
    expect(stranger.body.data.punch).toMatchObject({ approval: 'pending', face: { result: 'mismatch' } });
    expect(stranger.body.data.punch.flags).toContain('face_mismatch');
    const n = await Notification.findOne({ companyId: owner.companyId, template: 'punch_approval' }).sort({ createdAt: -1 }).lean();
    expect(`${n?.title} ${n?.body}`).toMatch(/does not clearly match|मेल नहीं खाती/);

    dash = await api().get(`${V}/dashboard/today`).set(auth(owner.token)).expect(200);
    const item = dash.body.data.needsAction.punchApprovals.find((p: any) => p.punch.id === stranger.body.data.punch.id);
    expect(item.facePhotoUrl).toMatch(/\/files\/faces\//);
    expect(item.punch.selfieUrl).toMatch(/\/files\/selfies\//);
    expect(dash.body.data.needsAction.faceEnrollments).toEqual([]);

    // The owner rejects the stranger punch; an unsure selfie waits too.
    await api().post(`${V}/attendance/${stranger.body.data.record.id}/punches/${stranger.body.data.punch.id}/decision`).set(auth(owner.token)).send({ approve: false }).expect(200);
    const blurry = await api().post(`${V}/attendance/check-in`).set(auth(e.token)).send(punchBody(e.deviceId, { selfieBase64: photo('blurry') })).expect(201);
    expect(blurry.body.data.punch).toMatchObject({ approval: 'pending', face: { result: 'unsure', similarity: 82 } });
  });

  it('a face-engine error never blocks or holds a check-in', async () => {
    const { owner, emp, e } = await setup();
    await enableFace(owner.token).expect(200);
    await enroll(e.token, { consent: true, photoBase64: photo() }).expect(201);
    await api().post(`${V}/employees/${emp.id}/face/approve`).set(auth(owner.token)).expect(200);
    // Reference photo lost from storage.
    const doc = await Employee.findOne({ _id: emp.id, companyId: owner.companyId }).lean();
    await (await provider('storage')).delete(doc!.face!.refKey!);
    const r = await api().post(`${V}/attendance/check-in`).set(auth(e.token)).send(punchBody(e.deviceId)).expect(201);
    expect(r.body.data.punch).toMatchObject({ approval: 'not_required', face: { result: 'error' } });
    expect(r.body.data.punch.flags).toContain('face_check_failed');
  });

  it('withdrawing consent, an owner reset, or leaving deletes the photo; policy off skips the check', async () => {
    const { owner, emp, e } = await setup();
    await enableFace(owner.token).expect(200);
    const storage = await provider('storage');

    await enroll(e.token, { consent: true, photoBase64: photo() }).expect(201);
    let key = (await Employee.findOne({ _id: emp.id, companyId: owner.companyId }).lean())!.face!.refKey!;
    const w = await api().delete(`${V}/me/face`).set(auth(e.token)).expect(200);
    expect(w.body.data).toMatchObject({ status: 'none', photoUrl: null });
    await expect(storage.get(key)).rejects.toThrow();

    await enroll(e.token, { consent: true, photoBase64: photo() }).expect(201);
    key = (await Employee.findOne({ _id: emp.id, companyId: owner.companyId }).lean())!.face!.refKey!;
    await api().delete(`${V}/employees/${emp.id}/face`).set(auth(owner.token)).expect(200);
    await expect(storage.get(key)).rejects.toThrow();

    await enroll(e.token, { consent: true, photoBase64: photo() }).expect(201);
    await api().post(`${V}/employees/${emp.id}/face/approve`).set(auth(owner.token)).expect(200);
    await api().patch(`${V}/company/settings`).set(auth(owner.token)).send({ faceMatchPolicy: 'off' }).expect(200);
    const off = await api().post(`${V}/attendance/check-in`).set(auth(e.token)).send(punchBody(e.deviceId, { selfieBase64: photo('stranger') })).expect(201);
    expect(off.body.data.punch).toMatchObject({ approval: 'not_required', face: null });

    key = (await Employee.findOne({ _id: emp.id, companyId: owner.companyId }).lean())!.face!.refKey!;
    await api().post(`${V}/employees/${emp.id}/deactivate`).set(auth(owner.token)).send({}).expect(200);
    expect((await Employee.findOne({ _id: emp.id, companyId: owner.companyId }).lean())!.face).toMatchObject({ status: 'none', refKey: null });
    await expect(storage.get(key)).rejects.toThrow();
  });

  it('staff cannot touch another person\'s face photo and owners cannot enrol for staff', async () => {
    const { owner, emp, e } = await setup();
    expect((await api().post(`${V}/employees/${emp.id}/face/approve`).set(auth(e.token))).status).toBe(403);
    expect((await enroll(owner.token, { consent: true, photoBase64: photo() })).status).toBe(403);
    const other = await setup();
    expect((await api().get(`${V}/employees/${emp.id}/face`).set(auth(other.owner.token))).status).toBe(404);
  });
});
