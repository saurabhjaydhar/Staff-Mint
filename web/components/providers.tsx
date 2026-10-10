"use client";

import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, useSyncExternalStore, type ReactNode } from "react";
import { useRouter } from "next/navigation";
import { api, isApiError, setApiLanguage } from "@/lib/api";
import { translate, type DictKey } from "@/lib/i18n";
import { getDeviceId } from "@/lib/tokens";
import { homeFor } from "@/lib/roles";
import type { AccountChange, Lang, MeResult, SwitchResult, Tokens } from "@/lib/types";

// ---------------- i18n ----------------
const LANG_KEY = "staffmint.lang";
const LANG_EVENT = "staffmint:lang";

function readLang(): Lang {
  try {
    return window.localStorage.getItem(LANG_KEY) === "hi" ? "hi" : "en";
  } catch {
    return "en";
  }
}
function subscribeLang(cb: () => void) {
  window.addEventListener("storage", cb);
  window.addEventListener(LANG_EVENT, cb);
  return () => {
    window.removeEventListener("storage", cb);
    window.removeEventListener(LANG_EVENT, cb);
  };
}

interface I18nCtx {
  lang: Lang;
  setLang: (l: Lang) => void;
  t: (key: DictKey) => string;
}
const I18nContext = createContext<I18nCtx | null>(null);

function I18nProvider({ children }: { children: ReactNode }) {
  const lang = useSyncExternalStore(subscribeLang, readLang, () => "en" as Lang);
  setApiLanguage(lang);
  useEffect(() => {
    document.documentElement.lang = lang;
  }, [lang]);
  const setLang = useCallback((l: Lang) => {
    window.localStorage.setItem(LANG_KEY, l);
    window.dispatchEvent(new Event(LANG_EVENT));
  }, []);
  const value = useMemo<I18nCtx>(() => ({ lang, setLang, t: (k) => translate(lang, k) }), [lang, setLang]);
  return <I18nContext.Provider value={value}>{children}</I18nContext.Provider>;
}

export function useI18n() {
  const ctx = useContext(I18nContext);
  if (!ctx) throw new Error("useI18n must be used inside <Providers>");
  return ctx;
}

// ---------------- toast ----------------
type ToastTone = "mint" | "red" | "slate";
interface ToastItem {
  id: number;
  text: string;
  tone: ToastTone;
}
const ToastContext = createContext<(text: string, tone?: ToastTone) => void>(() => {});

function ToastProvider({ children }: { children: ReactNode }) {
  const [items, setItems] = useState<ToastItem[]>([]);
  const nextId = useRef(1);
  const show = useCallback((text: string, tone: ToastTone = "mint") => {
    const id = nextId.current++;
    setItems((xs) => [...xs, { id, text, tone }]);
    setTimeout(() => setItems((xs) => xs.filter((x) => x.id !== id)), 4000);
  }, []);
  return (
    <ToastContext.Provider value={show}>
      {children}
      <div className="pointer-events-none fixed bottom-4 right-4 z-[60] flex flex-col gap-2">
        {items.map((i) => (
          <div
            key={i.id}
            role="status"
            className={
              "pointer-events-auto max-w-sm rounded-lg px-4 py-2 text-sm text-white shadow-lg " +
              (i.tone === "red" ? "bg-red-600" : i.tone === "slate" ? "bg-slate-800" : "bg-mint-600")
            }
          >
            {i.text}
          </div>
        ))}
      </div>
    </ToastContext.Provider>
  );
}

export function useToast() {
  return useContext(ToastContext);
}

// ---------------- auth ----------------
export type AuthStatus = "loading" | "anonymous" | "authenticated" | "error";

interface AuthCtx {
  status: AuthStatus;
  me: MeResult | null;
  error: string | null;
  /** Store tokens (after OTP verify / company setup) and load /me. */
  signIn: (tokens: Tokens) => Promise<MeResult | null>;
  refreshMe: () => Promise<MeResult | null>;
  /** Open another of this person's businesses in this browser. */
  switchAccount: (membershipId: string) => Promise<MeResult | null>;
  /** F14: leave a business, close/restore one, hide an "access ended" notice. */
  leaveAccount: (membershipId: string) => Promise<MeResult | null>;
  closeBusiness: (confirmName: string) => Promise<MeResult | null>;
  restoreBusiness: (companyId: string) => Promise<MeResult | null>;
  dismissNotice: (membershipId: string) => Promise<void>;
  logout: () => Promise<void>;
}
const AuthContext = createContext<AuthCtx | null>(null);

