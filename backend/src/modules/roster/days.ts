import { weekdayOf } from '../../lib/dates.js';

type ShiftLike = { _id?: unknown; weeklyOff?: number[] | null; weeklyOffWeeks?: Record<string, number[]> | null };

/** Which week of the month [d] is in, as people count it for "2nd Saturday": days 1–7 are week 1, 8–14 week 2 … */
export const weekOfMonth = (d: string) => Math.ceil(Number(d.slice(8, 10)) / 7);

/**
 * The shift's weekly off falls on [d]. A weekday listed in `weeklyOffWeeks` is off only in those weeks of the
 * month ("1st and 3rd Saturday"); otherwise it is off every week.
 */
export function isShiftOff(shift: ShiftLike | null | undefined, d: string) {
  const wd = weekdayOf(d);
  if (!(shift?.weeklyOff ?? [0]).includes(wd)) return false;
  const weeks = shift?.weeklyOffWeeks?.[String(wd)];
  return !weeks?.length || weeks.includes(weekOfMonth(d));
}

/** A person's usual shift: their own, else their branch's (or the main branch's), else the default shift. */
export function usualShiftResolver<S extends ShiftLike>(shifts: S[], branches: { _id: unknown; shiftId?: unknown; isDefault?: boolean | null }[]) {
  const shiftById = new Map(shifts.map((s) => [String(s._id), s]));
  const branchById = new Map(branches.map((b) => [String(b._id), b]));
  const defaultBranch = branches.find((b) => b.isDefault);
  const defaultShift = shifts.find((s: any) => s.isDefault) ?? shifts[0];
  return (e: { shiftId?: unknown; branchId?: unknown }): S | undefined => {
    const branch = e.branchId ? branchById.get(String(e.branchId)) : defaultBranch;
    return shiftById.get(String(e.shiftId ?? '')) ?? shiftById.get(String(branch?.shiftId ?? '')) ?? defaultShift;
  };
}
