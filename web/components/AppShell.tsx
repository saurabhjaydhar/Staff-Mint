"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useEffect, useState, type ReactNode } from "react";
import { api, errorMessage } from "@/lib/api";
import { saveBlob } from "@/lib/download";
import { canAccess, canExport, homeFor, navFor } from "@/lib/roles";
import type { Role } from "@/lib/types";
import type { DictKey } from "@/lib/i18n";
import { initials } from "@/lib/profile";
import { useAuth, useI18n, useToast } from "./providers";

const ROLE_KEY: Record<string, DictKey> = { owner: "role_owner", manager: "role_manager", ca: "role_ca", employee: "role_employee" };
import { Alert, Button, Loading, cx } from "./ui";

export function Logo({ className }: { className?: string }) {
  return (
    <div className={cx("flex items-center gap-2", className)}>
      <span className="grid h-8 w-8 place-items-center rounded-lg bg-mint-500 text-lg font-bold text-white">₹</span>
      <span className="text-lg font-semibold tracking-tight">
        Staff<span className="text-mint-600">Mint</span>
      </span>
    </div>
  );
}

export function LanguageToggle({ className }: { className?: string }) {
  const { lang, setLang } = useI18n();
  return (
    <div className={cx("inline-flex rounded-lg bg-slate-100 p-0.5 text-xs", className)} role="group" aria-label="Language">
      {(["en", "hi"] as const).map((l) => (
        <button
          key={l}
          type="button"
          onClick={() => setLang(l)}
          className={cx("rounded-md px-2 py-1 font-medium", lang === l ? "bg-white text-mint-700 shadow-sm" : "text-slate-600")}
        >
          {l === "en" ? "English" : "हिंदी"}
        </button>
      ))}
    </div>
  );
}

export function ExportButton({ variant = "secondary", className }: { variant?: "secondary" | "ghost"; className?: string }) {
  const { t } = useI18n();
  const toast = useToast();
  const [busy, setBusy] = useState(false);
  return (
    <Button
      variant={variant}
      size="sm"
      loading={busy}
      className={className}
      onClick={async () => {
        setBusy(true);
        try {
          const { blob, filename } = await api.download("/export", undefined, "staffmint-export.zip");
          saveBlob(blob, filename);
        } catch (e) {
          toast(errorMessage(e), "red");
        } finally {
          setBusy(false);
        }
      }}
    >
      ⇩ {t("export_all")}
    </Button>
  );
}

/** Current user's role (only valid inside the app shell). */
export function useRole(): { role: Role; readOnly: boolean } {
  const { me } = useAuth();
  const role = me?.user.role ?? "owner";
  return { role, readOnly: role === "ca" };
}

function FullScreen({ children }: { children: ReactNode }) {
  return <div className="flex min-h-screen flex-col items-center justify-center gap-4 p-6">{children}</div>;
}

