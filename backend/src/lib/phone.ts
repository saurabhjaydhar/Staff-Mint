/**
 * Normalise phone numbers to E.164. Country-aware: a bare 10-digit number is
 * treated as local to the default country. No India-only logic leaks elsewhere.
 */
const COUNTRY_CODES: Record<string, { code: string; nsnLength: number[] }> = {
  IN: { code: '91', nsnLength: [10] },
  AE: { code: '971', nsnLength: [9] },
  SA: { code: '966', nsnLength: [9] },
  SG: { code: '65', nsnLength: [8] },
  MY: { code: '60', nsnLength: [9, 10] },
};

export function normalizePhone(raw: unknown, country = 'IN'): string | null {
  if (raw === null || raw === undefined) return null;
  let s = String(raw).trim();
  if (!s) return null;
  // Excel sometimes gives numbers like 9.87654321E9
  if (/^\d+(\.\d+)?e\+?\d+$/i.test(s)) s = Number(s).toFixed(0);
  const hasPlus = s.startsWith('+');
  let digits = s.replace(/\D/g, '');
  if (s.startsWith('00')) digits = digits.slice(2);
  const cc = COUNTRY_CODES[country] ?? COUNTRY_CODES.IN;

  if (hasPlus || s.startsWith('00')) {
    return digits.length >= 8 && digits.length <= 15 ? `+${digits}` : null;
  }
  if (digits.startsWith('0') && cc.nsnLength.includes(digits.length - 1)) digits = digits.slice(1);
  if (cc.nsnLength.includes(digits.length)) {
    if (country === 'IN' && !/^[6-9]/.test(digits)) return null;
    return `+${cc.code}${digits}`;
  }
  if (digits.startsWith(cc.code) && cc.nsnLength.includes(digits.length - cc.code.length)) return `+${digits}`;
  return null;
}

export const maskPhone = (phone: string): string => phone.replace(/(\+\d{2,3})\d+(\d{3})$/, '$1xxxxx$2');
