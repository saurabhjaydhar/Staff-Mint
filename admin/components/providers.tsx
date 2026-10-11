"use client";

import { useRouter } from "next/navigation";
import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from "react";
import { api, setSignedOutHandler } from "@/lib/api";
import { clearCache } from "@/lib/cache";
import { clearSession, readSession, saveSession, type Session } from "@/lib/session";
import type { Admin } from "@/lib/types";
import { cx } from "./ui";

interface AuthValue {
  /** undefined while reading the saved session on first load. */
  session: Session | null | undefined;
  admin: Admin | null;
  canEdit: boolean;
  signIn: (token: string, expiresInSec: number, admin: Admin) => void;
  signOut: () => Promise<void>;
}

const AuthContext = createContext<AuthValue | null>(null);
const ToastContext = createContext<(msg: string, tone?: "mint" | "red") => void>(() => undefined);

export const useAuth = () => {
  const v = useContext(AuthContext);
  if (!v) throw new Error("useAuth must be inside <Providers>");
  return v;
};
export const useToast = () => useContext(ToastContext);

export function Providers({ children }: { children: ReactNode }) {
  const router = useRouter();
  const [session, setSession] = useState<Session | null | undefined>(undefined);
  const [toasts, setToasts] = useState<{ id: number; msg: string; tone: "mint" | "red" }[]>([]);

  useEffect(() => {
    // Read the saved session once on the client (localStorage is not available on the server).
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setSession(readSession());
    setSignedOutHandler(() => {
      clearCache();
      setSession(null);
      router.replace("/login");
    });
    return () => setSignedOutHandler(null);
  }, [router]);

  const signIn = useCallback((token: string, expiresInSec: number, admin: Admin) => {
    const s = { token, expiresAt: Date.now() + expiresInSec * 1000 - 60_000, admin };
    saveSession(s);
    setSession(s);
  }, []);

  const signOut = useCallback(async () => {
    await api.post("/admin/logout").catch(() => undefined);
    clearSession();
    clearCache();
    setSession(null);
    router.replace("/login");
  }, [router]);

  const toast = useCallback((msg: string, tone: "mint" | "red" = "mint") => {
    const id = Date.now() + Math.random();
    setToasts((t) => [...t, { id, msg, tone }]);
    setTimeout(() => setToasts((t) => t.filter((x) => x.id !== id)), 3500);
  }, []);

  const value = useMemo<AuthValue>(
    () => ({ session, admin: session?.admin ?? null, canEdit: session?.admin.role === "admin", signIn, signOut }),
    [session, signIn, signOut],
  );

  return (
    <AuthContext.Provider value={value}>
      <ToastContext.Provider value={toast}>
        {children}
        <div aria-live="polite" className="pointer-events-none fixed inset-x-0 bottom-24 z-[60] flex flex-col items-center gap-2 px-4 md:bottom-6 md:items-end">
          {toasts.map((t) => (
            <div key={t.id} className={cx("pointer-events-auto max-w-sm rounded-xl px-4 py-2.5 text-sm text-white shadow-lg", t.tone === "red" ? "bg-red-600" : "bg-slate-900")}>
              {t.msg}
            </div>
          ))}
        </div>
      </ToastContext.Provider>
    </AuthContext.Provider>
  );
}
