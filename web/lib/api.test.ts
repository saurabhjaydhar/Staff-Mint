import { describe, expect, it, vi } from "vitest";
import { ApiClient, ApiError, filenameFromDisposition, parseErrorResponse } from "./api";
import { memoryTokenStore } from "./tokens";

const BASE = "http://api.test/api/v1";

function json(status: number, body: unknown, headers: Record<string, string> = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...headers },
  });
}

const expired = () => json(401, { error: { code: "TOKEN_EXPIRED", message: "Access token expired" } });

type Call = { url: string; init: RequestInit };

function mockFetch(handler: (url: string, init: RequestInit, n: number) => Response | Promise<Response>) {
  const calls: Call[] = [];
  const fn = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input);
    calls.push({ url, init: init || {} });
    return handler(url, init || {}, calls.length);
  });
  return { fn: fn as unknown as typeof fetch, calls };
}

function authHeader(init: RequestInit): string | undefined {
  return (init.headers as Record<string, string> | undefined)?.Authorization;
}

describe("ApiClient basics", () => {
  it("unwraps {data}, sends bearer token, query string and Accept-Language", async () => {
    const { fn, calls } = mockFetch(() => json(200, { data: [{ id: "e1" }] }));
    const client = new ApiClient({
      baseUrl: BASE + "/",
      fetch: fn,
      tokens: memoryTokenStore({ accessToken: "A1", refreshToken: "R1" }),
      getLanguage: () => "hi",
    });
    const data = await client.get<{ id: string }[]>("/employees", { status: "active", search: "", branchId: undefined });
    expect(data).toEqual([{ id: "e1" }]);
    expect(calls[0].url).toBe(`${BASE}/employees?status=active`);
    expect(authHeader(calls[0].init)).toBe("Bearer A1");
    expect((calls[0].init.headers as Record<string, string>)["Accept-Language"]).toBe("hi");
  });

  it("sends JSON bodies with content-type and FormData untouched", async () => {
    const { fn, calls } = mockFetch(() => json(200, { data: { ok: true } }));
    const client = new ApiClient({ baseUrl: BASE, fetch: fn, tokens: memoryTokenStore({ accessToken: "A", refreshToken: "R" }) });
    await client.post("/imports", { text: "a,b" });
    expect((calls[0].init.headers as Record<string, string>)["Content-Type"]).toBe("application/json");
    expect(calls[0].init.body).toBe(JSON.stringify({ text: "a,b" }));

    const fd = new FormData();
    fd.append("kind", "staff");
    await client.post("/imports", fd);
    expect((calls[1].init.headers as Record<string, string>)["Content-Type"]).toBeUndefined();
    expect(calls[1].init.body).toBe(fd);
  });

  it("parses {error:{code,message,details}} into ApiError", async () => {
    const { fn } = mockFetch(() =>
      json(402, { error: { code: "PLAN_LIMIT", message: "Staff limit reached", details: { limit: 10 } } }),
    );
    const client = new ApiClient({ baseUrl: BASE, fetch: fn, tokens: memoryTokenStore({ accessToken: "A", refreshToken: "R" }) });
    const err = await client.post("/employees", { name: "x", phone: "1" }).catch((e) => e);
    expect(err).toBeInstanceOf(ApiError);
    expect(err).toMatchObject({ status: 402, code: "PLAN_LIMIT", message: "Staff limit reached", details: { limit: 10 } });
  });

  it("falls back to a status-based code for non-JSON errors", async () => {
    const err = await parseErrorResponse(new Response("<html>bad gateway</html>", { status: 502, statusText: "Bad Gateway" }));
    expect(err.code).toBe("INTERNAL");
    expect(err.message).toBe("Bad Gateway");
    const nf = await parseErrorResponse(new Response("", { status: 404 }));
    expect(nf.code).toBe("NOT_FOUND");
  });

  it("maps network failures to NETWORK_ERROR", async () => {
    const fn = vi.fn(async () => {
      throw new TypeError("fetch failed");
    }) as unknown as typeof fetch;
    const client = new ApiClient({ baseUrl: BASE, fetch: fn, tokens: memoryTokenStore() });
    await expect(client.get("/me")).rejects.toMatchObject({ code: "NETWORK_ERROR", status: 0 });
  });

  it("does not attach a token for auth:false requests", async () => {
    const { fn, calls } = mockFetch(() => json(200, { data: { requestId: "r" } }));
    const client = new ApiClient({ baseUrl: BASE, fetch: fn, tokens: memoryTokenStore({ accessToken: "A", refreshToken: "R" }) });
    await client.post("/auth/otp/request", { phone: "9876543210" }, { auth: false });
    expect(authHeader(calls[0].init)).toBeUndefined();
  });
});

