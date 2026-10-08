import { describe, expect, it } from "vitest";
import { diffObjects } from "./diff";
import { canAccess, homeFor, navFor } from "./roles";
import { defaultPayrollMonth, previousMonth } from "./format";

describe("roles", () => {
  it("CA sees only payroll and reports", () => {
    expect(navFor("ca").map((n) => n.href)).toEqual(["/payroll", "/reports"]);
    expect(canAccess("ca", "/staff")).toBe(false);
    expect(canAccess("ca", "/reports")).toBe(true);
    expect(homeFor("ca")).toBe("/payroll");
  });
  it("owner sees everything, employee nothing", () => {
    expect(navFor("owner").length).toBeGreaterThan(8);
    expect(navFor("employee")).toEqual([]);
    expect(canAccess("manager", "/billing")).toBe(false);
  });
});

describe("diffObjects", () => {
  it("flattens and reports changes", () => {
    const d = diffObjects(
      { name: "Ramesh", ratePaise: 1500000, consent: { location: false }, tags: [1] },
      { name: "Ramesh", ratePaise: 1600000, consent: { location: true }, phone: "+91" },
    );
    expect(d).toEqual([
      { path: "consent.location", before: false, after: true, kind: "changed" },
      { path: "phone", before: undefined, after: "+91", kind: "added" },
      { path: "ratePaise", before: 1500000, after: 1600000, kind: "changed" },
      { path: "tags", before: [1], after: undefined, kind: "removed" },
    ]);
  });
  it("handles null before (creation)", () => {
    expect(diffObjects(null, { a: 1 })).toEqual([{ path: "a", before: undefined, after: 1, kind: "added" }]);
  });
});

describe("months", () => {
  it("computes previous and default payroll month", () => {
    expect(previousMonth(new Date(2026, 0, 10))).toBe("2025-12");
    expect(defaultPayrollMonth(new Date(2026, 9, 5))).toBe("2026-09");
    expect(defaultPayrollMonth(new Date(2026, 9, 25))).toBe("2026-10");
  });
});
