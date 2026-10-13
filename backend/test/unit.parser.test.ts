import { describe, expect, it } from 'vitest';
import { parseCommand } from '../src/modules/assistant/rulesParser.js';
import { matchEmployees } from '../src/modules/assistant/service.js';

const ctx = { today: '2026-10-08', employeeNames: ['Ramesh Kumar', 'Suresh Yadav', 'Amit Verma', 'Raju', 'Pooja Singh', 'Vikas'], shiftNames: ['Morning', 'Evening', 'Day'], role: 'owner' };

/** Owner phrase test set (seed for the PRD's 200-phrase pilot set). */
const OWNER: [string, string, Record<string, unknown>?][] = [
  ['Ramesh ko aaj half day laga do', 'mark_attendance', { employeeName: 'Ramesh', status: 'half_day', date: '2026-10-08' }],
  ['Suresh aaj nahi aaya', 'mark_attendance', { employeeName: 'Suresh', status: 'absent', date: '2026-10-08' }],
  ['suresh kal absent tha', 'mark_attendance', { status: 'absent', date: '2026-10-07' }],
  ['Pooja ko kal ki chutti laga do', 'mark_attendance', { employeeName: 'Pooja', status: 'leave', date: '2026-10-07' }],
  ['Amit present tha 5 oct ko', 'mark_attendance', { status: 'present', date: '2026-10-05' }],
  ['Vikas aadha din', 'mark_attendance', { status: 'half_day' }],
  ['mark ramesh absent today', 'mark_attendance', { status: 'absent' }],
  ['Raju bimar tha kal chutti', 'mark_attendance', { status: 'leave', leaveType: 'sick' }],
  ['Kaun late aaya?', 'who_is', { query: 'late', date: '2026-10-08' }],
  ['Kal kaun absent tha?', 'who_is', { query: 'absent', date: '2026-10-07' }],
  ['aaj kaun kaun aaya', 'who_is', { query: 'present' }],
  ['who is on leave today', 'who_is', { query: 'on_leave' }],
  ['kitne log nahi aaye', 'who_is', { query: 'absent' }],
  ['Amit ko 5000 advance diya', 'record_advance', { employeeName: 'Amit', amount: 5000 }],
  ['ramesh ko 10k udhaar diya 4 kisht mein', 'record_advance', { amount: 10000, installments: 4 }],
  ['Pooja advance 2500', 'record_advance', { amount: 2500 }],
  ['Raju ko 500 bonus', 'add_adjustment', { employeeName: 'Raju', type: 'bonus', amount: 500 }],
  ['Suresh ka 200 fine kaato', 'add_adjustment', { type: 'deduction', amount: 200 }],
  ['vikas ko 1000 incentive do', 'add_adjustment', { type: 'bonus', amount: 1000 }],
  ['Naya banda Pooja 9876543210 12000', 'add_employee', { name: 'Pooja', phone: '9876543210', salary: 12000 }],
  ['naya staff Mohan Lal 98765 43211 15k', 'add_employee', { name: 'Mohan Lal', salary: 15000 }],
  ['add staff Geeta 9876543212 600 per day', 'add_employee', { wageType: 'daily', salary: 600 }],
  ['Kal sabki chutti hai', 'declare_holiday', { date: '2026-10-09' }],
  ['aaj dukan band hai diwali', 'declare_holiday', { date: '2026-10-08', name: 'Diwali' }],
  ['Is month salary kitni banegi?', 'salary_preview', { month: '2026-10' }],
  ['pichle mahine ki salary total kitna hua', 'salary_preview', { month: '2026-09' }],
  ['Ramesh ki salary kitni banegi', 'salary_preview', { employeeName: 'Ramesh' }],
  ['October ka salary report bhejo', 'report', { kind: 'salary', month: '2026-10' }],
  ['september attendance report excel mein', 'report', { kind: 'attendance', month: '2026-09', format: 'xlsx' }],
  ['advance report', 'report', { kind: 'advances' }],
  ['Sab ki payslip bhej do', 'send_payslips'],
  ['salary slip send karo', 'send_payslips'],
  ['Ramesh ki chutti approve kar do', 'decide_leave', { decision: 'approved' }],
  ['pooja ki leave reject karo', 'decide_leave', { decision: 'rejected' }],
  // Roster (8 Oct 2026 is a Thursday)
  ['Raju ko is hafte evening shift do', 'set_shift', { employeeName: 'Raju', shift: 'Evening', from: '2026-10-08', to: '2026-10-11' }],
  ['Pooja ko agle hafte subah ki shift', 'set_shift', { employeeName: 'Pooja', shift: 'Morning', from: '2026-10-12', to: '2026-10-18' }],
  ['Amit ko Sunday off do', 'set_shift', { employeeName: 'Amit', shift: 'off', from: '2026-10-11', to: '2026-10-11' }],
  ['Raju kal morning shift', 'set_shift', { shift: 'Morning', from: '2026-10-09' }],
  ['Sunday ko kaun aa raha hai?', 'who_works', { date: '2026-10-11' }],
  ['kal kaun kaam par hai', 'who_works', { date: '2026-10-09' }],
  ['who is working on saturday', 'who_works', { date: '2026-10-10' }],
  ['Kya kya kar sakte ho?', 'help'],
  ['help', 'help'],
];

