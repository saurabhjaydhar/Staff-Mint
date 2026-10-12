import { describe, expect, it } from "vitest";
import { dictionaries, fill } from "./i18n";

describe("fill", () => {
  it("fills placeholders in both languages", () => {
    expect(fill(dictionaries.en.at_work, { n: 6, total: 9 })).toBe("6 of 9 at work");
    expect(fill(dictionaries.hi.at_work, { n: 6, total: 9 })).toBe("9 में से 6 काम पर");
    expect(fill(dictionaries.en.leave_effect, { left: 4, type: "paid", after: 2 })).toBe("Has 4 paid leaves left. After this: 2.");
  });

  it("leaves unknown placeholders empty instead of printing {braces}", () => {
    expect(fill("Hi {name}{x}", { name: "Pooja" })).toBe("Hi Pooja");
  });
});
