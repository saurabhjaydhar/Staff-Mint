import { describe, expect, it } from "vitest";
import { displayPhone, EMAIL_RE, indianMobile, initials } from "./profile";

describe("profile helpers", () => {
  it("accepts Indian mobiles in common shapes", () => {
    expect(indianMobile("98765 43210")).toBe("9876543210");
    expect(indianMobile("+91 98765-43210")).toBe("9876543210");
    expect(indianMobile("09876543210")).toBe("9876543210");
    expect(indianMobile("12345 67890")).toBeNull();
    expect(indianMobile("98765")).toBeNull();
  });

  it("formats E.164 for display", () => {
    expect(displayPhone("+919876543210")).toBe("+91 98765 43210");
    expect(displayPhone("+14155550123")).toBe("+14155550123");
  });

  it("makes initials, including Hindi names", () => {
    expect(initials("Rakesh Sharma")).toBe("RS");
    expect(initials("  pooja ")).toBe("P");
    expect(initials("")).toBe("?");
    expect(initials("राकेश शर्मा")).toBe("राश");
  });

  it("checks email shape", () => {
    expect(EMAIL_RE.test("a@b.in")).toBe(true);
    expect(EMAIL_RE.test("a@b")).toBe(false);
  });
});
