/** All money is integer paise. ₹1 = 100 paise. */

export const toPaise = (rupees: number): number => Math.round(rupees * 100);
export const toRupees = (paise: number): number => paise / 100;

/** Round half away from zero to the nearest whole rupee (in paise). */
export const roundToRupee = (paise: number): number => Math.sign(paise) * Math.round(Math.abs(paise) / 100) * 100;

export function formatINR(paise: number, opts: { decimals?: boolean } = {}): string {
  const rupees = paise / 100;
  const decimals = opts.decimals ?? paise % 100 !== 0;
  return '₹' + rupees.toLocaleString('en-IN', { minimumFractionDigits: decimals ? 2 : 0, maximumFractionDigits: decimals ? 2 : 0 });
}

export function formatMoney(paise: number, currency = 'INR'): string {
  if (currency === 'INR') return formatINR(paise);
  return new Intl.NumberFormat('en', { style: 'currency', currency }).format(paise / 100);
}

/**
 * Parse loose human salary formats into paise.
 * Handles: "12000", "12,000", "₹12,000/-", "12k", "12.5K", "1.2 lakh", "Rs. 9500", "15 hazaar".
 * Returns null if not parseable.
 */
export function parseAmountToPaise(input: unknown): number | null {
  if (input === null || input === undefined) return null;
  if (typeof input === 'number') return Number.isFinite(input) && input >= 0 ? Math.round(input * 100) : null;
  let s = String(input).trim().toLowerCase();
  if (!s) return null;
  s = s
    .replace(/₹|rs\.?|inr|rupees?|\/-|\/month|\/mo|per month|pm|p\.m\.|monthly/g, '')
    .replace(/,/g, '')
    .replace(/\s+/g, ' ')
    .trim();
  const m = s.match(/^(\d+(?:\.\d+)?)\s*(k|thousand|hazaar|hazar|hajar|l|lac|lakh|lakhs)?$/);
  if (!m) return null;
  let n = parseFloat(m[1]);
  const unit = m[2];
  if (unit && ['k', 'thousand', 'hazaar', 'hazar', 'hajar'].includes(unit)) n *= 1000;
  if (unit && ['l', 'lac', 'lakh', 'lakhs'].includes(unit)) n *= 100000;
  if (!Number.isFinite(n) || n < 0) return null;
  return Math.round(n * 100);
}
