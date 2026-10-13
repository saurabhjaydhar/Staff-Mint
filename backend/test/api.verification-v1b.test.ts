import { describe, expect, it } from 'vitest';
import { api, auth, V, createOwner, addEmployee, employeeSession, nextPhone, mocks, storage } from './helpers.js';
import { AuditLog, Company, Employee, VerificationCheck, VerificationRequest } from '../src/models/index.js';
import { purgeRetention } from '../src/jobs/handlers.js';
import { setProvider } from '../src/providers/registry.js';
import { MockVerificationProvider } from '../src/providers/verification/mock.js';
import { MockFaceProvider } from '../src/providers/face/mock.js';
import { describe as describeLog } from '../src/modules/audit/describe.js';
import { addDays, todayIn } from '../src/lib/dates.js';

const jpeg = (marker: string) => Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.from(marker)]).toString('base64');
const photo = (marker: string) => ({ data: jpeg(marker), mime: 'image/jpeg' });
const check = (data: any, kind: string) => data.checks.find((c: any) => c.kind === kind);

async function setup() {
  await mocks();
  setProvider('verification', new MockVerificationProvider());
  setProvider('face', new MockFaceProvider());
  const owner = await createOwner({ plan: 'growth' });
  return owner;
}
const ask = (token: string, id: string, kinds: string[]) => api().post(`${V}/verification/employees/${id}`).set(auth(token)).send({ kinds });
const step = (token: string, path: string, body: Record<string, unknown> = {}) => api().post(`${V}/verification/mine/${path}`).set(auth(token)).send(body);
const forThem = (token: string, id: string, path: string, body: Record<string, unknown> = {}) =>
  api().post(`${V}/verification/employees/${id}/on-behalf/${path}`).set(auth(token)).send(body);

describe('selfie vs ID photo', () => {
  it('needs a photo ID first; a selfie with no face is "try again"; a stranger is for the owner to look at; a match is verified', async () => {
    const owner = await setup();
    const phone = nextPhone();
    const emp = await addEmployee(owner, { name: 'Ramesh Kumar', phone });
    const staff = await employeeSession(phone);
    await ask(owner.token, emp.id, ['face']).expect(201);
    await step(staff.token, 'consent').expect(200);
    let me = (await api().get(`${V}/verification/mine`).set(auth(staff.token)).expect(200)).body.data;
    expect(me.idPhoto).toBe(false);
    expect(me.consentText.en.join(' ')).toMatch(/selfie is not kept/i);

    const noId = await step(staff.token, 'face', { selfie: jpeg('me') });
    expect(noId.status).toBe(409);
    expect(noId.body.error.details).toMatchObject({ reason: 'no_id_photo' });

    await step(staff.token, 'documents', { kind: 'pan', files: [photo('pan-card')] }).expect(201);
    me = (await api().get(`${V}/verification/mine`).set(auth(staff.token)).expect(200)).body.data;
    expect(me.idPhoto).toBe(true);

    const blank = await step(staff.token, 'face', { selfie: jpeg('noface') });
    expect(blank.status).toBe(422);
    expect(blank.body.error.code).toBe('FACE_NOT_CLEAR');
    expect((await VerificationCheck.findOne({ companyId: owner.companyId, kind: 'face' }).lean())!.attempts).toBe(0);

    me = (await step(staff.token, 'face', { selfie: jpeg('stranger') }).expect(200)).body.data;
    expect(check(me, 'face')).toMatchObject({ status: 'mismatch', matchScore: 12 });
    const ownerView = (await api().get(`${V}/verification/employees/${emp.id}`).set(auth(owner.token)).expect(200)).body.data;
    expect(ownerView).toMatchObject({ badge: 'needs_attention', hasApp: true });
    expect(check(ownerView, 'face').details).toEqual({ idKind: 'pan' });

    await api().post(`${V}/verification/checks/${check(ownerView, 'face').id}/ask-again`).set(auth(owner.token)).expect(200);
    me = (await step(staff.token, 'face', { selfie: jpeg('me') }).expect(200)).body.data;
    expect(check(me, 'face')).toMatchObject({ status: 'verified', matchScore: 97 });
    expect(me.request.status).toBe('done');
    expect((await Employee.findOne({ _id: emp.id, companyId: owner.companyId }).lean())!.verification?.status).toBe('verified');

    // The selfie itself is never stored.
    const stored = JSON.stringify(await VerificationCheck.find({ companyId: owner.companyId }).lean());
    expect(stored).not.toContain(jpeg('me'));
    const log = await AuditLog.findOne({ companyId: owner.companyId, action: 'verification.check', 'after.status': 'mismatch' }).lean();
    expect(describeLog(log!, 'en', { employeeName: () => 'Ramesh Kumar' } as any)?.text).toBe('Ramesh Kumar: selfie vs ID photo don’t match');
  });

  it('no face on the ID photo: "not found", so they can add a clearer one', async () => {
    const owner = await setup();
    const phone = nextPhone();
    const emp = await addEmployee(owner, { phone });
    const staff = await employeeSession(phone);
    await ask(owner.token, emp.id, ['face']).expect(201);
    await step(staff.token, 'consent').expect(200);
    await step(staff.token, 'documents', { kind: 'aadhaar', files: [photo('noface-blurry-copy')] }).expect(201);
    const me = (await step(staff.token, 'face', { selfie: jpeg('me') }).expect(200)).body.data;
    expect(check(me, 'face')).toMatchObject({ status: 'not_found', matchScore: null });
  });
});

