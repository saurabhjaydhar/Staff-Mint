import { describe, expect, it } from 'vitest';
import { formatINR, parseAmountToPaise, roundToRupee } from '../src/lib/money.js';
import { normalizePhone } from '../src/lib/phone.js';
import { daysInMonth, previousMonth, weekdayOf, zonedInstant } from '../src/lib/dates.js';
import { decryptField, encryptField } from '../src/lib/crypto.js';
import { distanceMeters } from '../src/lib/geo.js';
import { parseDateLoose, readPastedText, parseDelimited } from '../src/modules/imports/parse.js';
import { autoMap, cleanRows, dayColumns, parseAttendanceCode } from '../src/modules/imports/mapping.js';

describe('money', () => {
  it.each([
    ['12000', 1200000],
    ['12,000', 1200000],
    ['₹12,000/-', 1200000],
    ['12k', 1200000],
    ['12.5K', 1250000],
    ['1.2 lakh', 12000000],
    ['Rs. 9500', 950000],
    ['15 hazaar', 1500000],
    [8000, 800000],
    ['abc', null],
    ['', null],
  ])('parses %s', (input, expected) => expect(parseAmountToPaise(input)).toBe(expected));
  it('formats with Indian grouping', () => {
    expect(formatINR(1234567800)).toBe('₹1,23,45,678');
    expect(formatINR(1050)).toBe('₹10.50');
  });
  it('rounds to rupee', () => {
    expect(roundToRupee(1083871)).toBe(1083900);
    expect(roundToRupee(-28649)).toBe(-28600);
  });
});

describe('phone', () => {
  it.each([
    ['9876543210', '+919876543210'],
    ['+91 98765 43210', '+919876543210'],
    ['09876543210', '+919876543210'],
    ['919876543210', '+919876543210'],
    ['9.87654321E9', '+919876543210'],
    ['12345', null],
    ['5876543210', null],
  ])('normalizes %s', (raw, expected) => expect(normalizePhone(raw)).toBe(expected));
  it('handles UAE numbers when country is AE', () => expect(normalizePhone('501234567', 'AE')).toBe('+971501234567'));
});

describe('dates & geo & crypto', () => {
  it('month helpers', () => {
    expect(daysInMonth('2026-02')).toBe(28);
    expect(previousMonth('2026-01')).toBe('2025-12');
    expect(weekdayOf('2026-10-04')).toBe(0);
  });
  it('zoned instant respects timezone', () => expect(zonedInstant('2026-10-08', '09:00', 'Asia/Kolkata').toISOString()).toBe('2026-10-08T03:30:00.000Z'));
  it('haversine distance', () => {
    const d = distanceMeters({ lat: 28.6139, lng: 77.209 }, { lat: 28.6148, lng: 77.209 });
    expect(d).toBeGreaterThan(95);
    expect(d).toBeLessThan(105);
  });
  it('field encryption roundtrip', () => {
    const enc = encryptField('{"account":"1234"}');
    expect(enc.startsWith('v1:')).toBe(true);
    expect(decryptField(enc)).toBe('{"account":"1234"}');
  });
});

describe('import parsing & mapping', () => {
  it('parses DD/MM dates by default and Excel serials', () => {
    expect(parseDateLoose('05/03/2024')).toBe('2024-03-05');
    expect(parseDateLoose('5-3-24')).toBe('2024-03-05');
    expect(parseDateLoose('12 Jan 2024')).toBe('2024-01-12');
    expect(parseDateLoose(45292)).toBe('2024-01-01');
  });
  it('parses quoted CSV and detects delimiters', () => {
    expect(parseDelimited('a,b\n"x, y",2\n')).toEqual([['a', 'b'], ['x, y', '2']]);
    expect(parseDelimited('a\tb\n1\t2')).toEqual([['a', 'b'], ['1', '2']]);
  });
  it('parses pasted WhatsApp lines', () => {
    const t = readPastedText('1. Pooja - 98765 43210 - 12k - helper\nRamesh 9876500001 ₹15,000/-');
    expect(t.rows[0]).toMatchObject({ Name: 'Pooja', Salary: '12k', Designation: 'helper' });
    expect(t.rows[1]).toMatchObject({ Name: 'Ramesh' });
    expect(normalizePhone(t.rows[0].Phone)).toBe('+919876543210');
  });
  it('maps Hindi/English synonym headers and sniffs unknown columns', () => {
    const headers = ['Karmchari ka Naam', 'Mob No.', 'Tankhwah', 'DOJ', 'Col5'];
    const rows = [{ 'Karmchari ka Naam': 'Ramesh', 'Mob No.': '9876543210', Tankhwah: '12k', DOJ: '01/02/2024', Col5: 'monthly' }];
    const { mapping } = autoMap(headers, rows);
    expect(mapping).toMatchObject({ 'Karmchari ka Naam': 'name', 'Mob No.': 'phone', Tankhwah: 'ratePaise', DOJ: 'joiningDate', Col5: 'wageType' });
  });
  it('detects competitor templates', () => {
    const headers = ['Staff Name', 'Phone Number', 'Salary Type', 'Salary Amount'];
    expect(autoMap(headers, []).template).toBe('salarybox');
  });
  it('flags invalid rows, duplicates and daily-looking salaries', () => {
    const mapping = { N: 'name', P: 'phone', S: 'ratePaise' } as any;
    const rows = cleanRows(
      [
        { N: 'A', P: '9876543210', S: '12000' },
        { N: '', P: '123', S: 'x' },
        { N: 'C', P: '9876543210', S: '500' },
      ],
      mapping,
      [],
      'IN',
      new Set(),
    );
    expect(rows[0].issues).toHaveLength(0);
    expect(rows[1].issues.map((i) => i.field).sort()).toEqual(['name', 'phone', 'ratePaise']);
    expect(rows[2].issues.map((i) => i.field)).toEqual(expect.arrayContaining(['phone', 'wageType']));
    expect(rows[2].values.wageType).toBe('daily');
  });
  it('attendance grid codes and day columns', () => {
    expect(parseAttendanceCode('P')).toEqual({ status: 'present' });
    expect(parseAttendanceCode('HD')).toEqual({ status: 'half_day' });
    expect(parseAttendanceCode('sl')).toEqual({ status: 'leave', leaveType: 'sick' });
    expect(parseAttendanceCode('??')).toBeUndefined();
    expect(dayColumns(['Name', '1', '02', '31', '32'], '2026-10')).toEqual({ '1': '2026-10-01', '02': '2026-10-02', '31': '2026-10-31' });
  });
});
