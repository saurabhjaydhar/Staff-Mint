// Tiny stale-while-revalidate cache: screens show the last data instantly when you come
// back to them, then refresh in the background. Same request in flight is shared.

type Entry = { data?: unknown; error?: unknown; at: number; promise?: Promise<unknown> };

const store = new Map<string, Entry>();
const listeners = new Map<string, Set<() => void>>();

export const FRESH_MS = 15_000;

export function getEntry(key: string): Entry | undefined {
  return store.get(key);
}

function emit(key: string) {
  listeners.get(key)?.forEach((fn) => fn());
}

export function subscribe(key: string, fn: () => void): () => void {
  let set = listeners.get(key);
  if (!set) listeners.set(key, (set = new Set()));
  set.add(fn);
  return () => {
    set!.delete(fn);
    if (!set!.size) listeners.delete(key);
  };
}

/** Fetch unless fresh (or forced); concurrent callers share one request. */
export function load<T>(key: string, fetcher: () => Promise<T>, opts: { force?: boolean; now?: number } = {}): Promise<T> {
  const now = opts.now ?? Date.now();
  const e = store.get(key);
  if (e?.promise) return e.promise as Promise<T>;
  if (!opts.force && e && e.data !== undefined && now - e.at < FRESH_MS) return Promise.resolve(e.data as T);
  const promise = fetcher().then(
    (data) => {
      store.set(key, { data, at: Date.now() });
      emit(key);
      return data;
    },
    (error) => {
      store.set(key, { data: e?.data, error, at: e?.at ?? 0 });
      emit(key);
      throw error;
    },
  );
  store.set(key, { ...(e ?? { at: 0 }), promise });
  emit(key);
  return promise;
}

/** Mark every key starting with one of these prefixes as stale (after a change). */
export function invalidate(...prefixes: string[]) {
  for (const [key, e] of store) {
    if (prefixes.some((p) => key.startsWith(p))) {
      store.set(key, { ...e, at: 0 });
      emit(key);
    }
  }
}

export function clearCache() {
  store.clear();
}
