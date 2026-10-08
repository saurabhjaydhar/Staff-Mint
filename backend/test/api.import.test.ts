import { describe, expect, it } from 'vitest';
import ExcelJS from 'exceljs';
import { api, auth, V, createOwner, addEmployee } from './helpers.js';
import { Advance, Attendance, Employee } from '../src/models/index.js';

async function competitorExcel() {
  const wb = new ExcelJS.Workbook();
  const ws = wb.addWorksheet('Staff');
  ws.addRow(['Sharma Medical — staff list']); // title row above the header
  ws.addRow(['S.No', 'Karmchari Naam', 'Mobile No.', 'Monthly Tankhwah', 'Joining (DD/MM/YYYY)', 'Post', 'Udhaar Baaki']);
  const salaries = ['12k', '₹12,000/-', 15000, '9,500', '11.5k'];
  for (let i = 1; i <= 30; i++) {
    const phone = i % 3 === 0 ? `+91 98${String(10000000 + i).slice(0, 3)} ${String(10000 + i * 7).slice(-5)}` : `98${String(76500000 + i * 13)}`;
    ws.addRow([i, `Staff Member ${String.fromCharCode(64 + ((i - 1) % 26) + 1)}${i}`, phone, salaries[i % salaries.length], `0${(i % 9) + 1}/03/2024`, i % 2 ? 'Helper' : 'Cashier', i === 5 ? '2000' : '']);
  }
  // Two rows that need the owner: bad phone, unreadable salary
  ws.getRow(10).getCell(3).value = '12345';
  ws.getRow(20).getCell(4).value = 'baad mein';
  return Buffer.from(await wb.xlsx.writeBuffer());
}

describe('staff import (switching)', () => {
  it('30-row Excel with non-standard headers imports with ≤ 3 corrections, then undo', async () => {
    const owner = await createOwner({ plan: 'growth' });
    const r = await api().post(`${V}/imports`).set(auth(owner.token)).attach('file', await competitorExcel(), 'staff.xlsx').field('kind', 'staff');
    expect(r.status).toBe(201);
    const s = r.body.data;
    expect(s.totalRows).toBe(30);
    expect(s.mapping).toMatchObject({ 'Karmchari Naam': 'name', 'Mobile No.': 'phone', 'Monthly Tankhwah': 'ratePaise', 'Joining (DD/MM/YYYY)': 'joiningDate', Post: 'designation', 'Udhaar Baaki': 'advanceBalancePaise' });
    expect(s.errorCount).toBeLessThanOrEqual(3);
    const bad = s.rows.filter((x: any) => x.issues.some((i: any) => i.severity === 'error'));
    expect(bad.map((x: any) => x.index).sort((a: number, b: number) => a - b)).toEqual([7, 17]);
    expect(s.rows[0].values).toMatchObject({ ratePaise: 1200000, joiningDate: '2024-03-02' });

    const fixed = await api()
      .patch(`${V}/imports/${s.id}`)
      .set(auth(owner.token))
      .send({ fixes: [{ row: 7, field: 'phone', value: '9811100007' }, { row: 17, field: 'ratePaise', value: '13k' }] });
    expect(fixed.body.data.errorCount).toBe(0);
    const c = await api().post(`${V}/imports/${s.id}/commit`).set(auth(owner.token)).send({});
    expect(c.body.data).toMatchObject({ created: 30, updated: 0, skipped: 0 });
    expect(await Employee.countDocuments({ companyId: owner.companyId, deletedAt: null })).toBe(30);
    expect(await Advance.countDocuments({ companyId: owner.companyId })).toBe(1);
    expect((await api().post(`${V}/imports/${s.id}/commit`).set(auth(owner.token)).send({})).status).toBe(409);

    const rb = await api().post(`${V}/imports/${s.id}/rollback`).set(auth(owner.token));
    expect(rb.body.data.removed).toBe(30);
    expect(await Employee.countDocuments({ companyId: owner.companyId, deletedAt: null })).toBe(0);
  });

  it('pasted WhatsApp text, column remap, and no silent overwrite of existing staff', async () => {
    const owner = await createOwner();
    await addEmployee(owner, { name: 'Old Ramesh', phone: '9876500001', ratePaise: 1000000 });
    const text = 'Ramesh 9876500001 15000\nPooja - 98765 00002 - 12k - helper';
    const r = await api().post(`${V}/imports`).set(auth(owner.token)).send({ text });
    expect(r.status).toBe(201);
    expect(r.body.data.rows[0].issues[0].message).toMatch(/Already in your staff list/);
    const c = await api().post(`${V}/imports/${r.body.data.id}/commit`).set(auth(owner.token)).send({});
    expect(c.body.data).toMatchObject({ created: 1, skipped: 1 });
    const old = await Employee.findOne({ companyId: owner.companyId, phone: '+919876500001' }).lean();
    expect(old).toMatchObject({ name: 'Old Ramesh', ratePaise: 1000000 });

    const r2 = await api().post(`${V}/imports`).set(auth(owner.token)).send({ text: 'Name,Number,Pay\nRamesh,9876500001,16000' });
    const remap = await api().patch(`${V}/imports/${r2.body.data.id}`).set(auth(owner.token)).send({ mapping: { Pay: 'ratePaise' } });
    expect(remap.body.data.mapping.Pay).toBe('ratePaise');
    const c2 = await api().post(`${V}/imports/${r2.body.data.id}/commit`).set(auth(owner.token)).send({ overwriteExisting: true });
    expect(c2.body.data.updated).toBe(1);
    expect((await Employee.findOne({ companyId: owner.companyId, phone: '+919876500001' }).lean())!.ratePaise).toBe(1600000);
  });

  it('imports an attendance history grid (P/A/HD/L/WO codes)', async () => {
    const owner = await createOwner();
    await addEmployee(owner, { name: 'Ramesh', phone: '9876500001' });
    const csv = 'Name,Phone,1,2,3,4\nRamesh,9876500001,P,HD,A,WO\nNobody,9000000000,P,P,P,P\n';
    const r = await api().post(`${V}/imports`).set(auth(owner.token)).attach('file', Buffer.from(csv), 'att.csv').field('kind', 'attendance').field('month', '2026-09');
    expect(r.status).toBe(201);
    expect(r.body.data.errorCount).toBe(1);
    await api().patch(`${V}/imports/${r.body.data.id}`).set(auth(owner.token)).send({ skipRows: [1] }).expect(200);
    const c = await api().post(`${V}/imports/${r.body.data.id}/commit`).set(auth(owner.token)).send({});
    expect(c.body.data.created).toBe(4);
    const recs = await Attendance.find({ companyId: owner.companyId }).sort({ date: 1 }).lean();
    expect(recs.map((x) => x.status)).toEqual(['present', 'half_day', 'absent', 'week_off']);
  });
});
