import ExcelJS from 'exceljs';
import { DateTime } from 'luxon';

export interface Table {
  headers: string[];
  rows: Record<string, unknown>[];
}

function cellValue(v: any): unknown {
  if (v === null || v === undefined) return '';
  if (v instanceof Date) return v;
  if (typeof v === 'object') {
    if ('result' in v) return cellValue(v.result);
    if ('text' in v) return v.text;
    if ('richText' in v) return v.richText.map((r: any) => r.text).join('');
    if ('hyperlink' in v) return v.text ?? v.hyperlink;
  }
  return v;
}

/** Split CSV/TSV respecting quotes. */
export function parseDelimited(text: string): string[][] {
  const firstLines = text.split(/\r?\n/).slice(0, 5).join('\n');
  const delims = [',', '\t', ';', '|'];
  const delim = delims.map((d) => [d, firstLines.split(d).length] as const).sort((a, b) => b[1] - a[1])[0][0];
  const out: string[][] = [];
  let row: string[] = [];
  let cur = '';
  let q = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (q) {
      if (c === '"' && text[i + 1] === '"') {
        cur += '"';
        i++;
      } else if (c === '"') q = false;
      else cur += c;
    } else if (c === '"') q = true;
    else if (c === delim) {
      row.push(cur);
      cur = '';
    }
    else if (c === '\n' || c === '\r') {
      if (c === '\r' && text[i + 1] === '\n') i++;
      row.push(cur);
      out.push(row);
      row = [];
      cur = '';
    } else cur += c;
  }
  if (cur || row.length) {
    row.push(cur);
    out.push(row);
  }
  return out.filter((r) => r.some((c) => c.trim()));
}

function toTable(matrix: unknown[][]): Table {
  // Header row = first row with ≥2 non-empty text-ish cells.
  const hIdx = Math.max(
    0,
    matrix.findIndex((r) => r.filter((c) => typeof c === 'string' && c.trim() && !/^\+?\d[\d\s-]{6,}$/.test(c.trim())).length >= 2),
  );
  const raw = (matrix[hIdx] ?? []).map((h, i) => String(h ?? '').trim() || `Column ${i + 1}`);
  const seen = new Map<string, number>();
  const headers = raw.map((h) => {
    const n = (seen.get(h) ?? 0) + 1;
    seen.set(h, n);
    return n > 1 ? `${h} (${n})` : h;
  });
  const rows = matrix
    .slice(hIdx + 1)
    .filter((r) => r.some((c) => String(c ?? '').trim()))
    .map((r) => Object.fromEntries(headers.map((h, i) => [h, typeof r[i] === 'string' ? (r[i] as string).trim() : (r[i] ?? '')])));
  return { headers, rows };
}

export async function readTable(buffer: Buffer, filename: string): Promise<Table> {
  const lower = filename.toLowerCase();
  if (lower.endsWith('.xlsx') || lower.endsWith('.xlsm') || buffer.subarray(0, 2).toString() === 'PK') {
    const wb = new ExcelJS.Workbook();
    await wb.xlsx.load(buffer as any);
    const ws = wb.worksheets.find((w) => w.actualRowCount > 0) ?? wb.worksheets[0];
    if (!ws) return { headers: [], rows: [] };
    const matrix: unknown[][] = [];
    ws.eachRow({ includeEmpty: false }, (row) => {
      const vals = (row.values as any[]).slice(1).map(cellValue);
      matrix.push(vals);
    });
    return toTable(matrix);
  }
  if (lower.endsWith('.xls')) throw Object.assign(new Error('Old .xls files are not supported. Save as .xlsx or CSV and upload again.'), { code: 'VALIDATION_ERROR' });
  return toTable(parseDelimited(buffer.toString('utf8').replace(/^\uFEFF/, '')));
}

/**
 * Pasted WhatsApp text. Either a delimited table with a header, or free lines like:
 *   "Ramesh 9876543210 12000"  /  "1. Pooja - 98765 43210 - 12k - helper"
 */
/** Mobile numbers: optional country code, 10 digits possibly split 5+5 by a space/dash. */
export const PHONE_RE = /(?:\+?\d{1,3}[\s-]?)?\d{5}[\s-]?\d{5}(?!\d)/;

export function readPastedText(text: string): Table {
  const lines = text.split(/\r?\n/).map((l) => l.trim()).filter(Boolean);
  if (lines.length >= 2 && /[,\t|;]/.test(lines[0]) && /[a-z]/i.test(lines[0]) && !/\d{7,}/.test(lines[0])) {
    return toTable(parseDelimited(lines.join('\n')));
  }
  const rows = lines.map((line) => {
    let l = line.replace(/^\s*\d+[.)]\s*/, '');
    const phoneMatch = l.match(PHONE_RE);
    const phone = phoneMatch ? phoneMatch[0] : "";
    if (phoneMatch) l = l.replace(phoneMatch[0], " ");
    const amtMatch = l.match(/(₹|rs\.?\s*)?(\d+(?:[.,]\d+)*\s*(k|hazaar|hazar|thousand|lakh)?)(\s*\/-)?/i);
    const salary = amtMatch ? amtMatch[0] : '';
    if (amtMatch) l = l.replace(amtMatch[0], ' ');
    const parts = l.split(/\s*[-–,|:]\s*|\s{2,}/).map((p) => p.trim()).filter(Boolean);
    const name = (parts[0] ?? '').replace(/\s+/g, ' ');
    const designation = parts.slice(1).join(' ');
    return { Name: name, Phone: phone, Salary: salary.trim(), Designation: designation };
  });
  return { headers: ['Name', 'Phone', 'Salary', 'Designation'], rows };
}

/** Dates: Date objects, Excel serials, DD/MM/YYYY (default), YYYY-MM-DD, "12 Jan 2024". */
export function parseDateLoose(v: unknown): string | null {
  if (v === null || v === undefined || v === '') return null;
  if (v instanceof Date && !Number.isNaN(v.getTime())) return DateTime.fromJSDate(v, { zone: 'utc' }).toISODate();
  if (typeof v === 'number' && v > 20000 && v < 80000) return DateTime.fromObject({ year: 1899, month: 12, day: 30 }, { zone: 'utc' }).plus({ days: Math.floor(v) }).toISODate();
  const s = String(v).trim();
  const fmts = ['dd/MM/yyyy', 'd/M/yyyy', 'dd-MM-yyyy', 'd-M-yyyy', 'dd.MM.yyyy', 'dd/MM/yy', 'd/M/yy', 'dd-MM-yy', 'd-M-yy', 'd.M.yyyy', 'd.M.yy', 'yyyy-MM-dd', 'yyyy/MM/dd', 'd MMM yyyy', 'dd MMM yyyy', 'd MMMM yyyy', 'MMM d, yyyy', 'dd-MMM-yyyy', 'd-MMM-yy', 'dd-MMM-yy'];
  for (const f of fmts) {
    const d = DateTime.fromFormat(s, f, { locale: 'en' });
    if (d.isValid) return d.toISODate();
  }
  return null;
}
