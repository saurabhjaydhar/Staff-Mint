import { describe, expect, it } from 'vitest';
import { computePayslip, DEFAULT_STATUTORY, type EngineInput, type StatutorySettings } from '../src/modules/payroll/engine.js';

/** September 2026 (30 days), everyone present every day, monthly salary. */
function input(ratePaise: number, statutory: Partial<StatutorySettings> | null, extra: Partial<EngineInput['employee']> = {}): EngineInput {
  return {
    month: '2026-09',
    currency: 'INR',
    settings: {
      monthDivisor: 'days_in_month',
      weekOffsPaid: true,
      holidaysPaid: true,
      sickLeavePaid: true,
      dailyPaysOffDays: false,
      roundToRupee: true,
      statutory: statutory ? { ...DEFAULT_STATUTORY, ...statutory } : null,
    },
    employee: {
      employeeId: 'e1',
      name: 'Pooja',
      wageType: 'monthly',
      ratePaise,
      days: Array.from({ length: 30 }, (_, i) => ({ date: `2026-09-${String(i + 1).padStart(2, '0')}`, status: 'present' as const })),
      adjustments: [],
      advances: [],
      ...extra,
    },
  };
}
const lines = (r: ReturnType<typeof computePayslip>) => r.lines.map((l) => [l.code, l.amountPaise]);

describe('statutory deductions (PF, ESI, Professional Tax)', () => {
  it('off: the simple shop slip is unchanged', () => {
    const r = computePayslip(input(2000000, null));
    expect(lines(r)).toEqual([['basic', 2000000]]);
    expect(r.netPaise).toBe(2000000);
    expect(r.employerContributions).toEqual([]);
  });

  it('₹20,000 with PF, ESI and PT: Basic/HRA split, 12% PF, 0.75% ESI, PT, employer share shown', () => {
    const r = computePayslip(input(2000000, { pfEnabled: true, esiEnabled: true, ptEnabled: true, ptMonthlyPaise: 20000 }));
    // Basic 50% = 10,000; HRA 10,000; PF 12% × 10,000 = 1,200; ESI 0.75% × 20,000 = 150; PT 200.
    expect(lines(r)).toEqual([
      ['basic', 1000000],
      ['allowance', 1000000],
      ['pf', 120000],
      ['esi', 15000],
      ['pt', 20000],
    ]);
    expect(r.grossPaise).toBe(2000000);
    expect(r.deductionsPaise).toBe(155000);
    expect(r.netPaise).toBe(1845000);
    expect(r.employerContributions.map((c) => [c.code, c.amountPaise])).toEqual([
      ['pf', 120000],
      ['esi', 65000], // 3.25% × 20,000
    ]);
    expect(r.lines[2].explanation.hi.length).toBeGreaterThan(5);
  });

  it('₹40,000: PF capped at the ₹15,000 ceiling, no ESI above ₹21,000', () => {
    const r = computePayslip(input(4000000, { pfEnabled: true, esiEnabled: true, ptEnabled: true }));
    // Basic 20,000 → PF on 15,000 = 1,800. ESI wages 40,000 > 21,000 → none.
    expect(lines(r)).toEqual([
      ['basic', 2000000],
      ['allowance', 2000000],
      ['pf', 180000],
      ['pt', 20000],
    ]);
    expect(r.lines.find((l) => l.code === 'pf')!.explanation.en).toContain('capped');
    expect(r.netPaise).toBe(3800000);
  });

  it('PF on full Basic when the owner turns the ceiling off', () => {
    const r = computePayslip(input(4000000, { pfEnabled: true, pfCapAtCeiling: false }));
    expect(r.lines.find((l) => l.code === 'pf')!.amountPaise).toBe(240000); // 12% × 20,000
  });

  it('ESI rounds up to the next rupee', () => {
    const r = computePayslip(input(1234500, { esiEnabled: true }));
    // No PF → no split. 0.75% × 12,345 = 92.59 → ₹93; employer 3.25% = 401.21 → ₹402.
    expect(lines(r)).toEqual([
      ['basic', 1234500],
      ['esi', 9300],
    ]);
    expect(r.employerContributions.map((c) => c.amountPaise)).toEqual([40200]);
  });

  it('exempt staff and the PT threshold', () => {
    const exempt = computePayslip(input(2000000, { pfEnabled: true, esiEnabled: true }, { pfExempt: true, esiExempt: true }));
    expect(lines(exempt)).toEqual([['basic', 2000000]]);
    const belowPt = computePayslip(input(900000, { ptEnabled: true, ptMonthlyPaise: 20000, ptMinGrossPaise: 1000000 }));
    expect(lines(belowPt)).toEqual([['basic', 900000]]);
  });

  it('statutory comes before advances, and salary never goes below zero', () => {
    const r = computePayslip(
      input(2000000, { pfEnabled: true, ptEnabled: true }, {
        advances: [{ id: 'a1', date: '2026-09-02', amountPaise: 5000000, mode: 'full_next', installments: 1, outstandingPaise: 5000000, skip: false }],
      }),
    );
    expect(r.lines.map((l) => l.code)).toEqual(['basic', 'allowance', 'pf', 'pt', 'advance']);
    expect(r.netPaise).toBe(0);
    expect(r.anomalies.map((a) => a.code)).toContain('advance_capped');
  });
});
