import { describe, expect, it } from "vitest";
import {
  buildFixes,
  cellDisplayValue,
  cellInputValue,
  daysInMonth,
  displayColumns,
  draftKey,
  duplicateMappings,
  flaggedRows,
  initialSkips,
  mappingOptions,
  mappingPatch,
  moneyInputError,
  normalizeFixValue,
  otherIssues,
  sampleTemplateCsv,
  secondsLeft,
  toggleSkip,
  undoDeadline,
  unresolvedCount,
} from "./importHelpers";
import type { ImportSession } from "./types";

const session: ImportSession = {
  id: "imp1",
  kind: "staff",
  source: "auto",
  status: "review",
  headers: ["Naam", "Mobile", "Tankhwah", "Remarks", "Post"],
  mapping: { Naam: "name", Mobile: "phone", Tankhwah: "ratePaise", Remarks: null, Post: "designation" },
  rows: [
    { index: 0, values: { name: "Ramesh", phone: "+919876543210", ratePaise: 1500000, designation: "Helper" }, issues: [] },
    {
      index: 1,
      values: { name: "Sunita", phone: "98765", ratePaise: 1200000 },
      issues: [{ field: "phone", message: "Phone must have 10 digits" }],
    },
    {
      index: 2,
      values: { name: "", phone: "+919800000000", ratePaise: null },
      issues: [
        { field: "name", message: "Name is required" },
        { field: "ratePaise", message: "Could not read salary" },
        { field: "joiningDate", message: "Unclear date 03/04/2024" },
      ],
    },
  ],
  flaggedCount: 2,
  totalRows: 3,
};

describe("flaggedRows", () => {
  it("returns only rows with issues", () => {
    expect(flaggedRows(session).map((r) => r.index)).toEqual([1, 2]);
  });
  it("counts unresolved flagged rows excluding skipped ones", () => {
    expect(unresolvedCount(session, [])).toBe(2);
    expect(unresolvedCount(session, [2])).toBe(1);
  });
});

describe("columns and mapping", () => {
  it("shows mapped fields in header order plus issue-only fields", () => {
    expect(displayColumns(session)).toEqual(["name", "phone", "ratePaise", "designation", "joiningDate"]);
  });
  it("collects row issues that have no displayed column", () => {
    expect(otherIssues(session.rows[2], ["name", "phone", "ratePaise"])).toEqual(["joiningDate: Unclear date 03/04/2024"]);
  });
  it("offers known fields plus unknown values used by the backend", () => {
    const opts = mappingOptions({ mapping: { "01": "day:01", Naam: "name" } });
    expect(opts).toContain("lastSalaryPaise");
    expect(opts[opts.length - 1]).toBe("day:01");
  });
  it("builds mapping PATCH bodies, ignoring with null", () => {
    expect(mappingPatch("Remarks", "designation")).toEqual({ mapping: { Remarks: "designation" } });
    expect(mappingPatch("Post", "")).toEqual({ mapping: { Post: null } });
  });
  it("detects a field mapped twice", () => {
    expect(duplicateMappings({ A: "name", B: "name", C: "phone", D: null })).toEqual(["name"]);
  });
});

