import { describe, expect, it } from 'vitest';
import { api, auth, V, createOwner, addEmployee, employeeSession, nextPhone, mocks } from './helpers.js';
import { AuditLog, Employee, User, VerificationCheck } from '../src/models/index.js';
import { setProvider } from '../src/providers/registry.js';
import { MockVerificationProvider } from '../src/providers/verification/mock.js';
import { describe as describeLog } from '../src/modules/audit/describe.js';
import { decryptField } from '../src/lib/crypto.js';

const look = { employeeName: () => 'Ramesh Kumar' } as any;
const check = (data: any, kind: string) => data.checks.find((c: any) => c.kind === kind);

async function setup() {
  await mocks();
  setProvider('verification', new MockVerificationProvider());
  return createOwner({ plan: 'growth' });
}
const ask = (token: string, id: string, kinds: string[]) => api().post(`${V}/verification/employees/${id}`).set(auth(token)).send({ kinds });
const step = (token: string, path: string, body: Record<string, unknown> = {}) => api().post(`${V}/verification/mine/${path}`).set(auth(token)).send(body);
const forThem = (token: string, id: string, path: string, body: Record<string, unknown> = {}) =>
  api().post(`${V}/verification/employees/${id}/on-behalf/${path}`).set(auth(token)).send(body);

describe('driving licence, voter ID and UAN', () => {
  it('checks each against the record, keeps only the last 4, lists past jobs from the PF record and fills the UAN', async () => {
    const owner = await setup();
    const phone = nextPhone();
    const emp = await addEmployee(owner, { name: 'Ramesh Kumar', phone });
    const staff = await employeeSession(phone);
    await ask(owner.token, emp.id, ['dl', 'voter', 'uan']).expect(201);

    // Staff only see the consent lines for what was asked.
    let me = (await api().get(`${V}/verification/mine`).set(auth(staff.token)).expect(200)).body.data;
    expect(me.checks.map((c: any) => c.kind)).toEqual(['dl', 'voter', 'uan']);
    const consent = me.consentText.en.join(' ');
    expect(consent).toMatch(/Driving licence/);
    expect(consent).toMatch(/places you worked before/);
    expect(consent).not.toMatch(/Aadhaar|₹1/);
    expect(me.consentText.hi).toHaveLength(me.consentText.en.length);
    expect(me.savedUanLast4).toBeNull();

    await step(staff.token, 'dl', { number: 'DL0420191234567', dob: '1995-04-12' }).expect(403); // agree first
    await step(staff.token, 'consent').expect(200);

    // Licence: bad number, wrong date of birth (not found), then found.
    expect((await step(staff.token, 'dl', { number: 'DL04', dob: '1995-04-12' })).status).toBe(400);
    expect((await step(staff.token, 'dl', { number: 'DL0420191234567', dob: '2099-01-01' })).status).toBe(400);
    me = (await step(staff.token, 'dl', { number: 'DL04 2019 1234567', dob: '2000-01-01' }).expect(200)).body.data;
    expect(check(me, 'dl')).toMatchObject({ status: 'not_found', last4: '4567', attempts: 1 });
    me = (await step(staff.token, 'dl', { number: 'dl-04-2019-1234567', dob: '1995-04-12' }).expect(200)).body.data;
    expect(check(me, 'dl')).toMatchObject({ status: 'verified', last4: '4567', details: null });

    // Voter ID held under another name: the owner decides.
    expect((await step(staff.token, 'voter', { epic: 'AB12345678' })).status).toBe(400);
    me = (await step(staff.token, 'voter', { epic: 'abc1234569' }).expect(200)).body.data;
    expect(check(me, 'voter')).toMatchObject({ status: 'mismatch', last4: '4569' });

    // UAN: typed, verified, past employers for the owner only, saved to the profile.
    me = (await step(staff.token, 'uan', { uan: '1012 3456 7891' }).expect(200)).body.data;
    expect(check(me, 'uan')).toMatchObject({ status: 'verified', last4: '7891', employers: null });
    expect((await Employee.findOne({ _id: emp.id, companyId: owner.companyId }).lean())!.uan).toBe('101234567891');

    const view = (await api().get(`${V}/verification/employees/${emp.id}`).set(auth(owner.token)).expect(200)).body.data;
    expect(view.badge).toBe('needs_attention');
    expect(check(view, 'dl').details).toEqual({ validTill: '2034-05-20', state: 'Delhi' });
    expect(check(view, 'voter')).toMatchObject({ nameOnRecord: 'Rajesh Kumar Sharma' });
    expect(check(view, 'uan').employers).toEqual([
      { name: 'City Mart Pvt Ltd', joined: '2022-04-15', left: '2025-12-31' },
      { name: 'Sharma Traders', joined: '2019-06-01', left: '2022-03-31' },
    ]);
    // Nothing but the last 4 is stored in the clear; past jobs are encrypted with the rest.
    const raw = (await VerificationCheck.findOne({ companyId: owner.companyId, kind: 'uan' }).lean())!;
    expect(JSON.stringify(raw)).not.toMatch(/101234567891|Sharma Traders/);
    expect(JSON.parse(decryptField(raw.detailsEnc!)).employers).toHaveLength(2);

    await api().post(`${V}/verification/checks/${check(view, 'voter').id}/accept`).set(auth(owner.token)).send({ reason: 'Full name on the card' }).expect(200);
    const after = (await api().get(`${V}/verification/employees/${emp.id}`).set(auth(owner.token)).expect(200)).body.data;
    expect(after.badge).toBe('verified');

    // History reads plainly.
    const logs = await AuditLog.find({ companyId: owner.companyId, action: 'verification.check' }).sort({ createdAt: 1 }).lean();
    expect(logs.map((l) => describeLog(l as any, 'en', look)!.text)).toEqual([
      'Ramesh Kumar: driving licence not found',
      'Ramesh Kumar: driving licence verified',
      'Ramesh Kumar: voter ID name doesn’t match',
      'Ramesh Kumar: PF number (UAN) verified',
    ]);
  });

  it('uses the UAN already in the profile, and the owner can do the steps with staff who have no app', async () => {
    const owner = await setup();
    const emp = await addEmployee(owner, { name: 'Sunita Devi', phone: nextPhone() });
    await Employee.updateOne({ _id: emp.id, companyId: owner.companyId }, { $set: { uan: '100987654321' } });
    await ask(owner.token, emp.id, ['uan', 'voter']).expect(201);
    await forThem(owner.token, emp.id, 'uan').expect(403);
    await forThem(owner.token, emp.id, 'consent', { staffAgreed: true, slip: { data: Buffer.from([0xff, 0xd8, 0xff, 0xe0, 1, 2]).toString('base64'), mime: 'image/jpeg' } }).expect(200);
    let me = (await api().get(`${V}/verification/employees/${emp.id}/on-behalf`).set(auth(owner.token)).expect(200)).body.data;
    expect(me.savedUanLast4).toBe('4321');
    me = (await forThem(owner.token, emp.id, 'uan').expect(200)).body.data;
    expect(check(me, 'uan')).toMatchObject({ status: 'verified', last4: '4321' });
    me = (await forThem(owner.token, emp.id, 'voter', { epic: 'XYZ1230000' }).expect(200)).body.data;
    expect(check(me, 'voter')).toMatchObject({ status: 'not_found' });
  });
});

