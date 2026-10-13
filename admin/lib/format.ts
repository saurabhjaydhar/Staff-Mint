// Formatting for admin screens (India first: ₹, lakh/crore, IST dates).

import type { BusinessStatus } from "./types";

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

/** ₹1,23,456 — whole rupees from paise. */
export function rupees(paise: number): string {
  return `₹${Math.round(paise / 100).toLocaleString("en-IN")}`;
}

/** Short money for tiles: ₹950, ₹12.4K, ₹3.2L, ₹1.1Cr. */
export function rupeesShort(paise: number): string {
  const r = paise / 100;
  const trim = (n: number) => (n >= 100 ? Math.round(n).toString() : n.toFixed(1).replace(/\.0$/, ""));
  if (r >= 1e7) return `₹${trim(r / 1e7)}Cr`;
  if (r >= 1e5) return `₹${trim(r / 1e5)}L`;
  if (r >= 1e3) return `₹${trim(r / 1e3)}K`;
  return `₹${Math.round(r)}`;
}

/** 1,284 · 12.9K · 3.4L */
export function count(n: number): string {
  if (n >= 1e5) return `${(n / 1e5).toFixed(1).replace(/\.0$/, "")}L`;
  if (n >= 1e4) return `${(n / 1e3).toFixed(1).replace(/\.0$/, "")}K`;
  return n.toLocaleString("en-IN");
}

export function date(iso: string | null | undefined): string {
  if (!iso) return "—";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  return `${d.getDate()} ${MONTHS[d.getMonth()]} ${d.getFullYear()}`;
}

/** "12 Oct" from "2026-10-12". */
export function dayMonth(ymd: string): string {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(ymd);
  return m ? `${Number(m[3])} ${MONTHS[Number(m[2]) - 1]}` : ymd;
}

export function dateTime(iso: string | null | undefined): string {
  if (!iso) return "—";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  return `${d.getDate()} ${MONTHS[d.getMonth()]}, ${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
}

/** "just now", "5 min ago", "3 h ago", "2 days ago", then the date. */
export function ago(iso: string | null | undefined, now = Date.now()): string {
  if (!iso) return "—";
  const s = Math.max(0, Math.round((now - new Date(iso).getTime()) / 1000));
  if (s < 60) return "just now";
  if (s < 3600) return `${Math.floor(s / 60)} min ago`;
  if (s < 86400) return `${Math.floor(s / 3600)} h ago`;
  if (s < 7 * 86400) return `${Math.floor(s / 86400)} day${s < 2 * 86400 ? "" : "s"} ago`;
  return date(iso);
}

/** Whole days until a date (part of a day counts as one); 0 when past. */
export function daysUntil(iso: string, now = Date.now()): number {
  const ms = new Date(iso).getTime() - now;
  return ms <= 0 ? 0 : Math.ceil(ms / 86_400_000);
}

export const STATUS_LABEL: Record<BusinessStatus, string> = {
  trial: "Trial",
  paid: "Paid",
  past_due: "Payment due",
  free: "Free",
  closed: "Closed",
  billed_with: "On another bill",
};

export type Tone = "mint" | "amber" | "red" | "slate" | "sky" | "violet";

export const STATUS_TONE: Record<BusinessStatus, Tone> = {
  trial: "sky",
  paid: "mint",
  past_due: "red",
  free: "slate",
  closed: "slate",
  billed_with: "violet",
};

export const FEATURE_LABELS: Record<string, string> = {
  attendance: "Attendance",
  leave: "Leave",
  digest: "Daily summary",
  payroll: "Salary",
  advances: "Advances",
  payslips: "Payslips",
  assistant: "Mint AI assistant",
  reports: "Reports",
  roster: "Roster",
  roster_repeat: "Repeat roster every week",
  branches: "Multiple branches",
  whatsapp_payslips: "Payslips on WhatsApp",
  whatsapp_assistant: "WhatsApp assistant",
  face_match: "Face check",
  ca_access: "Accountant access",
  priority_support: "Priority support",
};

/** "+91 98765 43210" */
export function phone(p: string | null | undefined): string {
  if (!p) return "—";
  const m = /^\+91(\d{5})(\d{5})$/.exec(p);
  return m ? `+91 ${m[1]} ${m[2]}` : p;
}

/** Readable name for a setting key: "accounts.restoreDays" → "Accounts · restore days". */
export function configLabel(key: string): string {
  const [group, ...rest] = key.split(".");
  const name = rest.join(".").replace(/([a-z])([A-Z])/g, "$1 $2").toLowerCase();
  return `${group.charAt(0).toUpperCase()}${group.slice(1)} · ${name}`;
}

/** Display a setting value compactly. */
export function configValue(v: unknown): string {
  if (Array.isArray(v)) return v.join(", ");
  if (typeof v === "boolean") return v ? "On" : "Off";
  if (v === null || v === undefined) return "—";
  return String(v);
}

/** Parse what an admin typed back into the setting's type (same as the default's). */
export function parseConfigInput(raw: string, like: unknown): { ok: true; value: unknown } | { ok: false; error: string } {
  const t = raw.trim();
  if (typeof like === "number") {
    const n = Number(t);
    return t !== "" && Number.isFinite(n) ? { ok: true, value: n } : { ok: false, error: "Enter a number" };
  }
  if (typeof like === "boolean") {
    if (/^(on|true|yes|1)$/i.test(t)) return { ok: true, value: true };
    if (/^(off|false|no|0)$/i.test(t)) return { ok: true, value: false };
    return { ok: false, error: "Enter on or off" };
  }
  if (Array.isArray(like)) {
    const parts = t ? t.split(",").map((s) => s.trim()).filter(Boolean) : [];
    const numeric = like.length > 0 && like.every((x) => typeof x === "number");
    if (numeric) {
      const nums = parts.map(Number);
      return nums.every((n) => Number.isFinite(n)) ? { ok: true, value: nums } : { ok: false, error: "Enter numbers separated by commas" };
    }
    return { ok: true, value: parts };
  }
  return t ? { ok: true, value: t } : { ok: false, error: "Can't be empty" };
}

/** Rupees typed by an admin → paise. */
export function parseRupees(raw: string): number | null {
  const t = raw.replace(/[₹,\s]/g, "");
  if (!/^\d+(\.\d{1,2})?$/.test(t)) return null;
  return Math.round(Number(t) * 100);
}

/** A clean round number at or above the max for a chart's top line (1–5, then 10, 20, 50, 100…). */
export function niceTop(max: number): number {
  if (max <= 5) return Math.max(1, Math.ceil(max));
  const pow = 10 ** Math.floor(Math.log10(max));
  for (const m of [1, 2, 5, 10]) if (m * pow >= max) return m * pow;
  return 10 * pow;
}
