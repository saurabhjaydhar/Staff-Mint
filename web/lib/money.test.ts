import { describe, expect, it } from "vitest";
import { formatPaise, groupIndian, paiseToRupeeInput, parseRupeesToPaise } from "./money";

describe("groupIndian", () => {
  it.each([
    ["0", "0"],
    ["999", "999"],
    ["1000", "1,000"],
    ["99999", "99,999"],
    ["100000", "1,00,000"],
    ["1234567", "12,34,567"],
    ["123456789", "12,34,56,789"],
  ])("%s -> %s", (input, out) => expect(groupIndian(input)).toBe(out));
});

describe("formatPaise", () => {
  it("formats rupees with Indian grouping", () => {
    expect(formatPaise(0)).toBe("₹0");
    expect(formatPaise(100)).toBe("₹1");
    expect(formatPaise(1500000)).toBe("₹15,000");
    expect(formatPaise(12345678900)).toBe("₹12,34,56,789");
  });
  it("shows paise only when non-zero by default", () => {
    expect(formatPaise(123456789)).toBe("₹12,34,567.89");
    expect(formatPaise(1505)).toBe("₹15.05");
  });
  it("supports decimals options and symbol toggle", () => {
    expect(formatPaise(1500000, { decimals: "always" })).toBe("₹15,000.00");
    expect(formatPaise(1500050, { decimals: "never" })).toBe("₹15,001");
    expect(formatPaise(1500049, { decimals: "never" })).toBe("₹15,000");
    expect(formatPaise(1500000, { symbol: false })).toBe("15,000");
  });
  it("handles negatives and missing values", () => {
    expect(formatPaise(-250000)).toBe("-₹2,500");
    expect(formatPaise(null)).toBe("—");
    expect(formatPaise(undefined)).toBe("—");
    expect(formatPaise(Number.NaN)).toBe("—");
  });
});

describe("parseRupeesToPaise", () => {
  it.each<[string | number, number | null]>([
    ["12000", 1200000],
    ["12,000", 1200000],
    ["₹12,000/-", 1200000],
    ["Rs. 12000.50", 1200050],
    ["12k", 1200000],
    ["12.5K", 1250000],
    ["1.2 lakh", 12000000],
    ["1.5L", 15000000],
    ["15000/month", 1500000],
    [" 600 ", 60000],
    [450.5, 45050],
    ["", null],
    ["abc", null],
    ["-500", null],
    ["12k5", null],
  ])("%j -> %j", (input, out) => expect(parseRupeesToPaise(input)).toBe(out));
});

describe("paiseToRupeeInput", () => {
  it("renders editable rupee text", () => {
    expect(paiseToRupeeInput(1500000)).toBe("15000");
    expect(paiseToRupeeInput(1250050)).toBe("12500.5");
    expect(paiseToRupeeInput(null)).toBe("");
  });
});
