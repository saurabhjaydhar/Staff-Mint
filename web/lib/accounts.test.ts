import { describe, expect, it } from "vitest";
import { newBusinessLabel, switchTargets, webCanOpen } from "./accounts";
import type { Membership } from "./types";

const m = (id: string, role: Membership["role"]): Membership => ({ id, companyId: `c-${id}`, companyName: id, businessType: "shop", role, lastUsedAt: null });

describe("accounts", () => {
  it("staff accounts open in the mobile app, not on the web", () => {
    expect(webCanOpen(m("a", "employee"))).toBe(false);
    expect(webCanOpen(m("a", "manager"))).toBe(true);
    expect(webCanOpen(m("a", "ca"))).toBe(true);
  });

  it("switch targets skip the open account and staff accounts", () => {
    const list = [m("own", "owner"), m("job", "employee"), m("client", "ca")];
    expect(switchTargets(list, "own").map((x) => x.id)).toEqual(["client"]);
    expect(switchTargets(undefined, null)).toEqual([]);
  });

  it("new business label depends on owning one already", () => {
    expect(newBusinessLabel([m("job", "employee")])).toBe("acc_new_first");
    expect(newBusinessLabel([m("own", "owner")])).toBe("acc_new");
  });
});
