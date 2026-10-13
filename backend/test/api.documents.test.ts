import { describe, expect, it } from 'vitest';
import { DateTime } from 'luxon';
import { api, auth, V, createOwner, addEmployee, employeeSession, nextPhone, mocks, storage } from './helpers.js';
import { AuditLog, Company, Employee, Notification, StaffDocument } from '../src/models/index.js';
import { purgeRetention, schedulerTick } from '../src/jobs/handlers.js';
import { describe as describeLog } from '../src/modules/audit/describe.js';
import { addDays, todayIn } from '../src/lib/dates.js';

const JPEG = (marker = 'pan-photo') => Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.from(marker)]);
const PDF = Buffer.from('%PDF-1.4 police certificate');
const b64 = (b: Buffer) => b.toString('base64');
const photo = (marker?: string) => ({ data: b64(JPEG(marker)), mime: 'image/jpeg' });

async function setup(plan = 'starter') {
  await mocks();
  const owner = await createOwner({ plan });
  const phone = nextPhone();
  const emp = await addEmployee(owner, { name: 'Ramesh Kumar', phone });
  const staff = await employeeSession(phone);
  return { owner, emp, staff };
}
const addMine = (token: string, body: Record<string, unknown>) => api().post(`${V}/verification/mine/documents`).set(auth(token)).send(body);
const addFor = (token: string, id: string, body: Record<string, unknown>) => api().post(`${V}/verification/employees/${id}/documents`).set(auth(token)).send(body);
const list = (token: string, id: string) => api().get(`${V}/verification/employees/${id}/documents`).set(auth(token));
const open = (token: string, id: string) => api().post(`${V}/verification/documents/${id}/open`).set(auth(token));
const pathOf = (url: string) => new URL(url).pathname;