describe("token refresh", () => {
  it("refreshes on 401 TOKEN_EXPIRED, stores rotated tokens and retries once", async () => {
    const tokens = memoryTokenStore({ accessToken: "OLD", refreshToken: "R1" });
    const { fn, calls } = mockFetch((url, init) => {
      if (url.endsWith("/auth/refresh")) {
        expect(JSON.parse(String(init.body))).toEqual({ refreshToken: "R1" });
        return json(200, { data: { accessToken: "NEW", refreshToken: "R2" } });
      }
      return authHeader(init) === "Bearer NEW" ? json(200, { data: { user: { id: "u1" } } }) : expired();
    });
    const client = new ApiClient({ baseUrl: BASE, fetch: fn, tokens });
    const me = await client.get<{ user: { id: string } }>("/me");
    expect(me.user.id).toBe("u1");
    expect(tokens.get()).toEqual({ accessToken: "NEW", refreshToken: "R2" });
    expect(calls.map((c) => c.url.replace(BASE, ""))).toEqual(["/me", "/auth/refresh", "/me"]);
  });

  it("uses a single refresh for concurrent expired requests", async () => {
    const tokens = memoryTokenStore({ accessToken: "OLD", refreshToken: "R1" });
    let refreshCalls = 0;
    const { fn } = mockFetch(async (url, init) => {
      if (url.endsWith("/auth/refresh")) {
        refreshCalls++;
        await new Promise((r) => setTimeout(r, 10));
        return json(200, { data: { accessToken: "NEW", refreshToken: "R2" } });
      }
      return authHeader(init) === "Bearer NEW" ? json(200, { data: url }) : expired();
    });
    const client = new ApiClient({ baseUrl: BASE, fetch: fn, tokens });
    const results = await Promise.all([client.get("/a"), client.get("/b"), client.get("/c")]);
    expect(results).toEqual([`${BASE}/a`, `${BASE}/b`, `${BASE}/c`]);
    expect(refreshCalls).toBe(1);
  });

  it("clears tokens and signals auth failure when refresh fails", async () => {
    const tokens = memoryTokenStore({ accessToken: "OLD", refreshToken: "R1" });
    const onAuthFailure = vi.fn();
    const { fn, calls } = mockFetch((url) =>
      url.endsWith("/auth/refresh")
        ? json(401, { error: { code: "UNAUTHORIZED", message: "Refresh token revoked" } })
        : expired(),
    );
    const client = new ApiClient({ baseUrl: BASE, fetch: fn, tokens, onAuthFailure });
    await expect(client.get("/me")).rejects.toMatchObject({ code: "UNAUTHORIZED" });
    expect(tokens.get()).toBeNull();
    expect(onAuthFailure).toHaveBeenCalledTimes(1);
    expect(calls).toHaveLength(2); // no retry after failed refresh
  });

  it("does not loop if the retried request is still unauthorized", async () => {
    const tokens = memoryTokenStore({ accessToken: "OLD", refreshToken: "R1" });
    const onAuthFailure = vi.fn();
    const { fn, calls } = mockFetch((url) =>
      url.endsWith("/auth/refresh") ? json(200, { data: { accessToken: "NEW", refreshToken: "R2" } }) : expired(),
    );
    const client = new ApiClient({ baseUrl: BASE, fetch: fn, tokens, onAuthFailure });
    await expect(client.get("/me")).rejects.toMatchObject({ code: "TOKEN_EXPIRED" });
    expect(calls).toHaveLength(3);
    expect(onAuthFailure).toHaveBeenCalledTimes(1);
    expect(tokens.get()).toBeNull();
  });

  it("does not refresh on other 401 codes, but signals auth failure", async () => {
    const tokens = memoryTokenStore({ accessToken: "BAD", refreshToken: "R1" });
    const onAuthFailure = vi.fn();
    const { fn, calls } = mockFetch(() => json(401, { error: { code: "UNAUTHORIZED", message: "Invalid token" } }));
    const client = new ApiClient({ baseUrl: BASE, fetch: fn, tokens, onAuthFailure });
    await expect(client.get("/me")).rejects.toMatchObject({ code: "UNAUTHORIZED" });
    expect(calls).toHaveLength(1);
    expect(onAuthFailure).toHaveBeenCalledTimes(1);
  });

  it("does not refresh for non-401 errors", async () => {
    const tokens = memoryTokenStore({ accessToken: "A", refreshToken: "R1" });
    const { fn, calls } = mockFetch(() => json(403, { error: { code: "FORBIDDEN", message: "No" } }));
    const client = new ApiClient({ baseUrl: BASE, fetch: fn, tokens });
    await expect(client.get("/audit-logs")).rejects.toMatchObject({ code: "FORBIDDEN", status: 403 });
    expect(calls).toHaveLength(1);
    expect(tokens.get()).not.toBeNull();
  });
});

