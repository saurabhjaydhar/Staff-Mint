"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useEffect, type ReactNode } from "react";
import { NAV, TABS, isActive } from "@/lib/nav";
import { useAuth } from "./providers";
import { Badge, Spinner, cx } from "./ui";

export function Logo() {
  return (
    <span className="flex items-center gap-2 font-semibold text-slate-900">
      <span className="grid h-8 w-8 place-items-center rounded-lg bg-mint-500 text-sm font-bold text-white">SM</span>
      <span>
        StaffMint <span className="text-mint-700">Admin</span>
      </span>
    </span>
  );
}

/** Signed-in frame: guards the session; bottom tabs on phones, sidebar on desktop. */
export function AdminShell({ children }: { children: ReactNode }) {
  const { session, admin } = useAuth();
  const pathname = usePathname();
  const router = useRouter();

  useEffect(() => {
    if (session === null) router.replace(`/login?next=${encodeURIComponent(pathname)}`);
  }, [session, router, pathname]);

  if (!session) {
    return (
      <div className="grid min-h-dvh place-items-center text-mint-600">
        <Spinner className="h-7 w-7" />
      </div>
    );
  }

  return (
    <div className="min-h-dvh md:flex">
      <aside className="sticky top-0 hidden h-dvh w-64 shrink-0 flex-col border-r border-slate-200 bg-white md:flex">
        <div className="px-5 py-5">
          <Logo />
        </div>
        <nav className="flex-1 space-y-0.5 overflow-y-auto px-3" aria-label="Main">
          {NAV.map((n) => (
            <Link
              key={n.href}
              href={n.href}
              aria-current={isActive(n.href, pathname) ? "page" : undefined}
              className={cx(
                "flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-medium transition-colors",
                isActive(n.href, pathname) ? "bg-mint-50 text-mint-800" : "text-slate-600 hover:bg-slate-50 hover:text-slate-900",
              )}
            >
              <span aria-hidden className="w-5 text-center text-base">
                {n.icon}
              </span>
              {n.label}
            </Link>
          ))}
        </nav>
        <div className="border-t border-slate-100 px-5 py-4 text-xs text-slate-500">
          <p className="truncate font-medium text-slate-700">{admin?.name || admin?.email}</p>
          <p className="mt-1 flex items-center gap-2">
            <span className="truncate">{admin?.email}</span>
            {admin?.role === "viewer" && <Badge>View only</Badge>}
          </p>
        </div>
      </aside>

      <main className="pb-tabbar mx-auto w-full max-w-5xl flex-1 px-4 md:px-8 md:pt-6 md:pb-10">{children}</main>

      <nav aria-label="Main" className="safe-bottom fixed inset-x-0 bottom-0 z-30 border-t border-slate-200 bg-white/95 backdrop-blur md:hidden">
        <ul className="mx-auto grid max-w-md grid-cols-4">
          {TABS.map((t) => {
            const active = isActive(t.href, pathname);
            return (
              <li key={t.href}>
                <Link
                  href={t.href}
                  aria-current={active ? "page" : undefined}
                  className={cx("flex h-16 flex-col items-center justify-center gap-0.5 text-[11px] font-medium", active ? "text-mint-700" : "text-slate-500")}
                >
                  <span aria-hidden className={cx("grid h-7 w-12 place-items-center rounded-full text-lg leading-none", active && "bg-mint-50")}>
                    {t.icon}
                  </span>
                  {t.label}
                </Link>
              </li>
            );
          })}
        </ul>
      </nav>
    </div>
  );
}
