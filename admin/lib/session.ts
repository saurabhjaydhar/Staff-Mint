// Admin session token: kept on this device until it expires (12 h) or the admin signs out.

import type { Admin } from "./types";

const KEY = "sm.admin.session";

export interface Session {
  token: string;
  expiresAt: number;
  admin: Admin;
}

export function readSession(now = Date.now()): Session | null {
  if (typeof window === "undefined") return null;
  try {
    const raw = window.localStorage.getItem(KEY);
    if (!raw) return null;
    const s = JSON.parse(raw) as Session;
    if (!s.token || !s.expiresAt || s.expiresAt <= now) {
      window.localStorage.removeItem(KEY);
      return null;
    }
    return s;
  } catch {
    return null;
  }
}

export function saveSession(s: Session) {
  window.localStorage.setItem(KEY, JSON.stringify(s));
}

export function clearSession() {
  if (typeof window !== "undefined") window.localStorage.removeItem(KEY);
}
