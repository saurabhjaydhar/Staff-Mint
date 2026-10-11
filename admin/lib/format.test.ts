import { describe, expect, it } from "vitest";
import { ago, configLabel, configValue, count, daysUntil, niceTop, parseConfigInput, parseRupees, phone, rupees, rupeesShort } from "./format";

describe("money", () => {
  it("formats rupees the Indian way", () => {
    expect(rupees(12345600)).toBe("₹1,23,456");
    expect(rupeesShort(95000)).toBe("₹950");
    expect(rupeesShort(1240000)).toBe("₹12.4K");
    expect(rupeesShort(32000000)).toBe("₹3.2L");
    expect(rupeesShort(1100000000)).toBe("₹1.1Cr");
    expect(rupeesShort(0)).toBe("₹0");
  });

  it("reads rupees typed by an admin", () => {
    expect(parseRupees("₹1,499")).toBe(149900);
    expect(parseRupees("499.50")).toBe(49950);
    expect(parseRupees("abc")).toBeNull();
    expect(parseRupees("-5")).toBeNull();
  });
});

describe("numbers, dates, phones", () => {
  it("compacts big counts", () => {
    expect(count(1284)).toBe("1,284");
    expect(count(12900)).toBe("12.9K");
    expect(count(340000)).toBe("3.4L");
  });

  it("says how long ago", () => {
    const now = new Date("2026-10-11T12:00:00Z").getTime();
    expect(ago("2026-10-11T11:59:30Z", now)).toBe("just now");
    expect(ago("2026-10-11T11:55:00Z", now)).toBe("5 min ago");
    expect(ago("2026-10-11T09:00:00Z", now)).toBe("3 h ago");
    expect(ago("2026-10-10T09:00:00Z", now)).toBe("1 day ago");
    expect(ago("2026-10-08T09:00:00Z", now)).toBe("3 days ago");
    expect(ago(null, now)).toBe("—");
  });

  it("counts days left, part of a day as one", () => {
    const now = new Date("2026-10-11T12:00:00Z").getTime();
    expect(daysUntil("2026-10-25T12:00:00Z", now)).toBe(14);
    expect(daysUntil("2026-10-11T20:00:00Z", now)).toBe(1);
    expect(daysUntil("2026-10-10T12:00:00Z", now)).toBe(0);
  });

  it("spaces Indian phone numbers", () => {
    expect(phone("+919876543210")).toBe("+91 98765 43210");
    expect(phone("+14155550100")).toBe("+14155550100");
    expect(phone(null)).toBe("—");
  });

  it("rounds a chart's top line to a clean number", () => {
    expect(niceTop(0)).toBe(1);
    expect(niceTop(3)).toBe(3);
    expect(niceTop(7)).toBe(10);
    expect(niceTop(13)).toBe(20);
    expect(niceTop(41)).toBe(50);
    expect(niceTop(120)).toBe(200);
  });
});

describe("settings", () => {
  it("names keys and shows values", () => {
    expect(configLabel("accounts.restoreDays")).toBe("Accounts · restore days");
    expect(configValue([3, 1])).toBe("3, 1");
    expect(configValue(true)).toBe("On");
  });

  it("keeps the setting's type when parsing what was typed", () => {
    expect(parseConfigInput("45", 30)).toEqual({ ok: true, value: 45 });
    expect(parseConfigInput("thirty", 30)).toMatchObject({ ok: false });
    expect(parseConfigInput("off", true)).toEqual({ ok: true, value: false });
    expect(parseConfigInput("5, 2", [3, 1])).toEqual({ ok: true, value: [5, 2] });
    expect(parseConfigInput("5, x", [3, 1])).toMatchObject({ ok: false });
    expect(parseConfigInput("paid, sick", ["paid"])).toEqual({ ok: true, value: ["paid", "sick"] });
    expect(parseConfigInput("pro", "starter")).toEqual({ ok: true, value: "pro" });
    expect(parseConfigInput("  ", "starter")).toMatchObject({ ok: false });
  });
});
