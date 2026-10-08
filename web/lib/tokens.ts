import type { Tokens } from "./types";

export interface TokenStore {
  get(): Tokens | null;
  set(tokens: Tokens): void;
  clear(): void;
}

const KEY = "staffmint.tokens";

/** Persists tokens in localStorage (no-op during server rendering). */
export const localStorageTokenStore: TokenStore = {
  get() {
    if (typeof window === "undefined") return null;
    try {
      const raw = window.localStorage.getItem(KEY);
      if (!raw) return null;
      const t = JSON.parse(raw) as Partial<Tokens>;
      return t.accessToken && t.refreshToken
        ? { accessToken: t.accessToken, refreshToken: t.refreshToken }
        : null;
    } catch {
      return null;
    }
  },
  set(tokens) {
    if (typeof window === "undefined") return;
    window.localStorage.setItem(KEY, JSON.stringify(tokens));
  },
  clear() {
    if (typeof window === "undefined") return;
    window.localStorage.removeItem(KEY);
  },
};

/** In-memory store (tests, SSR). */
export function memoryTokenStore(initial: Tokens | null = null): TokenStore {
  let current = initial;
  return {
    get: () => current,
    set: (t) => {
      current = t;
    },
    clear: () => {
      current = null;
    },
  };
}

const DEVICE_KEY = "staffmint.deviceId";

/** Stable per-browser device id sent with OTP verify. */
export function getDeviceId(): string {
  if (typeof window === "undefined") return "web-ssr";
  let id = window.localStorage.getItem(DEVICE_KEY);
  if (!id) {
    const rand =
      typeof crypto !== "undefined" && "randomUUID" in crypto
        ? crypto.randomUUID()
        : `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;
    id = `web-${rand}`;
    window.localStorage.setItem(DEVICE_KEY, id);
  }
  return id;
}
