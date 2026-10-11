"use client";

import { useCallback, useEffect, useSyncExternalStore } from "react";
import { api, errorText } from "./api";
import { getEntry, load, subscribe } from "./cache";

/**
 * GET an admin API path with the shared cache. Pass null to skip.
 * Returns cached data immediately (if any) and refreshes when stale or when the tab regains focus.
 */
export function useApi<T>(path: string | null) {
  const sub = useCallback((fn: () => void) => (path ? subscribe(path, fn) : () => undefined), [path]);
  const snap = useCallback(() => (path ? getEntry(path) : undefined), [path]);
  const entry = useSyncExternalStore(sub, snap, () => undefined);

  const reload = useCallback(
    (force = true) => {
      if (!path) return Promise.resolve(undefined as T | undefined);
      return load<T>(path, () => api.get<T>(path), { force }).catch(() => undefined);
    },
    [path],
  );

  useEffect(() => {
    if (!path) return;
    void reload(false);
    const onFocus = () => {
      if (document.visibilityState === "visible") void reload(false);
    };
    document.addEventListener("visibilitychange", onFocus);
    return () => document.removeEventListener("visibilitychange", onFocus);
  }, [path, reload]);

  return {
    data: entry?.data as T | undefined,
    error: entry?.error ? errorText(entry.error) : null,
    loading: !!entry?.promise,
    reload,
  };
}
