import { AppError } from '../../lib/errors.js';
import { decryptField, encryptField } from '../../lib/crypto.js';
import type { Ctx } from '../../lib/context.js';
import { Company } from '../../models/index.js';
import { audit } from '../audit/service.js';
import { assertEmployeeInScope } from '../employees/service.js';
import { maskPan } from '../../lib/mask.js';
import { DEFAULT_STATUTORY } from '../payroll/engine.js';

export interface StatutoryPatch {
  pfEnabled?: boolean;
  pfNumber?: string | null;
  basicPercent?: number;
  pfCapAtCeiling?: boolean;
  esiEnabled?: boolean;
  esiNumber?: string | null;
  ptEnabled?: boolean;
  ptState?: string | null;
  ptMonthlyPaise?: number;
  ptMinGrossPaise?: number;
}

/** The shop's PF / ESI / Professional Tax settings, with the rates in force. */
export function statutoryView(company: any) {
  const st = company?.settings?.statutory ?? {};
  return {
    pfEnabled: !!st.pfEnabled,
    pfNumber: st.pfNumber ?? null,
    basicPercent: st.basicPercent ?? DEFAULT_STATUTORY.basicPercent,
    pfRatePercent: st.pfRatePercent ?? DEFAULT_STATUTORY.pfRatePercent,
    pfWageCeilingPaise: st.pfWageCeilingPaise ?? DEFAULT_STATUTORY.pfWageCeilingPaise,
    pfCapAtCeiling: st.pfCapAtCeiling ?? true,
    esiEnabled: !!st.esiEnabled,
    esiNumber: st.esiNumber ?? null,
    esiEmployeePercent: st.esiEmployeePercent ?? DEFAULT_STATUTORY.esiEmployeePercent,
    esiEmployerPercent: st.esiEmployerPercent ?? DEFAULT_STATUTORY.esiEmployerPercent,
    esiWageLimitPaise: st.esiWageLimitPaise ?? DEFAULT_STATUTORY.esiWageLimitPaise,
    ptEnabled: !!st.ptEnabled,
    ptState: st.ptState ?? null,
    ptMonthlyPaise: st.ptMonthlyPaise ?? DEFAULT_STATUTORY.ptMonthlyPaise,
    ptMinGrossPaise: st.ptMinGrossPaise ?? 0,
  };
}

export async function getStatutory(ctx: Ctx) {
  return statutoryView(await Company.findById(ctx.companyId).lean());
}

/** Takes effect on the next salary calculated; approved months don't change. */
export async function updateStatutory(ctx: Ctx, patch: StatutoryPatch) {
  const c = await Company.findById(ctx.companyId);
  if (!c) throw new AppError('NOT_FOUND', 'Business not found');
  const before = statutoryView(c);
  const st: any = (c.settings as any).statutory ?? {};
  for (const [k, v] of Object.entries(patch)) {
    if (v === undefined) continue;
    st[k] = typeof v === 'string' ? (k === 'ptState' ? v.trim() : v.trim().toUpperCase()) || null : v;
  }
  (c.settings as any).statutory = st;
  c.markModified('settings');
  await c.save();
  const after = statutoryView(c);
  await audit(ctx, { action: 'company.statutory.update', entity: 'company', entityId: c._id, before, after });
  return after;
}

export interface EmployeeStatutoryPatch {
  employeeCode?: string | null;
  uan?: string | null;
  esicNumber?: string | null;
  pan?: string | null;
  pfExempt?: boolean;
  esiExempt?: boolean;
}

export function employeeStatutoryView(e: any) {
  let panMasked: string | null = null;
  if (e.panEnc) {
    try {
      panMasked = maskPan(decryptField(e.panEnc));
    } catch {
      panMasked = null;
    }
  }
  return {
    employeeCode: e.employeeCode ?? null,
    uan: e.uan ?? null,
    esicNumber: e.esicNumber ?? null,
    panMasked,
    pfExempt: !!e.pfExempt,
    esiExempt: !!e.esiExempt,
  };
}

const clean = (v: string | null | undefined) => (v === undefined ? undefined : v === null ? null : v.replace(/\s/g, '').toUpperCase() || null);

export async function updateEmployeeStatutory(ctx: Ctx, id: string, patch: EmployeeStatutoryPatch) {
  const e = await assertEmployeeInScope(ctx, id);
  const before = employeeStatutoryView(e);
  const uan = clean(patch.uan);
  const esic = clean(patch.esicNumber);
  const pan = clean(patch.pan);
  if (uan && !/^\d{12}$/.test(uan)) throw new AppError('VALIDATION_ERROR', 'UAN is 12 digits', { field: 'uan' });
  if (esic && !/^\d{10}(\d{7})?$/.test(esic)) throw new AppError('VALIDATION_ERROR', 'ESIC number is 10 or 17 digits', { field: 'esicNumber' });
  if (pan && !/^[A-Z]{5}\d{4}[A-Z]$/.test(pan)) throw new AppError('VALIDATION_ERROR', 'PAN looks wrong (like ABCDE1234F)', { field: 'pan' });
  if (patch.employeeCode !== undefined) e.employeeCode = patch.employeeCode?.trim() || null;
  if (uan !== undefined) e.uan = uan;
  if (esic !== undefined) e.esicNumber = esic;
  if (pan !== undefined) e.panEnc = pan ? encryptField(pan) : null;
  if (patch.pfExempt !== undefined) e.pfExempt = patch.pfExempt;
  if (patch.esiExempt !== undefined) e.esiExempt = patch.esiExempt;
  await e.save();
  const after = employeeStatutoryView(e);
  await audit(ctx, { action: 'employee.statutory.update', entity: 'employee', entityId: e._id, before, after });
  return after;
}
