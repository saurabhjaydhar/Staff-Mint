import { describe, expect, it } from "vitest";
import { TABS, isActive } from "./nav";

describe("navigation", () => {
  it("has four bottom tabs on phones", () => {
    expect(TABS.map((t) => t.label)).toEqual(["Home", "Businesses", "Messages", "More"]);
  });

  it("marks the current screen", () => {
    expect(isActive("/", "/")).toBe(true);
    expect(isActive("/", "/businesses")).toBe(false);
    expect(isActive("/businesses", "/businesses/abc")).toBe(true);
    expect(isActive("/businesses", "/businessesx")).toBe(false);
    // Screens that live under More light up the More tab.
    expect(isActive("/more", "/plans")).toBe(true);
    expect(isActive("/more", "/settings")).toBe(true);
    expect(isActive("/more", "/messages")).toBe(false);
  });
});
