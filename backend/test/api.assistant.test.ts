import { describe, expect, it } from 'vitest';
import { api, auth, V, createOwner, addEmployee, employeeSession, nextPhone, mocks, setPlan } from './helpers.js';
import { Attendance, AuditLog, Employee, AssistantSession } from '../src/models/index.js';
import { setProvider } from '../src/providers/registry.js';
import type { LlmProvider } from '../src/providers/types.js';

const say = (token: string, text: string, sessionId?: string) => api().post(`${V}/assistant/message`).set(auth(token)).send({ text, sessionId });
const act = (token: string, pendingActionId: string, action: string, optionId?: string) => api().post(`${V}/assistant/confirm`).set(auth(token)).send({ pendingActionId, action, optionId });

async function shop() {
  const owner = await createOwner();
  const ramesh1 = await addEmployee(owner, { name: 'Ramesh Kumar' });
  const ramesh2 = await addEmployee(owner, { name: 'Ramesh Gupta' });
  const suresh = await addEmployee(owner, { name: 'Suresh Yadav' });
  return { owner, ramesh1, ramesh2, suresh };
}

describe('Mint assistant', () => {
  it('never writes before confirmation; confirm writes with assistant channel audit', async () => {
    const { owner, suresh } = await shop();
    const r = await say(owner.token, 'Suresh aaj nahi aaya');
    expect(r.body.data).toMatchObject({ kind: 'confirm', intent: 'mark_attendance' });
    expect(r.body.data.preview.rows.find((x: any) => x.label === 'Staff').value).toBe('Suresh Yadav');
    expect(await Attendance.countDocuments({ companyId: owner.companyId })).toBe(0);
    const done = await act(owner.token, r.body.data.pendingActionId, 'confirm');
    expect(done.body.data.kind).toBe('done');
    const rec = await Attendance.findOne({ companyId: owner.companyId, employeeId: suresh.id }).lean();
    expect(rec).toMatchObject({ status: 'absent', overridden: true });
    const log = await AuditLog.findOne({ companyId: owner.companyId, action: 'attendance.override' }).lean();
    expect(log!.channel).toBe('assistant');
    // A pending action cannot be executed twice
    expect((await act(owner.token, r.body.data.pendingActionId, 'confirm')).body.data.kind).toBe('error');
  });

  it('ambiguous names ask with buttons; cancel saves nothing', async () => {
    const { owner, ramesh2 } = await shop();
    const r = await say(owner.token, 'Ramesh ko aaj half day laga do');
    expect(r.body.data.kind).toBe('choose');
    expect(r.body.data.options).toHaveLength(2);
    const c = await act(owner.token, r.body.data.pendingActionId, 'choose', ramesh2.id);
    expect(c.body.data.kind).toBe('confirm');
    expect(c.body.data.preview.rows[0].value).toBe('Ramesh Gupta');
    const x = await act(owner.token, c.body.data.pendingActionId, 'cancel');
    expect(x.body.data.kind).toBe('cancelled');
    expect(await Attendance.countDocuments({ companyId: owner.companyId })).toBe(0);
  });

  it('unknown staff and low-confidence input never guess', async () => {
    const { owner } = await shop();
    expect((await say(owner.token, 'Mohan ko 5000 advance diya')).body.data.kind).toBe('error');
    const r = await say(owner.token, 'aaj mausam kaisa hai');
    expect(r.body.data).toMatchObject({ kind: 'answer', intent: null });
  });

  it('add employee, advance, bonus, holiday, who-is and help', async () => {
    const { owner, suresh } = await shop();
    const add = await say(owner.token, 'Naya banda Pooja 9876543210 12000');
    expect(add.body.data.kind).toBe('confirm');
    // "haan" confirms the open action (WhatsApp-friendly)
    const yes = await say(owner.token, 'haan', add.body.data.sessionId);
    expect(yes.body.data.kind).toBe('done');
    expect(await Employee.findOne({ companyId: owner.companyId, phone: '+919876543210' }).lean()).toMatchObject({ name: 'Pooja', ratePaise: 1200000 });

    const adv = await say(owner.token, 'Suresh ko 5000 advance diya');
    expect(adv.body.data.preview.rows.find((x: any) => x.value === '₹5,000')).toBeTruthy();
    const done = await act(owner.token, adv.body.data.pendingActionId, 'confirm');
    expect(done.body.data.text).toMatch(/5,000/);

    const bonus = await say(owner.token, 'Suresh ko 500 bonus');
    expect((await act(owner.token, bonus.body.data.pendingActionId, 'confirm')).body.data.kind).toBe('done');

    const hol = await say(owner.token, 'Kal sabki chutti hai');
    expect((await act(owner.token, hol.body.data.pendingActionId, 'confirm')).body.data.kind).toBe('done');

    await api().post(`${V}/attendance/override`).set(auth(owner.token)).send({ employeeId: suresh.id, date: (await api().get(`${V}/dashboard/today`).set(auth(owner.token))).body.data.date, status: 'absent', reason: 'test data' });
    const who = await say(owner.token, 'aaj kaun absent hai');
    expect(who.body.data).toMatchObject({ kind: 'answer', intent: 'who_is' });
    expect(who.body.data.text).toContain('Suresh Yadav');
    expect((await say(owner.token, 'Kya kya kar sakte ho?')).body.data.text).toMatch(/half day/i);
  });

  it('pending actions expire', async () => {
    const { owner } = await shop();
    const r = await say(owner.token, 'Suresh aaj nahi aaya');
    await AssistantSession.updateOne({ companyId: owner.companyId, 'pending.id': r.body.data.pendingActionId }, { $set: { 'pending.$.expiresAt': new Date(Date.now() - 1000) } });
    expect((await act(owner.token, r.body.data.pendingActionId, 'confirm')).body.data.kind).toBe('error');
    expect(await Attendance.countDocuments({ companyId: owner.companyId })).toBe(0);
  });

  it('falls back to the configured LLM when rules are unsure — still confirm-before-write', async () => {
    const { owner } = await shop();
    const fake: LlmProvider = { name: 'fake-gemini', extract: async () => ({ intent: 'mark_attendance', args: { employeeName: 'Suresh', status: 'present' }, confidence: 0.9, provider: 'fake-gemini' }) };
    setProvider('llm', fake);
    const r = await say(owner.token, 'woh suresh wala banda aaj time pe aa gaya tha bhai');
    expect(r.body.data).toMatchObject({ kind: 'confirm', intent: 'mark_attendance' });
    expect(await Attendance.countDocuments({ companyId: owner.companyId })).toBe(0);
  });

  it('employee intents and plan gating', async () => {
    const owner = await createOwner();
    const phone = nextPhone();
    await addEmployee(owner, { phone, ratePaise: 3000000 });
    const e = await employeeSession(phone);
    const r = await say(e.token, 'Meri salary kitni bani?');
    expect(r.body.data).toMatchObject({ kind: 'answer', intent: 'my_salary' });
    const leave = await say(e.token, 'kal chutti chahiye');
    expect(leave.body.data.kind).toBe('confirm');
    expect((await act(e.token, leave.body.data.pendingActionId, 'confirm')).body.data.kind).toBe('done');
    // Employees cannot run owner tools
    expect((await say(e.token, 'Suresh ko 5000 advance diya')).body.data.kind).not.toBe('confirm');
    await setPlan(owner.companyId, 'free');
    const blocked = await say(owner.token, 'help');
    expect(blocked.status).toBe(402);
  });
});

