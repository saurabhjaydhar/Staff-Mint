// Pure helpers for the import review screen (F2). Kept framework-free so they are unit tested.

import { formatPaise, paiseToRupeeInput, parseRupeesToPaise } from "./money";
import type { ImportField, ImportKind, ImportPatch, ImportRow, ImportSession } from "./types";

export const IMPORT_FIELDS: { field: ImportField; label: string; labelHi: string }[] = [
  { field: "name", label: "Name", labelHi: "नाम" },
  { field: "phone", label: "Phone", labelHi: "फ़ोन" },
  { field: "ratePaise", label: "Salary / rate (₹)", labelHi: "वेतन / रेट (₹)" },
  { field: "wageType", label: "Wage type (monthly/daily)", labelHi: "वेतन प्रकार (मासिक/दैनिक)" },
  { field: "designation", label: "Designation", labelHi: "पद" },
  { field: "joiningDate", label: "Joining date", labelHi: "जॉइनिंग तारीख" },
  { field: "branch", label: "Branch", labelHi: "ब्रांच" },
  { field: "advanceBalancePaise", label: "Advance balance (₹)", labelHi: "एडवांस बाकी (₹)" },
  { field: "paidLeaveBalance", label: "Paid leave balance", labelHi: "पेड छुट्टी बाकी" },
  { field: "sickLeaveBalance", label: "Sick leave balance", labelHi: "बीमारी छुट्टी बाकी" },
  { field: "lastSalaryPaise", label: "Last salary (₹)", labelHi: "पिछला वेतन (₹)" },
];

/** Field names that carry paise; the UI edits them in rupees. */
export function isPaiseField(field: string): boolean {
  return /Paise$/.test(field);
}

export function isNumericField(field: string): boolean {
  return field === "paidLeaveBalance" || field === "sickLeaveBalance";
}

/** Rows the review UI must show: only those with issues (PRD F2). */
export function flaggedRows(session: Pick<ImportSession, "rows">): ImportRow[] {
  return session.rows.filter((r) => r.issues && r.issues.length > 0);
}

/** Issues for a given row + field. */
export function issuesFor(row: ImportRow, field: string): string[] {
  return row.issues.filter((i) => i.field === field).map((i) => i.message);
}

/** Row-level issues whose field is not one of the displayed columns. */
export function otherIssues(row: ImportRow, columns: string[]): string[] {
  return row.issues.filter((i) => !columns.includes(i.field)).map((i) => `${i.field ? `${i.field}: ` : ""}${i.message}`);
}

/**
 * Columns to display in the flagged-row table: mapped fields (in header order, de-duplicated),
 * plus any field that has an issue but no mapped column (e.g. a required `phone` missing).
 */
export function displayColumns(session: Pick<ImportSession, "headers" | "mapping" | "rows">): string[] {
  const cols: string[] = [];
  for (const h of session.headers) {
    const f = session.mapping[h];
    if (f && !cols.includes(f)) cols.push(f);
  }
  for (const r of flaggedRows(session)) {
    for (const i of r.issues) {
      if (i.field && !cols.includes(i.field)) cols.push(i.field);
    }
  }
  return cols;
}

/** Fields offered in the mapping dropdown: known fields + any unknown value the backend already uses. */
export function mappingOptions(session: Pick<ImportSession, "mapping">): string[] {
  const opts: string[] = IMPORT_FIELDS.map((f) => f.field);
  for (const v of Object.values(session.mapping)) {
    if (v && !opts.includes(v)) opts.push(v);
  }
  return opts;
}

export function fieldLabel(field: string, lang: "en" | "hi" = "en"): string {
  const f = IMPORT_FIELDS.find((x) => x.field === field);
  if (f) return lang === "hi" ? f.labelHi : f.label;
  return field;
}

/** Fields mapped to more than one header (likely a mistake worth highlighting). */
export function duplicateMappings(mapping: Record<string, string | null>): string[] {
  const seen = new Map<string, number>();
  for (const v of Object.values(mapping)) if (v) seen.set(v, (seen.get(v) || 0) + 1);
  return [...seen.entries()].filter(([, n]) => n > 1).map(([f]) => f);
}

/** Build the PATCH body for a single mapping change (null = ignore column). */
export function mappingPatch(header: string, field: string | null): ImportPatch {
  return { mapping: { [header]: field || null } };
}

/** Value shown in an editable cell (paise fields are shown in rupees). */
export function cellInputValue(field: string, value: unknown): string {
  if (value === null || value === undefined) return "";
  if (isPaiseField(field) && typeof value === "number") return paiseToRupeeInput(value);
  return String(value);
}

/** Read-only display for a cell. */
export function cellDisplayValue(field: string, value: unknown): string {
  if (value === null || value === undefined || value === "") return "—";
  if (isPaiseField(field) && typeof value === "number") return formatPaise(value);
  return String(value);
}

/**
 * Convert what the owner typed into the value sent in `fixes`.
 * Money fields are edited in rupees and sent as the typed rupee text ("12k", "₹12,000/-", "15000"):
 * the server's import cleaner parses rupee formats for every money field (PRD F2), whereas a bare
 * number would be ambiguous (paise vs rupees). Leave balances become numbers; wage type is canonicalised.
 */
