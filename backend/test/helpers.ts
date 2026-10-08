import request from 'supertest';
import { randomUUID } from 'node:crypto';
import { createApp } from '../src/app.js';
import { Subscription, Employee, OtpRequest } from '../src/models/index.js';
import { normalizePhone } from '../src/lib/phone.js';
import { provider, setProvider } from '../src/providers/registry.js';
import { MockMessagingProvider } from '../src/providers/messaging/mock.js';
import { MockPushProvider } from '../src/providers/push/mock.js';

export const app = createApp();
export const api = () => request(app);
export const V = '/api/v1';

let phoneSeq = 0;
export const nextPhone = () => `98${String(70000000 + ++phoneSeq + Math.floor(Math.random() * 1000) * 1000).padStart(8, '0')}`;

export const auth = (token: string) => ({ Authorization: `Bearer ${token}` });

export async function otpLogin(phone: string, deviceId = `dev-${randomUUID()}`) {
  await OtpRequest.deleteMany({ phone: normalizePhone(phone) }); // bypass resend throttling between logins in tests
  const r1 = await api().post(`${V}/auth/otp/request`).send({ phone });
  if (r1.status !== 200) throw new Error(`otp request failed: ${r1.status} ${JSON.stringify(r1.body)}`);
  const r2 = await api().post(`${V}/auth/otp/verify`).send({ phone, code: r1.body.data.devCode, deviceId });
  return { res: r2, deviceId, ...(r2.body.data ?? {}) };
}

export interface OwnerSession {
  token: string;
  refreshToken: string;
  companyId: string;
  userId: string;
  phone: string;
}

/** Owner with company at Connaught Place (28.6139, 77.2090), shift 09:00–18:00, Sunday off. */
export async function createOwner(opts: { plan?: string; setup?: Record<string, unknown> } = {}): Promise<OwnerSession> {
  const phone = nextPhone();
  const login = await otpLogin(phone);
  const r = await api()
    .post(`${V}/company`)
    .set(auth(login.accessToken))
    .send({ name: 'Test Shop', businessType: 'pharmacy', location: { lat: 28.6139, lng: 77.209 }, openingTime: '09:00', closingTime: '18:00', weeklyOff: [0], ...(opts.setup ?? {}) });
  if (r.status !== 201) throw new Error(`setup failed ${r.status} ${JSON.stringify(r.body)}`);
  const s: OwnerSession = { token: r.body.data.accessToken, refreshToken: r.body.data.refreshToken, companyId: r.body.data.company.id, userId: login.user.id, phone };
  if (opts.plan) await setPlan(s.companyId, opts.plan);
  return s;
}

export async function setPlan(companyId: string, planCode: string) {
  await Subscription.updateMany({ companyId }, { status: 'cancelled', currentPeriodEnd: new Date(0) });
  if (planCode !== 'free') {
    await Subscription.create({ companyId, provider: 'internal', planCode, status: 'active', currentPeriodEnd: new Date(Date.now() + 30 * 86400_000) });
  }
}

export async function addEmployee(owner: OwnerSession, data: Record<string, unknown> = {}) {
  const r = await api()
    .post(`${V}/employees`)
    .set(auth(owner.token))
    .send({ name: 'Ramesh Kumar', phone: nextPhone(), ratePaise: 1200000, ...data });
  if (r.status !== 201) throw new Error(`add employee failed ${r.status} ${JSON.stringify(r.body)}`);
  return r.body.data;
}

/** Employee logs in on a device and gives location consent. */
export async function employeeSession(phone: string, deviceId = `dev-${randomUUID()}`) {
  const login = await otpLogin(phone, deviceId);
  if (login.res.status !== 200) throw new Error(`employee login failed ${JSON.stringify(login.res.body)}`);
  await api().post(`${V}/me/consent`).set(auth(login.accessToken)).send({ location: true });
  return { token: login.accessToken as string, deviceId, user: login.user };
}

export const punchBody = (deviceId: string, over: Record<string, unknown> = {}) => ({
  clientTime: new Date().toISOString(),
  geo: { lat: 28.6139, lng: 77.209, accuracyM: 12 },
  mockLocation: false,
  deviceId,
  selfieBase64: Buffer.from('fake-jpeg').toString('base64'),
  clientPunchId: randomUUID(),
  ...over,
});

export async function mocks() {
  const messaging = new MockMessagingProvider();
  const push = new MockPushProvider();
  setProvider('messaging', messaging);
  setProvider('push', push);
  return { messaging, push };
}

export async function storage() {
  return provider('storage');
}

export async function setJoining(employeeId: string, date: string) {
  await Employee.updateOne({ _id: employeeId }, { joiningDate: date }).setOptions({ skipTenant: true });
}
