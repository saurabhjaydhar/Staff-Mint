import { describe, expect, it } from "vitest";
import { trialBanner, trialDaysLeft } from "./trial";
import type { Trial } from "./types";

const now = new Date(2026, 9, 11, 12);
const trial = (endsAt: Date): Trial => ({
  planCode: "pro",
  planName: "Pro",
  endsAt: endsAt.toISOString(),
  daysLeft: 0,
  active: true,
  ended: false,
  paidFeatures: ["payroll", "face_match", "priority_support"],
});

describe("free trial", () => {
  it("counts part of a day as a whole day", () => {
    expect(trialDaysLeft(trial(new Date(2026, 9, 25, 12)), now)).toBe(14);
    expect(trialDaysLeft(trial(new Date(2026, 9, 11, 20)), now)).toBe(1);
    expect(trialDaysLeft(trial(new Date(2026, 9, 11, 11)), now)).toBe(0);
  });

  it("shows a countdown to owners, warning in the last 3 days", () => {
    expect(trialBanner(trial(new Date(2026, 9, 25, 12)), { isOwner: true }, now)).toEqual({ kind: "active", days: 14, soon: false, endsOn: "25 Oct", planName: "Pro" });
    expect(trialBanner(trial(new Date(2026, 9, 13, 12)), { isOwner: true }, now)).toMatchObject({ kind: "active", days: 2, soon: true });
    expect(trialBanner(trial(new Date(2026, 9, 25, 12)), { isOwner: false }, now)).toEqual({ kind: "none" });
    expect(trialBanner(null, { isOwner: true }, now)).toEqual({ kind: "none" });
  });

  it("after the end: what is paused, until dismissed for that trial", () => {
    const t = trial(new Date(2026, 9, 9, 12));
    expect(trialBanner(t, { isOwner: true }, now)).toEqual({ kind: "ended", paused: ["payroll", "face_match"] });
    expect(trialBanner(t, { isOwner: true, dismissedFor: t.endsAt }, now)).toEqual({ kind: "none" });
    expect(trialBanner(t, { isOwner: true, dismissedFor: "2026-01-01T00:00:00.000Z" }, now)).toMatchObject({ kind: "ended" });
  });
});