export function normalizeFixValue(field: string, input: string): unknown {
  const raw = input.trim();
  if (raw === "") return null;
  if (isPaiseField(field)) return raw;
  if (isNumericField(field)) {
    const n = Number(raw);
    return Number.isFinite(n) ? n : raw;
  }
  if (field === "wageType") {
    const v = raw.toLowerCase();
    if (/^(m|monthly|month|mahina|masik|मासिक)$/.test(v)) return "monthly";
    if (/^(d|daily|day|din|dainik|दैनिक|dihadi)$/.test(v)) return "daily";
    return raw;
  }
  return raw;
}

/** Draft edits keyed by `${row}:${field}` -> typed text. */
export type FixDrafts = Record<string, string>;

export function draftKey(row: number, field: string): string {
  return `${row}:${field}`;
}

/** Turn draft edits into the `fixes` array, dropping edits that equal the current value. */
export function buildFixes(session: Pick<ImportSession, "rows">, drafts: FixDrafts): NonNullable<ImportPatch["fixes"]> {
  const fixes: NonNullable<ImportPatch["fixes"]> = [];
  for (const [key, text] of Object.entries(drafts)) {
    const sep = key.indexOf(":");
    const row = Number(key.slice(0, sep));
    const field = key.slice(sep + 1);
    const existing = session.rows.find((r) => r.index === row);
    if (existing && cellInputValue(field, existing.values[field]) === text) continue;
    fixes.push({ row, field, value: normalizeFixValue(field, text) });
  }
  return fixes.sort((a, b) => a.row - b.row || a.field.localeCompare(b.field));
}

/** Toggle a row in the skip list (returns a new sorted array). */
export function toggleSkip(skipRows: number[], row: number): number[] {
  const set = new Set(skipRows);
  if (set.has(row)) set.delete(row);
  else set.add(row);
  return [...set].sort((a, b) => a - b);
}

/** Initial skip list from a session (if the backend echoes it). */
export function initialSkips(session: Pick<ImportSession, "rows" | "skipRows">): number[] {
  if (Array.isArray(session.skipRows)) return [...session.skipRows].sort((a, b) => a - b);
  return session.rows.filter((r) => r.skipped).map((r) => r.index);
}

/** Flagged rows that are neither fixed nor skipped block a clean commit (warning only). */
export function unresolvedCount(session: Pick<ImportSession, "rows">, skipRows: number[]): number {
  return flaggedRows(session).filter((r) => !skipRows.includes(r.index)).length;
}

/** Seconds remaining until an ISO instant (never negative). */
export function secondsLeft(untilIso: string | undefined | null, now: number): number {
  if (!untilIso) return 0;
  const t = Date.parse(untilIso);
  if (Number.isNaN(t)) return 0;
  return Math.max(0, Math.ceil((t - now) / 1000));
}

function csvCell(v: string): string {
  return /[",\n]/.test(v) ? `"${v.replace(/"/g, '""')}"` : v;
}

export function toCsv(rows: string[][]): string {
  return rows.map((r) => r.map(csvCell).join(",")).join("\r\n") + "\r\n";
}

/** Days (1..n) of a YYYY-MM month. */
export function daysInMonth(month: string): number {
  const [y, m] = month.split("-").map(Number);
  return new Date(Date.UTC(y, m, 0)).getUTCDate();
}

/** Client-generated sample template (download from the import page). */
export function sampleTemplateCsv(kind: ImportKind, month?: string): string {
  if (kind === "attendance") {
    const m = month && /^\d{4}-\d{2}$/.test(month) ? month : "2026-09";
    const n = daysInMonth(m);
    const header = ["Name", "Phone", ...Array.from({ length: n }, (_, i) => String(i + 1))];
    const pattern = ["P", "P", "A", "P", "HD", "P", "WO", "P", "L", "P", "P", "H", "P", "WO"];
    const row = (name: string, phone: string, shift: number) => [
      name,
      phone,
      ...Array.from({ length: n }, (_, i) => pattern[(i + shift) % pattern.length]),
    ];
    return toCsv([header, row("Ramesh Kumar", "9876543210", 0), row("Sunita Devi", "9876501234", 3)]);
  }
  return toCsv([
    [
      "Name",
      "Phone",
      "Salary",
      "Wage Type",
      "Designation",
      "Joining Date",
      "Branch",
      "Advance Balance",
      "Paid Leave Balance",
      "Sick Leave Balance",
      "Last Salary",
    ],
    ["Ramesh Kumar", "9876543210", "15000", "monthly", "Salesman", "01/04/2024", "Main", "2000", "4", "2", "15000"],
    ["Sunita Devi", "9876501234", "600", "daily", "Helper", "15/07/2025", "Main", "0", "0", "0", "14400"],
    ["Mohd. Arif", "+919812345678", "12k", "monthly", "Cashier", "10/01/2023", "Main", "", "6", "3", "12000"],
  ]);
}

/**
 * Local deadline (ms epoch) for the Undo button. Uses the server's `undoUntil`, but guards against
 * client/server clock skew: if it is already past or implausibly far away, fall back to
 * `committedAt + windowSec` (the PRD's 30-second undo window).
 */
export function undoDeadline(undoUntil: string | undefined | null, committedAt: number, windowSec = 30): number {
  const fallback = committedAt + windowSec * 1000;
  if (!undoUntil) return fallback;
  const t = Date.parse(undoUntil);
  if (Number.isNaN(t) || t <= committedAt || t - committedAt > windowSec * 2 * 1000) return fallback;
  return t;
}

/** Client-side check for a money cell before sending (null = looks fine). */
export function moneyInputError(field: string, input: string): string | null {
  if (!isPaiseField(field) || input.trim() === "") return null;
  return parseRupeesToPaise(input) === null ? "Use an amount like 15000, 15k or ₹15,000" : null;
}
