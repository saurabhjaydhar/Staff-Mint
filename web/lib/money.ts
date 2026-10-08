// Money helpers. The API always sends integer paise (₹1 = 100 paise).

/** Group an integer string the Indian way: 1234567 -> 12,34,567 */
export function groupIndian(digits: string): string {
  if (digits.length <= 3) return digits;
  const last3 = digits.slice(-3);
  let rest = digits.slice(0, -3);
  const parts: string[] = [];
  while (rest.length > 2) {
    parts.unshift(rest.slice(-2));
    rest = rest.slice(0, -2);
  }
  if (rest) parts.unshift(rest);
  return `${parts.join(",")},${last3}`;
}

export interface FormatOptions {
  /** "auto" (default) shows .xx only when paise are non-zero; "always" always shows 2 decimals; "never" rounds to rupees. */
  decimals?: "auto" | "always" | "never";
  /** Prefix with ₹ (default true). */
  symbol?: boolean;
}

/** Format integer paise as ₹ with Indian digit grouping, e.g. 123456789 -> "₹12,34,567.89". */
export function formatPaise(paise: number | null | undefined, opts: FormatOptions = {}): string {
  if (paise === null || paise === undefined || !Number.isFinite(paise)) return "—";
  const { decimals = "auto", symbol = true } = opts;
  let value = Math.round(paise);
  const negative = value < 0;
  value = Math.abs(value);
  let rupees = Math.floor(value / 100);
  let rem = value % 100;
  if (decimals === "never") {
    if (rem >= 50) rupees += 1;
    rem = 0;
  }
  let out = groupIndian(String(rupees));
  if (decimals === "always" || (decimals === "auto" && rem !== 0)) {
    out += `.${String(rem).padStart(2, "0")}`;
  }
  return `${negative ? "-" : ""}${symbol ? "₹" : ""}${out}`;
}

/** Paise -> plain rupee string for editable inputs (no symbol, no grouping): 1250050 -> "12500.5" */
export function paiseToRupeeInput(paise: number | null | undefined): string {
  if (paise === null || paise === undefined || !Number.isFinite(paise)) return "";
  const rupees = Math.round(paise) / 100;
  return String(rupees);
}

/**
 * Parse a human rupee amount into integer paise.
 * Accepts: "12000", "12,000", "₹12,000/-", "Rs. 12000.50", "12k", "12.5K", "1.2 lakh", "1.5L", "1 cr".
 * Returns null when the input is empty or not a valid non-negative amount.
 */
export function parseRupeesToPaise(input: string | number | null | undefined): number | null {
  if (input === null || input === undefined) return null;
  if (typeof input === "number") {
    return Number.isFinite(input) && input >= 0 ? Math.round(input * 100) : null;
  }
  let s = input.trim().toLowerCase();
  if (!s) return null;
  s = s
    .replace(/₹|inr|rs\.?|rupees?|\/-|\s+/g, "")
    .replace(/,/g, "")
    .replace(/(per|\/)(month|mo|day|din|mahina)$/, "");
  const m = /^(\d+(?:\.\d+)?|\.\d+)(k|thousand|l|lakh|lakhs|lac|lacs|cr|crore|crores)?$/.exec(s);
  if (!m) return null;
  const n = Number(m[1]);
  if (!Number.isFinite(n)) return null;
  const suffix = m[2];
  let mult = 1;
  if (suffix === "k" || suffix === "thousand") mult = 1_000;
  else if (suffix && /^(l|lakh|lakhs|lac|lacs)$/.test(suffix)) mult = 1_00_000;
  else if (suffix && /^(cr|crore|crores)$/.test(suffix)) mult = 1_00_00_000;
  return Math.round(n * mult * 100);
}