function AuthProvider({ children }: { children: ReactNode }) {
  const router = useRouter();
  const [status, setStatus] = useState<AuthStatus>("loading");
  const [me, setMe] = useState<MeResult | null>(null);
  const [error, setError] = useState<string | null>(null);

  const refreshMe = useCallback(async (): Promise<MeResult | null> => {
    if (!api.tokens.get()) {
      setMe(null);
      setStatus("anonymous");
      return null;
    }
    try {
      const result = await api.get<MeResult>("/me");
      setMe(result);
      setError(null);
      setStatus("authenticated");
      return result;
    } catch (e) {
      if (isApiError(e) && (e.status === 401 || e.status === 403)) {
        api.tokens.clear();
        setMe(null);
        setStatus("anonymous");
      } else {
        setError(e instanceof Error ? e.message : String(e));
        setStatus("error");
      }
      return null;
    }
  }, []);

  useEffect(() => {
    let active = true;
    Promise.resolve().then(() => {
      if (active) void refreshMe();
    });
    return () => {
      active = false;
    };
  }, [refreshMe]);

  // A token refresh moved this browser to another business (access ended / role changed).
  const [change, setChange] = useState<AccountChange | null>(null);
  useEffect(() => {
    const onChange = (e: Event) => {
      setChange((e as CustomEvent<AccountChange>).detail);
      void refreshMe().then((m) => router.replace(m?.company ? homeFor(m.user.role) : "/login"));
    };
    window.addEventListener("staffmint:account-changed", onChange);
    return () => window.removeEventListener("staffmint:account-changed", onChange);
  }, [refreshMe, router]);

  useEffect(() => {
    const onFailure = () => {
      setMe(null);
      setStatus("anonymous");
      router.replace("/login");
    };
    window.addEventListener("staffmint:auth-failure", onFailure);
    return () => window.removeEventListener("staffmint:auth-failure", onFailure);
  }, [router]);

  const signIn = useCallback(
    async (tokens: Tokens) => {
      api.tokens.set(tokens);
      return refreshMe();
    },
    [refreshMe],
  );

  /** POST an account action that returns a new session for this browser, then reload. */
  const sessionAction = useCallback(
    async (path: string, extra: Record<string, unknown> = {}) => {
      const res = await api.post<SwitchResult>(path, { ...extra, deviceId: getDeviceId(), refreshToken: api.tokens.get()?.refreshToken });
      api.tokens.set({ accessToken: res.accessToken, refreshToken: res.refreshToken });
      return refreshMe();
    },
    [refreshMe],
  );
  const switchAccount = useCallback((membershipId: string) => sessionAction("/auth/switch", { membershipId }), [sessionAction]);
  const leaveAccount = useCallback((membershipId: string) => sessionAction(`/me/accounts/${membershipId}/leave`), [sessionAction]);
  const closeBusiness = useCallback((confirmName: string) => sessionAction("/company/close", { confirmName }), [sessionAction]);
  const restoreBusiness = useCallback((companyId: string) => sessionAction(`/me/businesses/${companyId}/restore`), [sessionAction]);
  const dismissNotice = useCallback(
    async (membershipId: string) => {
      setMe((m) => (m ? { ...m, endedNotices: (m.endedNotices ?? []).filter((n) => n.id !== membershipId) } : m));
      await api.post(`/me/notices/${membershipId}/dismiss`).catch(() => undefined);
    },
    [],
  );

  const logout = useCallback(async () => {
    const t = api.tokens.get();
    if (t) {
      try {
        await api.post("/auth/logout", { refreshToken: t.refreshToken }, { auth: false });
      } catch {
        /* best effort */
      }
    }
    api.tokens.clear();
    setMe(null);
    setStatus("anonymous");
    router.replace("/login");
  }, [router]);

  const value = useMemo<AuthCtx>(
    () => ({ status, me, error, signIn, refreshMe, switchAccount, leaveAccount, closeBusiness, restoreBusiness, dismissNotice, logout }),
    [status, me, error, signIn, refreshMe, switchAccount, leaveAccount, closeBusiness, restoreBusiness, dismissNotice, logout],
  );
  return (
    <AuthContext.Provider value={value}>
      {children}
      {change && <AccountChangeToast change={change} onDone={() => setChange(null)} />}
    </AuthContext.Provider>
  );
}

function AccountChangeToast({ change, onDone }: { change: AccountChange; onDone: () => void }) {
  const { t } = useI18n();
  const toast = useToast();
  useEffect(() => {
    const roleKey = { owner: "role_owner", manager: "role_manager", ca: "role_ca", employee: "role_employee" } as const;
    toast(
      change.kind === "ended"
        ? t("acc_ended").replace("{name}", change.companyName)
        : t("acc_role_changed").replace("{role}", t(roleKey[change.role ?? "employee"])),
      "slate",
    );
    onDone();
  }, [change, onDone, t, toast]);
  return null;
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth must be used inside <Providers>");
  return ctx;
}

export function Providers({ children }: { children: ReactNode }) {
  return (
    <I18nProvider>
      <ToastProvider>
        <AuthProvider>{children}</AuthProvider>
      </ToastProvider>
    </I18nProvider>
  );
}
