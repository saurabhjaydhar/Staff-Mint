import { beforeEach, describe, expect, it, vi } from "vitest";
import { FRESH_MS, clearCache, getEntry, invalidate, load, subscribe } from "./cache";

beforeEach(() => clearCache());

describe("cache", () => {
  it("shares one request between callers and reuses fresh data", async () => {
    const fetcher = vi.fn(async () => ({ n: 1 }));
    const [a, b] = await Promise.all([load("/x", fetcher), load("/x", fetcher)]);
    expect(a).toEqual({ n: 1 });
    expect(b).toBe(a);
    expect(fetcher).toHaveBeenCalledTimes(1);
    await load("/x", fetcher);
    expect(fetcher).toHaveBeenCalledTimes(1);
  });

  it("refetches when stale, forced or invalidated, and tells listeners", async () => {
    let n = 0;
    const fetcher = vi.fn(async () => ++n);
    const heard = vi.fn();
    const off = subscribe("/companies?page=1", heard);
    await load("/companies?page=1", fetcher);
    await load("/companies?page=1", fetcher, { now: Date.now() + FRESH_MS + 1 });
    expect(fetcher).toHaveBeenCalledTimes(2);
    await load("/companies?page=1", fetcher, { force: true });
    expect(fetcher).toHaveBeenCalledTimes(3);
    invalidate("/companies");
    await load("/companies?page=1", fetcher);
    expect(fetcher).toHaveBeenCalledTimes(4);
    expect(heard).toHaveBeenCalled();
    off();
  });

  it("keeps the last good data when a refresh fails", async () => {
    await load("/y", async () => "good");
    await expect(load("/y", async () => Promise.reject(new Error("offline")), { force: true })).rejects.toThrow("offline");
    expect(getEntry("/y")).toMatchObject({ data: "good" });
    expect((getEntry("/y")!.error as Error).message).toBe("offline");
  });
});