const EMPLOYEE: [string, string, Record<string, unknown>?][] = [
  ['Meri salary kitni bani?', 'my_salary'],
  ['meri salary kam kyun?', 'why_salary_low'],
  ['Why is my salary less this month', 'why_salary_low'],
  ['kal chutti chahiye', 'apply_leave', { from: '2026-10-09', type: 'paid' }],
  ['bimar hoon aaj leave chahiye', 'apply_leave', { from: '2026-10-08', type: 'sick' }],
  ['15 oct se 3 din ki chutti', 'apply_leave', { from: '2026-10-15', to: '2026-10-17' }],
];

describe('Mint Hinglish rule parser', () => {
  it.each(OWNER)('owner: %s → %s', (text, intent, args) => {
    const r = parseCommand(text, ctx);
    expect(r.intent).toBe(intent);
    expect(r.confidence).toBeGreaterThanOrEqual(0.6);
    if (args) expect(r.args).toMatchObject(args);
  });
  it.each(EMPLOYEE)('employee: %s → %s', (text, intent, args) => {
    const r = parseCommand(text, { ...ctx, role: 'employee' });
    expect(r.intent).toBe(intent);
    if (args) expect(r.args).toMatchObject(args);
  });
  it('returns no intent for chit-chat', () => {
    expect(parseCommand('aaj mausam kaisa hai', ctx).intent).toBeNull();
    expect(parseCommand('', ctx).intent).toBeNull();
  });
  it('accuracy over the phrase set is ≥ 90% (PRD F5 target)', () => {
    const ok = OWNER.filter(([t, i]) => parseCommand(t, ctx).intent === i).length + EMPLOYEE.filter(([t, i]) => parseCommand(t, { ...ctx, role: 'employee' }).intent === i).length;
    expect(ok / (OWNER.length + EMPLOYEE.length)).toBeGreaterThanOrEqual(0.9);
  });
});

describe('employee name matching', () => {
  const emps = [{ name: 'Ramesh Kumar' }, { name: 'Ramesh Gupta' }, { name: 'Suresh Yadav' }, { name: 'Raju' }];
  it('ambiguous first name returns both', () => expect(matchEmployees('Ramesh', emps)).toHaveLength(2));
  it('full name is exact', () => expect(matchEmployees('ramesh gupta', emps)).toEqual([{ name: 'Ramesh Gupta' }]));
  it('handles spelling variants', () => expect(matchEmployees('Sures', emps)).toEqual([{ name: 'Suresh Yadav' }]));
  it('no match for unknown', () => expect(matchEmployees('Mohan', emps)).toEqual([]));
});
