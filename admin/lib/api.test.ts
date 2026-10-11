import { afterEach, describe, expect, it, vi } from "vitest";
import { ApiError, qs, request, setSignedOutHandler } from "./api";

afterEach(() => {
  vi.unstubAllGlobals();
  setSignedOutHandler(null);
});

const respond = (status: number, body: unknown) => vi.fn(async () => new Response(JSON.stringify(body), { status }));

describe("admin api client", () => {
  it("unwraps data and turns errors into ApiError", async () => {
    vi.stubGlobal("fetch", respond(200, { data: { ok: 1 } }));
    expect(await request("GET", "/admin/stats", undefined, { auth: false })).toEqual({ ok: 1 });
    vi.stubGlobal("fetch", respond(409, { error: { code: "CONFLICT", message: "Keep at least one active admin" } }));
    const err = await request("PATCH", "/admin/admins/x", {}, { auth: false }).catch((e) => e);
    expect(err).toBeInstanceOf(ApiError);
    expect(err).toMatchObject({ status: 409, code: "CONFLICT", message: "Keep at least one active admin" });
  });

  it("signs out on 401 for signed-in calls", async () => {
    const out = vi.fn();
    setSignedOutHandler(out);
    vi.stubGlobal("fetch", respond(401, { error: { code: "UNAUTHORIZED", message: "Admin session ended" } }));
    await request("GET", "/admin/me").catch(() => undefined);
    expect(out).toHaveBeenCalledTimes(1);
    // Wrong password on the sign-in screen is not a sign-out.
    await request("POST", "/admin-auth/login", {}, { auth: false }).catch(() => undefined);
    expect(out).toHaveBeenCalledTimes(1);
  });

  it("explains network failures", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => Promise.reject(new TypeError("fetch failed"))));
    await expect(request("GET", "/admin/stats")).rejects.toMatchObject({ code: "NETWORK_ERROR" });
  });

  it("builds query strings without empty values", () => {
    expect(qs({ search: "gupta", status: "", page: 2, x: undefined })).toBe("?search=gupta&page=2");
    expect(qs({})).toBe("");
  });
});