describe('the owner does the steps with someone who has no smartphone', () => {
  it('they agree on paper (tick + signed slip), then Aadhaar OTP, PAN, bank and selfie, done by the owner', async () => {
    const owner = await setup();
    const raju = await addEmployee(owner, { name: 'Raju', phone: nextPhone() });
    await ask(owner.token, raju.id, ['aadhaar', 'pan', 'bank', 'face']).expect(201);
    let v = (await api().get(`${V}/verification/employees/${raju.id}`).set(auth(owner.token)).expect(200)).body.data;
    expect(v.hasApp).toBe(false);

    let steps = (await api().get(`${V}/verification/employees/${raju.id}/on-behalf`).set(auth(owner.token)).expect(200)).body.data;
    expect(steps.request.consented).toBe(false);
    expect((await forThem(owner.token, raju.id, 'pan', { pan: 'ABCDE1234F' })).status).toBe(403);
    expect((await forThem(owner.token, raju.id, 'consent', { staffAgreed: true })).status).toBe(400);
    expect((await forThem(owner.token, raju.id, 'consent', { staffAgreed: false, slip: photo('slip') })).status).toBe(400);
    steps = (await forThem(owner.token, raju.id, 'consent', { staffAgreed: true, slip: photo('signed-slip') }).expect(200)).body.data;
    expect(steps.request).toMatchObject({ consented: true, consentBy: 'owner_on_behalf', hasSlip: true });

    await forThem(owner.token, raju.id, 'aadhaar/otp', { aadhaar: '234567891234' }).expect(200);
    await forThem(owner.token, raju.id, 'aadhaar/verify', { otp: '123456' }).expect(200);
    await forThem(owner.token, raju.id, 'pan', { pan: 'ABCDE1234F' }).expect(200);
    await forThem(owner.token, raju.id, 'bank', { accountNumber: '123456781234', ifsc: 'SBIN0001234' }).expect(200);
    // The ID photo for the selfie check: the owner adds it (their agreement is on file now, no second slip).
    await api()
      .post(`${V}/verification/employees/${raju.id}/documents`)
      .set(auth(owner.token))
      .send({ kind: 'aadhaar', files: [photo('aadhaar-card')], staffAgreed: true })
      .expect(201);
    steps = (await forThem(owner.token, raju.id, 'face', { selfie: jpeg('raju-now') }).expect(200)).body.data;
    expect(steps.checks.map((c: any) => [c.kind, c.status])).toEqual([
      ['aadhaar', 'verified'],
      ['pan', 'verified'],
      ['bank', 'verified'],
      ['face', 'verified'],
    ]);
    v = (await api().get(`${V}/verification/employees/${raju.id}`).set(auth(owner.token)).expect(200)).body.data;
    expect(v.badge).toBe('verified');

    // The slip opens through a short link, and opening it is in History.
    const slip = (await api().post(`${V}/verification/employees/${raju.id}/slip/open`).set(auth(owner.token)).expect(200)).body.data;
    const file = await api().get(new URL(slip.url).pathname).expect(200);
    expect(Buffer.from(file.body).includes(Buffer.from('signed-slip'))).toBe(true);
    const consent = await AuditLog.findOne({ companyId: owner.companyId, action: 'verification.consent' }).lean();
    expect(describeLog(consent!, 'en', { employeeName: () => 'Raju' } as any)?.text).toBe('Raju agreed to the document check on paper (signed slip)');
    expect(await AuditLog.exists({ companyId: owner.companyId, action: 'document.view', 'after.label': 'Consent slip' })).toBeTruthy();
  });

  it('owners only: staff can’t do it for a colleague', async () => {
    const owner = await setup();
    const raju = await addEmployee(owner, { name: 'Raju', phone: nextPhone() });
    const phone = nextPhone();
    await addEmployee(owner, { name: 'Kavita', phone });
    const kavita = await employeeSession(phone);
    await ask(owner.token, raju.id, ['pan']).expect(201);
    expect((await forThem(kavita.token, raju.id, 'consent', { staffAgreed: true, slip: photo('x') })).status).toBe(403);
    expect((await api().get(`${V}/verification/employees/${raju.id}/on-behalf`).set(auth(kavita.token))).status).toBe(403);
  });

  it('the signed slip is deleted with the rest 180 days after they leave', async () => {
    const owner = await setup();
    const raju = await addEmployee(owner, { name: 'Raju', phone: nextPhone() });
    await ask(owner.token, raju.id, ['pan']).expect(201);
    await forThem(owner.token, raju.id, 'consent', { staffAgreed: true, slip: photo('signed-slip') }).expect(200);
    const key = (await VerificationRequest.findOne({ companyId: owner.companyId }).lean())!.consent!.slipKey!;
    const company = (await Company.findById(owner.companyId).lean())!;
    await Employee.updateOne({ _id: raju.id, companyId: owner.companyId }, { $set: { exitDate: addDays(todayIn(company.timezone), -200) } });
    await purgeRetention(company, new Date());
    expect(await VerificationRequest.countDocuments({ companyId: owner.companyId })).toBe(0);
    await expect((await storage()).get(key)).rejects.toThrow();
  });
});