describe("downloads", () => {
  it("returns blob and filename from Content-Disposition (refreshing if needed)", async () => {
    const tokens = memoryTokenStore({ accessToken: "OLD", refreshToken: "R1" });
    const { fn, calls } = mockFetch((url, init) => {
      if (url.endsWith("/auth/refresh")) return json(200, { data: { accessToken: "NEW", refreshToken: "R2" } });
      if (authHeader(init) !== "Bearer NEW") return expired();
      return new Response("PDFDATA", {
        status: 200,
        headers: { "Content-Type": "application/pdf", "Content-Disposition": 'attachment; filename="salary-2026-09.pdf"' },
      });
    });
    const client = new ApiClient({ baseUrl: BASE, fetch: fn, tokens });
    const { blob, filename } = await client.download("/reports/salary", { month: "2026-09", format: "pdf" }, "x.pdf");
    expect(filename).toBe("salary-2026-09.pdf");
    expect(await blob.text()).toBe("PDFDATA");
    expect(calls[2].url).toBe(`${BASE}/reports/salary?month=2026-09&format=pdf`);
  });

  it("parses filename variants", () => {
    expect(filenameFromDisposition("attachment; filename*=UTF-8''r%C3%A9port.xlsx")).toBe("réport.xlsx");
    expect(filenameFromDisposition("attachment; filename=export.zip")).toBe("export.zip");
    expect(filenameFromDisposition(null)).toBeNull();
  });
});

describe("account changed during refresh", () => {
  it("announces the change so the app can reload and say why", async () => {
    const target = new EventTarget();
    vi.stubGlobal("window", target);
    const seen: unknown[] = [];
    target.addEventListener("staffmint:account-changed", (e) => seen.push((e as CustomEvent).detail));
    const { fn } = mockFetch((url, init) => {
      if (url.endsWith("/auth/refresh")) {
        return json(200, {
          data: { accessToken: "A2", refreshToken: "R2", accountChange: { kind: "ended", reason: "removed", companyName: "Gupta Sweets", role: "owner", activeMembershipId: "m2" } },
        });
      }
      if (authHeader(init) === "Bearer A1") return json(401, { error: { code: "TOKEN_EXPIRED", message: "changed", details: { reason: "account_changed" } } });
      return json(200, { data: { ok: true } });
    });
    const client = new ApiClient({ baseUrl: BASE, fetch: fn, tokens: memoryTokenStore({ accessToken: "A1", refreshToken: "R1" }) });
    expect(await client.get("/me")).toEqual({ ok: true });
    expect(seen).toEqual([expect.objectContaining({ kind: "ended", companyName: "Gupta Sweets" })]);
    vi.unstubAllGlobals();
  });
});