describe('staff documents', () => {
  it('staff adds a document: stored encrypted, only the last 4 kept, owner opens it through a short link written to History', async () => {
    const { owner, emp, staff } = await setup();
    const add = await addMine(staff.token, { kind: 'aadhaar', number: '2345 6789 1234', files: [photo('aadhaar-front'), photo('aadhaar-back')] }).expect(201);
    expect(add.body.data).toMatchObject({ kind: 'aadhaar', numberLast4: '1234', addedBy: 'staff', files: [{ mime: 'image/jpeg' }, { mime: 'image/jpeg' }] });
    // The owner hears about it.
    expect(await Notification.exists({ companyId: owner.companyId, template: 'document_added' })).toBeTruthy();

    // Encrypted at rest; the full number is nowhere.
    const doc = (await StaffDocument.findOne({ companyId: owner.companyId, employeeId: emp.id }).lean())!;
    const raw = await (await storage()).get(doc.files[0].key);
    expect(raw.includes(Buffer.from('aadhaar-front'))).toBe(false);
    expect(JSON.stringify(doc)).not.toContain('234567891234');
    expect(JSON.stringify(await AuditLog.find({ companyId: owner.companyId }).lean())).not.toContain('234567891234');

    const docs = (await list(owner.token, emp.id).expect(200)).body.data;
    expect(docs).toMatchObject({ agreementOnFile: true, documents: [{ kind: 'aadhaar', numberLast4: '1234' }] });

    const opened = (await open(owner.token, add.body.data.id).expect(200)).body.data;
    expect(opened.files).toHaveLength(2);
    const file = await api().get(pathOf(opened.files[0].url)).expect(200);
    expect(file.headers['content-type']).toBe('image/jpeg');
    expect(Buffer.from(file.body).includes(Buffer.from('aadhaar-front'))).toBe(true);
    // A changed link doesn't open anything.
    await api().get(`${pathOf(opened.files[0].url)}x`).expect(403);
    await api().get('/doc-files/not-a-token').expect(403);

    const viewed = await AuditLog.findOne({ companyId: owner.companyId, action: 'document.view' }).lean();
    expect(viewed).toBeTruthy();
    const look = { employeeName: () => 'Ramesh Kumar' } as any;
    expect(describeLog(viewed!, 'en', look)?.text).toBe('Ramesh Kumar: Aadhaar opened');
    expect(describeLog(viewed!, 'hi', look)?.text).toBe('Ramesh Kumar: आधार खोला');

    // Staff see their own, and can remove what they added.
    const mine = (await api().get(`${V}/verification/mine/documents`).set(auth(staff.token)).expect(200)).body.data;
    expect(mine.documents).toHaveLength(1);
    await open(staff.token, add.body.data.id).expect(200);
    await api().delete(`${V}/verification/documents/${add.body.data.id}`).set(auth(staff.token)).expect(200);
    expect(await StaffDocument.countDocuments({ companyId: owner.companyId })).toBe(0);
    await expect((await storage()).get(doc.files[0].key)).rejects.toThrow();
  });

  it('only photos and PDFs; "other" needs a name; Aadhaar numbers are digits', async () => {
    const { staff } = await setup();
    expect((await addMine(staff.token, { kind: 'pan', files: [{ data: b64(Buffer.from('MZ not an image')), mime: 'image/jpeg' }] })).status).toBe(400);
    expect((await addMine(staff.token, { kind: 'pan', files: [{ data: b64(JPEG()), mime: 'text/html' }] })).status).toBe(400);
    expect((await addMine(staff.token, { kind: 'other', files: [photo()] })).status).toBe(400);
    expect((await addMine(staff.token, { kind: 'aadhaar', number: 'ABCD12341234', files: [photo()] })).status).toBe(400);
    await addMine(staff.token, { kind: 'other', label: '10th marksheet', files: [{ data: b64(PDF), mime: 'application/pdf' }] }).expect(201);
    // 4 MB each, 7 MB together.
    const big = { data: b64(Buffer.concat([JPEG(), Buffer.alloc(3_900_000)])), mime: 'image/jpeg' };
    expect((await addMine(staff.token, { kind: 'pan', files: [big, big] })).body.error.message).toMatch(/7 MB/);
  });

  it('owner adds for staff without a phone: they must agree, with a signed slip the first time', async () => {
    const { owner } = await setup();
    const raju = await addEmployee(owner, { name: 'Raju', phone: nextPhone() });
    const noTick = await addFor(owner.token, raju.id, { kind: 'pan', files: [photo()], staffAgreed: false });
    expect(noTick.body.error.code).toBe('CONSENT_REQUIRED');
    const noSlip = await addFor(owner.token, raju.id, { kind: 'pan', files: [photo()], staffAgreed: true });
    expect(noSlip.status).toBe(400);
    expect(noSlip.body.error.message).toMatch(/consent slip/);
    const first = await addFor(owner.token, raju.id, { kind: 'pan', number: 'ABCDE1234F', files: [photo()], staffAgreed: true, slip: photo('slip') }).expect(201);
    expect(first.body.data).toMatchObject({ addedBy: 'owner', hasSlip: true, numberLast4: '234F' });
    // Next time the slip on file is enough.
    await addFor(owner.token, raju.id, { kind: 'bank_proof', files: [photo()], staffAgreed: true }).expect(201);
    const opened = (await open(owner.token, first.body.data.id).expect(200)).body.data;
    expect(opened.slip).toMatchObject({ mime: 'image/jpeg' });

    const added = await AuditLog.findOne({ companyId: owner.companyId, action: 'document.add' }).sort({ at: 1 }).lean();
    expect(describeLog(added!, 'en', { employeeName: () => 'Raju' } as any)).toMatchObject({ text: 'Raju: PAN added', changes: [{ label: 'Consent', to: 'Signed slip added' }] });
  });

  it('owners only: staff can’t see or remove others’ documents, nor remove what the owner added', async () => {
    const { owner, emp, staff } = await setup();
    const phone = nextPhone();
    await addEmployee(owner, { name: 'Kavita', phone });
    const other = await employeeSession(phone);
    const d = (await addFor(owner.token, emp.id, { kind: 'pan', files: [photo()], staffAgreed: true, slip: photo('slip') }).expect(201)).body.data;
    expect((await list(staff.token, emp.id)).status).toBe(403);
    expect((await open(other.token, d.id)).status).toBe(404);
    // Ramesh can open his own, but the slip is the owner's.
    expect((await open(staff.token, d.id).expect(200)).body.data.slip).toBeNull();
    expect((await api().delete(`${V}/verification/documents/${d.id}`).set(auth(staff.token))).status).toBe(403);
  });

  it('needs a paid plan', async () => {
    const { staff, owner, emp } = await setup('free');
    expect((await addMine(staff.token, { kind: 'pan', files: [photo()] })).body.error.code).toBe('FEATURE_NOT_IN_PLAN');
    expect((await addFor(owner.token, emp.id, { kind: 'pan', files: [photo()], staffAgreed: true, slip: photo() })).status).toBe(402);
  });

  it('a licence running out within 30 days reminds the owner and the staff member once; a new date reminds again', async () => {
    const { owner, emp, staff } = await setup();
    const company = (await Company.findById(owner.companyId).lean())!;
    const today = todayIn(company.timezone);
    const d = (await addMine(staff.token, { kind: 'dl', expiresOn: addDays(today, 10), files: [photo()] }).expect(201)).body.data;
    expect(d.expiry).toBe('soon');
    await addMine(staff.token, { kind: 'passport', expiresOn: addDays(today, 400), files: [photo()] }).expect(201);
    // 11 AM company time.
    const at = DateTime.fromISO(`${today}T11:00`, { zone: company.timezone }).toJSDate();
    await schedulerTick(at);
    await schedulerTick(at);
    // Remembered, so the next tick the same day sends nothing.
    expect((await Company.findById(owner.companyId).lean())!.jobState?.lastDocExpiryDate).toBe(today);
    const sent = await Notification.find({ companyId: owner.companyId, template: 'document_expiring' }).lean();
    const on = DateTime.fromISO(addDays(today, 10)).setLocale('hi').toFormat('d LLLL yyyy');
    // The business speaks Hindi (the default).
    expect(sent.map((n) => n.title).sort()).toEqual([`Ramesh Kumar का ड्राइविंग लाइसेंस ${on} को ख़त्म होगा`, `आपका ड्राइविंग लाइसेंस ${on} को ख़त्म होगा`]);
    expect(sent.find((n) => n.title?.startsWith('आपका'))!.body).toMatch(/मेरे दस्तावेज़/);
    // The owner fixes the date (new licence) → it reminds again when that one runs out.
    await api().patch(`${V}/verification/documents/${d.id}`).set(auth(owner.token)).send({ expiresOn: addDays(today, 5) }).expect(200);
    await Company.updateOne({ _id: owner.companyId }, { $unset: { 'jobState.lastDocExpiryDate': '' } });
    await schedulerTick(at);
    expect(await Notification.countDocuments({ companyId: owner.companyId, template: 'document_expiring' })).toBe(4);
    expect((await list(owner.token, emp.id)).body.data.documents.map((x: any) => x.expiry).sort()).toEqual(['ok', 'soon']);
  });

  it('deleted with their files 180 days after the person leaves', async () => {
    const { owner, emp, staff } = await setup();
    await addMine(staff.token, { kind: 'pan', files: [photo()] }).expect(201);
    const key = (await StaffDocument.findOne({ companyId: owner.companyId }).lean())!.files[0].key;
    const company = (await Company.findById(owner.companyId).lean())!;
    await Employee.updateOne({ _id: emp.id, companyId: owner.companyId }, { $set: { exitDate: addDays(todayIn(company.timezone), -100) } });
    await purgeRetention(company, new Date());
    expect(await StaffDocument.countDocuments({ companyId: owner.companyId })).toBe(1);
    await Employee.updateOne({ _id: emp.id, companyId: owner.companyId }, { $set: { exitDate: addDays(todayIn(company.timezone), -200) } });
    await purgeRetention(company, new Date());
    expect(await StaffDocument.countDocuments({ companyId: owner.companyId })).toBe(0);
    await expect((await storage()).get(key)).rejects.toThrow();
  });
});
