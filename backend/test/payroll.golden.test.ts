import { describe, expect, it } from 'vitest';
import fs from 'node:fs';
import path from 'node:path';
import { computePayslip, ENGINE_VERSION } from '../src/modules/payroll/engine.js';

const dir = path.join(path.dirname(new URL(import.meta.url).pathname), 'golden/payroll');
const files = fs.readdirSync(dir).filter((f) => f.endsWith('.json'));

describe('payroll engine — golden files', () => {
  it('has golden cases', () => expect(files.length).toBeGreaterThanOrEqual(10));

  for (const f of files) {
    it(f.replace('.json', ''), () => {
      const { input, expected } = JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8'));
      const r = computePayslip(input);
      expect(r.engineVersion).toBe(ENGINE_VERSION);
      expect(r.payableDays).toBe(expected.payableDays);
      expect(r.grossPaise).toBe(expected.grossPaise);
      if (expected.deductionsPaise !== undefined) expect(r.deductionsPaise).toBe(expected.deductionsPaise);
      expect(r.netPaise).toBe(expected.netPaise);
      expect(r.netPaise).toBe(r.grossPaise - r.deductionsPaise);
      expect(r.anomalies.map((a) => a.code).sort()).toEqual([...expected.anomalies].sort());
      if (expected.summary) expect(r.summary).toEqual(expected.summary);
      if (expected.lines) expect(r.lines.map((l) => [l.code, l.amountPaise])).toEqual(expected.lines);
      if (expected.advanceDeductions) expect(r.advanceDeductions.map((a) => [a.advanceId, a.amountPaise])).toEqual(expected.advanceDeductions);
      for (const s of expected.explainIncludes ?? []) expect(r.lines[0].explanation.en).toContain(s);
      // Every line is explainable in both languages.
      for (const l of r.lines) {
        expect(l.explanation.en.length).toBeGreaterThan(5);
        expect(l.explanation.hi.length).toBeGreaterThan(5);
      }
    });
  }

  it('is deterministic (same input → identical output)', () => {
    const { input } = JSON.parse(fs.readFileSync(path.join(dir, files[0]), 'utf8'));
    expect(computePayslip(input)).toEqual(computePayslip(structuredClone(input)));
  });

  it('computes 30 staff in well under 5 seconds', () => {
    const { input } = JSON.parse(fs.readFileSync(path.join(dir, 'advances-bonus-deduction.json'), 'utf8'));
    const t0 = performance.now();
    for (let i = 0; i < 30 * 100; i++) computePayslip({ ...input, employee: { ...input.employee, employeeId: `e${i}` } });
    expect(performance.now() - t0).toBeLessThan(5000);
  });
});