describe("cell values and fixes", () => {
  it("edits paise fields in rupees", () => {
    expect(cellInputValue("ratePaise", 1500000)).toBe("15000");
    expect(cellInputValue("name", null)).toBe("");
    expect(cellDisplayValue("ratePaise", 1500000)).toBe("₹15,000");
    expect(cellDisplayValue("phone", "")).toBe("—");
  });

  it("normalizes typed values", () => {
    // money is sent as rupee text for the server's cleaner
    expect(normalizeFixValue("ratePaise", " 12k ")).toBe("12k");
    expect(normalizeFixValue("advanceBalancePaise", "₹2,000/-")).toBe("₹2,000/-");
    expect(normalizeFixValue("paidLeaveBalance", "4")).toBe(4);
    expect(normalizeFixValue("wageType", "Daily")).toBe("daily");
    expect(normalizeFixValue("wageType", "mahina")).toBe("monthly");
    expect(normalizeFixValue("phone", " 9876543210 ")).toBe("9876543210");
    expect(normalizeFixValue("name", "   ")).toBeNull();
  });

  it("builds fixes from drafts, skipping unchanged cells", () => {
    const drafts = {
      [draftKey(2, "ratePaise")]: "14,000",
      [draftKey(1, "phone")]: "9876543211",
      [draftKey(1, "ratePaise")]: "12000", // unchanged (1200000 paise)
      [draftKey(2, "name")]: "Mohan",
    };
    expect(buildFixes(session, drafts)).toEqual([
      { row: 1, field: "phone", value: "9876543211" },
      { row: 2, field: "name", value: "Mohan" },
      { row: 2, field: "ratePaise", value: "14,000" },
    ]);
  });

  it("validates money input client-side", () => {
    expect(moneyInputError("ratePaise", "12k")).toBeNull();
    expect(moneyInputError("ratePaise", "twelve")).toMatch(/amount/);
    expect(moneyInputError("name", "twelve")).toBeNull();
    expect(moneyInputError("lastSalaryPaise", "")).toBeNull();
  });
});

describe("skips", () => {
  it("toggles rows in a sorted list", () => {
    expect(toggleSkip([], 3)).toEqual([3]);
    expect(toggleSkip([5, 3], 1)).toEqual([1, 3, 5]);
    expect(toggleSkip([1, 3], 3)).toEqual([1]);
  });
  it("reads initial skips from the session when present", () => {
    expect(initialSkips(session)).toEqual([]);
    expect(initialSkips({ ...session, skipRows: [2, 1] })).toEqual([1, 2]);
    expect(initialSkips({ rows: [{ index: 4, values: {}, issues: [], skipped: true }] })).toEqual([4]);
  });
});

describe("undo countdown", () => {
  it("computes remaining seconds, never negative", () => {
    const now = Date.parse("2026-10-08T10:00:00.000Z");
    expect(secondsLeft("2026-10-08T10:00:30.000Z", now)).toBe(30);
    expect(secondsLeft("2026-10-08T10:00:00.400Z", now)).toBe(1);
    expect(secondsLeft("2026-10-08T09:59:00.000Z", now)).toBe(0);
    expect(secondsLeft(undefined, now)).toBe(0);
    expect(secondsLeft("garbage", now)).toBe(0);
  });
});

describe("sample templates", () => {
  it("staff template has a header and quoted-safe rows", () => {
    const csv = sampleTemplateCsv("staff");
    const lines = csv.trim().split("\r\n");
    expect(lines[0].startsWith("Name,Phone,Salary")).toBe(true);
    expect(lines.length).toBe(4);
  });
  it("attendance template has one column per day of the month", () => {
    expect(daysInMonth("2026-02")).toBe(28);
    expect(daysInMonth("2028-02")).toBe(29);
    const header = sampleTemplateCsv("attendance", "2026-02").split("\r\n")[0].split(",");
    expect(header).toHaveLength(2 + 28);
    expect(header.slice(0, 3)).toEqual(["Name", "Phone", "1"]);
  });
});

describe("undoDeadline", () => {
  const committedAt = Date.parse("2026-10-08T10:00:00.000Z");
  it("uses the server deadline when plausible", () => {
    expect(undoDeadline("2026-10-08T10:00:28.000Z", committedAt)).toBe(committedAt + 28_000);
  });
  it("falls back to 30s when the server clock is skewed or missing", () => {
    expect(undoDeadline("2026-10-08T09:59:00.000Z", committedAt)).toBe(committedAt + 30_000);
    expect(undoDeadline("2026-10-08T11:00:00.000Z", committedAt)).toBe(committedAt + 30_000);
    expect(undoDeadline(undefined, committedAt)).toBe(committedAt + 30_000);
  });
});