describe('WhatsApp owner commands (same Mint brain)', () => {
  it('inbound text → confirm buttons → button tap executes', async () => {
    const { messaging } = await mocks();
    const { owner, suresh } = await shop();
    await setPlan(owner.companyId, 'growth');
    const wait = async (n: number) => {
      for (let i = 0; i < 50 && messaging.outbox.length < n; i++) await new Promise((r) => setTimeout(r, 20));
    };
    await api().post(`${V}/webhooks/messaging/mock`).send({ from: `+91${owner.phone}`, text: 'Suresh aaj nahi aaya', id: 'wamid.1' }).expect(200);
    await wait(1);
    const msg = messaging.outbox[0];
    expect(msg.kind).toBe('buttons');
    const confirmBtn = msg.buttons!.find((b) => b.id.endsWith(':confirm'))!;
    await api().post(`${V}/webhooks/messaging/mock`).send({ from: `+91${owner.phone}`, buttonId: confirmBtn.id, id: 'wamid.2' }).expect(200);
    await wait(2);
    expect(messaging.outbox[1].text).toMatch(/Suresh Yadav/);
    const rec = await Attendance.findOne({ companyId: owner.companyId, employeeId: suresh.id }).lean();
    expect(rec!.status).toBe('absent');
    const log = await AuditLog.findOne({ companyId: owner.companyId, action: 'attendance.override' }).lean();
    expect(log!.channel).toBe('whatsapp');
  });

  it('unknown numbers get a polite reply; Meta verification handshake', async () => {
    const { messaging } = await mocks();
    await api().post(`${V}/webhooks/messaging/mock`).send({ from: '+919000000001', text: 'hi' }).expect(200);
    for (let i = 0; i < 50 && !messaging.outbox.length; i++) await new Promise((r) => setTimeout(r, 20));
    expect(messaging.outbox[0].text).toMatch(/not registered/);
    const v = await api().get(`${V}/webhooks/messaging/meta?hub.mode=subscribe&hub.verify_token=fake-verify-token&hub.challenge=42`);
    expect(v.text).toBe('42');
    expect((await api().get(`${V}/webhooks/messaging/meta?hub.mode=subscribe&hub.verify_token=wrong&hub.challenge=42`)).status).toBe(403);
  });
});