export function AppShell({ children }: { children: ReactNode }) {
  const { status, me, error, refreshMe, logout } = useAuth();
  const { t } = useI18n();
  const router = useRouter();
  const pathname = usePathname();
  const [menuOpen, setMenuOpen] = useState(false);

  const role = me?.user.role;
  const needsSetup = status === "authenticated" && role === "owner" && !me?.company;

  useEffect(() => {
    if (status === "anonymous" || needsSetup) router.replace("/login");
  }, [status, needsSetup, router]);

  if (status === "loading" || status === "anonymous" || needsSetup) {
    return (
      <FullScreen>
        <Logo />
        <Loading label={t("loading")} />
      </FullScreen>
    );
  }
  if (status === "error" || !me || !role) {
    return (
      <FullScreen>
        <Logo />
        <Alert onRetry={() => void refreshMe()}>{error || "Could not load your account."}</Alert>
      </FullScreen>
    );
  }
  if (role === "employee") {
    return (
      <FullScreen>
        <Logo />
        <div className="max-w-md rounded-xl bg-white p-6 text-center shadow-sm ring-1 ring-slate-200">
          <h1 className="text-xl font-semibold">{t("employee_use_app")}</h1>
          <p className="mt-2 text-sm text-slate-600">{t("employee_use_app_body")}</p>
          <div className="mt-5 flex justify-center gap-2">
            <LanguageToggle />
            <Button variant="secondary" size="sm" onClick={() => void logout()}>
              {t("logout")}
            </Button>
          </div>
        </div>
      </FullScreen>
    );
  }

  const items = navFor(role);
  const allowed = canAccess(role, pathname);

  const nav = (
    <nav className="flex flex-1 flex-col gap-0.5">
      {items.map((item) => {
        const active = item.href === "/" ? pathname === "/" : pathname === item.href || pathname.startsWith(item.href + "/");
        return (
          <Link
            key={item.href}
            href={item.href}
            onClick={() => setMenuOpen(false)}
            className={cx(
              "flex items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium transition-colors",
              active ? "bg-mint-50 text-mint-700" : "text-slate-600 hover:bg-slate-100 hover:text-slate-900",
            )}
          >
            <span className="w-4 text-center text-base leading-none" aria-hidden>
              {item.icon}
            </span>
            {t(item.label)}
          </Link>
        );
      })}
    </nav>
  );

  const sidebar = (
    <div className="flex h-full flex-col gap-4 p-4">
      <Logo />
      <Link
        href="/profile"
        onClick={() => setMenuOpen(false)}
        title={t("nav_profile")}
        className={cx(
          "flex items-center gap-3 rounded-xl px-2.5 py-2 ring-1 transition-colors",
          pathname === "/profile" ? "bg-mint-50 ring-mint-200" : "bg-slate-50 ring-transparent hover:bg-slate-100",
        )}
      >
        <span className="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-mint-500 text-sm font-semibold text-white">{initials(me.user.name || me.user.phone)}</span>
        <span className="min-w-0 flex-1 text-xs text-slate-600">
          <span className="block truncate text-sm font-medium text-slate-900">{me.user.name || me.user.phone}</span>
          <span className="block truncate">{me.company ? `${me.company.name} · ` : ""}{t(ROLE_KEY[role] ?? "role_owner")}</span>
        </span>
        <span className="text-slate-400" aria-hidden>
          ›
        </span>
      </Link>
      {nav}
      <div className="space-y-2 border-t border-slate-100 pt-3">
        {canExport(role) && <ExportButton variant="ghost" className="w-full justify-start" />}
        <LanguageToggle />
        <Button variant="ghost" size="sm" className="w-full justify-start" onClick={() => void logout()}>
          ⎋ {t("logout")}
        </Button>
      </div>
    </div>
  );

  return (
    <div className="flex min-h-screen">
      <aside className="sticky top-0 hidden h-screen w-60 shrink-0 border-r border-slate-200 bg-white lg:block">{sidebar}</aside>
      {menuOpen && (
        <div className="fixed inset-0 z-40 bg-slate-900/40 lg:hidden" onClick={() => setMenuOpen(false)}>
          <aside className="h-full w-64 bg-white" onClick={(e) => e.stopPropagation()}>
            {sidebar}
          </aside>
        </div>
      )}
      <div className="flex min-w-0 flex-1 flex-col">
        <header className="flex items-center justify-between border-b border-slate-200 bg-white px-4 py-2 lg:hidden">
          <Logo />
          <Button variant="ghost" size="sm" onClick={() => setMenuOpen(true)} aria-label="Open menu">
            ☰
          </Button>
        </header>
        <main className="mx-auto w-full max-w-7xl flex-1 p-4 md:p-6">
          {allowed ? (
            children
          ) : (
            <div className="rounded-xl bg-white p-6 text-center shadow-sm ring-1 ring-slate-200">
              <p className="text-slate-700">You don&apos;t have access to this page.</p>
              <Link href={homeFor(role)} className="mt-3 inline-block text-sm font-medium text-mint-700 underline">
                Go to {t(items[0]?.label ?? "nav_dashboard")}
              </Link>
            </div>
          )}
        </main>
      </div>
    </div>
  );
}