describe('documents check report', () => {
  it('is a PDF for owners, written to History; 404 before any check; staff cannot get it', async () => {
    const owner = await setup();
    await User.updateOne({ _id: owner.userId }, { $set: { language: 'en' } });
    const phone = nextPhone();
    const emp = await addEmployee(owner, { name: 'Ramesh Kumar', phone });
    const staff = await employeeSession(phone);
    await api().get(`${V}/verification/employees/${emp.id}/report.pdf`).set(auth(owner.token)).expect(404);
    await ask(owner.token, emp.id, ['pan', 'uan']).expect(201);
    await step(staff.token, 'consent').expect(200);
    await step(staff.token, 'pan', { pan: 'ABCDE1234F' }).expect(200);
    await step(staff.token, 'uan', { uan: '101234567891' }).expect(200);

    const res = await api()
      .get(`${V}/verification/employees/${emp.id}/report.pdf`)
      .set(auth(owner.token))
      .buffer(true)
      .parse((r, cb) => {
        const chunks: Buffer[] = [];
        r.on('data', (c: Buffer) => chunks.push(c));
        r.on('end', () => cb(null, Buffer.concat(chunks)));
      })
      .expect(200);
    expect(res.headers['content-type']).toMatch(/application\/pdf/);
    expect(res.headers['content-disposition']).toMatch(/documents-check-ramesh-kumar\.pdf/);
    const pdf = (res.body as Buffer).toString('latin1');
    expect(pdf.startsWith('%PDF')).toBe(true);
    expect(pdf).toMatch(/Documents check report/);
    expect(pdf).toMatch(/Sharma Traders/);
    expect(pdf).toMatch(/ending 7891/);
    expect(pdf).not.toMatch(/101234567891/);

    await api().get(`${V}/verification/employees/${emp.id}/report.pdf`).set(auth(staff.token)).expect(403);

    // The app opens a 5-minute link in the phone's browser.
    const { url } = (await api().post(`${V}/verification/employees/${emp.id}/report/open`).set(auth(owner.token)).expect(200)).body.data;
    const path = new URL(url).pathname;
    expect(path).toMatch(/^\/doc-files\/report\//);
    const viaLink = await api().get(path).buffer(true).parse((r, cb) => {
      const chunks: Buffer[] = [];
      r.on('data', (c: Buffer) => chunks.push(c));
      r.on('end', () => cb(null, Buffer.concat(chunks)));
    });
    expect(viaLink.status).toBe(200);
    expect((viaLink.body as Buffer).toString('latin1')).toMatch(/Documents check report/);
    await api().get(path.replace(/.$/, (c) => (c === 'a' ? 'b' : 'a'))).expect(403);
    await api().post(`${V}/verification/employees/${emp.id}/report/open`).set(auth(staff.token)).expect(403);
    expect(await AuditLog.countDocuments({ companyId: owner.companyId, action: 'verification.report' })).toBe(2);
    const log = (await AuditLog.findOne({ companyId: owner.companyId, action: 'verification.report' }).lean())!;
    expect(describeLog(log as any, 'en', look)!.text).toBe('Ramesh Kumar: documents check report downloaded');
  });
});
