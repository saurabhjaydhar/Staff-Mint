"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { errorMessage } from "@/lib/api";

interface AsyncState<T> {
  data: T | undefined;
  error: unknown;
  /** key#version the current data/error belongs to */
  forKey: string | null;
}

/**
 * Load data for a string `key` (encode the inputs in it, e.g. `employees:${status}`).
 * Pass `null` as key to skip loading. Keeps previous data while reloading.
 */
export function useAsync<T>(fn: () => Promise<T>, key: string | null) {
  const [version, setVersion] = useState(0);
  const [state, setState] = useState<AsyncState<T>>({ data: undefined, error: null, forKey: null });
  const fnRef = useRef(fn);

  useEffect(() => {
    fnRef.current = fn;
  });

  const fullKey = key === null ? null : `${key}#${version}`;

  useEffect(() => {
    if (fullKey === null) return;
    let cancelled = false;
    fnRef.current().then(
      (data) => {
        if (!cancelled) setState({ data, error: null, forKey: fullKey });
      },
      (error: unknown) => {
        if (!cancelled) setState((s) => ({ data: s.data, error, forKey: fullKey }));
      },
    );
    return () => {
      cancelled = true;
    };
  }, [fullKey]);

  const reload = useCallback(() => setVersion((v) => v + 1), []);
  const setData = useCallback((updater: T | ((prev: T | undefined) => T)) => {
    setState((s) => ({
      ...s,
      data: typeof updater === "function" ? (updater as (p: T | undefined) => T)(s.data) : updater,
    }));
  }, []);

  const loading = fullKey !== null && state.forKey !== fullKey;
  return {
    data: state.data,
    error: loading ? null : state.error,
    errorText: !loading && state.error ? errorMessage(state.error) : null,
    loading,
    reload,
    setData,
  };
}

export type ActionResult<R> = { ok: true; value: R } | { ok: false; error: unknown };

/** Run mutations with a busy key + error message. */
export function useAction() {
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const run = useCallback(async <R,>(key: string, fn: () => Promise<R>): Promise<ActionResult<R>> => {
    setBusy(key);
    setError(null);
    try {
      return { ok: true, value: await fn() };
    } catch (e) {
      setError(errorMessage(e));
      return { ok: false, error: e };
    } finally {
      setBusy(null);
    }
  }, []);

  return { busy, error, setError, run };
}

/** Debounce a value (e.g. a search box) before using it as a request key. */
export function useDebounced<T>(value: T, ms = 300): T {
  const [v, setV] = useState(value);
  useEffect(() => {
    const id = setTimeout(() => setV(value), ms);
    return () => clearTimeout(id);
  }, [value, ms]);
  return v;
}
