import type { AttendanceStatus, DisplayStatus } from "./types";

export interface StatusStyle {
  code: string;
  label: string;
  className: string;
}

// Codes match the PRD grid: P/A/HD/L/WO/H/–
export const STATUS_STYLES: Record<DisplayStatus, StatusStyle> = {
  present: { code: "P", label: "Present", className: "bg-emerald-100 text-emerald-800" },
  late: { code: "P", label: "Present (late)", className: "bg-amber-100 text-amber-800 ring-1 ring-amber-300" },
  checked_in: { code: "P", label: "Checked in", className: "bg-emerald-50 text-emerald-700 ring-1 ring-emerald-200" },
  absent: { code: "A", label: "Absent", className: "bg-red-100 text-red-700" },
  half_day: { code: "HD", label: "Half day", className: "bg-orange-100 text-orange-800" },
  leave: { code: "L", label: "Leave", className: "bg-sky-100 text-sky-800" },
  holiday: { code: "H", label: "Holiday", className: "bg-violet-100 text-violet-800" },
  week_off: { code: "WO", label: "Week off", className: "bg-slate-200 text-slate-700" },
  not_marked: { code: "–", label: "Not marked", className: "bg-white text-slate-400 ring-1 ring-slate-200" },
};

export function statusStyle(s: DisplayStatus | null | undefined): StatusStyle {
  return STATUS_STYLES[s ?? "not_marked"] ?? STATUS_STYLES.not_marked;
}

export const OVERRIDE_STATUSES: { value: AttendanceStatus; label: string }[] = [
  { value: "present", label: "Present (P)" },
  { value: "absent", label: "Absent (A)" },
  { value: "half_day", label: "Half day (HD)" },
  { value: "leave", label: "Leave (L)" },
  { value: "holiday", label: "Holiday (H)" },
  { value: "week_off", label: "Week off (WO)" },
];

/** Map a display status to the status pre-selected in the override form. */
export function overrideDefault(s: DisplayStatus | null | undefined): AttendanceStatus {
  switch (s) {
    case "late":
    case "checked_in":
    case "present":
      return "present";
    case "absent":
    case "half_day":
    case "leave":
    case "holiday":
    case "week_off":
      return s;
    default:
      return "present";
  }
}
