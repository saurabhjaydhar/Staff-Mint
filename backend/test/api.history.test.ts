import { describe, expect, it } from 'vitest';
import { api, auth, V, createOwner, addEmployee } from './helpers.js';

describe('history (audit log) in plain words', () => {
  it('each change is one sentence with names, in English or Hindi, with what changed; filters by kind', async () => {
    const owner = await createOwner();
    const emp = await addEmployee(owner, { name: 'Raju Kumar' });
    await api().post(`${V}/attendance/override`).set(auth(owner.token)).send({ employeeId: emp.id, date: '2026-10-01', status: 'absent', reason: 'Did not come' }).expect(200);
    await api().post(`${V}/advances`).set(auth(owner.token)).send({ employeeId: emp.id, amountPaise: 50000, date: '2026-10-02', mode: 'full_next' }).expect(201);
    await api().patch(`${V}/company/settings`).set(auth(owner.token)).send({ graceMinutes: 20, weekOffsPaid: false }).expect(200);

    const en = (await api().get(`${V}/audit-logs`).set(auth(owner.token)).set('Accept-Language', 'en').expect(200)).body.data;
    const texts = en.map((l: any) => l.text);
    expect(texts).toContain('Raju Kumar: 1 Oct set to Absent');
    expect(texts).toContain('Raju Kumar: advance of ₹500 given');
    expect(texts).toContain('Raju Kumar added');
    expect(texts).toContain('Shop rules changed');
    const override = en.find((l: any) => l.action === 'attendance.override');
    expect(override).toMatchObject({ category: 'attendance' });
    expect(override.changes).toContainEqual({ label: 'Reason', to: 'Did not come' });
    const rules = en.find((l: any) => l.action === 'company.settings.update');
    expect(rules.changes).toContainEqual({ label: 'Late after (minutes)', from: '15', to: '20' });
    expect(rules.changes).toContainEqual({ label: 'Weekly offs are paid', from: 'On', to: 'Off' });
    // No raw codes in the sentences.
    expect(texts.join(' ')).not.toMatch(/attendance\.|employee\.|company\./);

    const hi = (await api().get(`${V}/audit-logs`).set(auth(owner.token)).set('Accept-Language', 'hi').expect(200)).body.data;
    expect(hi.map((l: any) => l.text)).toContain('Raju Kumar: 1 अक्टूबर को ग़ैरहाज़िर किया');
    expect(hi.map((l: any) => l.text)).toContain('Raju Kumar को ₹500 एडवांस दिया');

    const salary = (await api().get(`${V}/audit-logs`).query({ category: 'salary' }).set(auth(owner.token)).expect(200)).body.data;
    expect(salary.length).toBeGreaterThan(0);
    expect(salary.every((l: any) => l.category === 'salary')).toBe(true);
    expect((await api().get(`${V}/audit-logs`).query({ category: 'nonsense' }).set(auth(owner.token))).status).toBe(400);
  });
});
