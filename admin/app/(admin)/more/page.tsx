"use client";

import Link from "next/link";
import { useAuth } from "@/components/providers";
import { Badge, Button, PageHeader } from "@/components/ui";
import { NAV } from "@/lib/nav";

/** Phones: everything that isn't a bottom tab. */
export default function MorePage() {
  const { admin, signOut } = useAuth();
  return (
    <div className="space-y-4">
      <PageHeader title="More" />
      <div className="flex items-center gap-3 rounded-2xl bg-white p-4 ring-1 ring-slate-200">
        <span className="grid h-11 w-11 place-items-center rounded-full bg-mint-100 font-semibold text-mint-800">{(admin?.name || admin?.email || "?").charAt(0).toUpperCase()}</span>
        <div className="min-w-0 flex-1">
          <p className="truncate font-medium">{admin?.name || admin?.email}</p>
          <p className="truncate text-sm text-slate-500">{admin?.email}</p>
        </div>
        <Badge tone={admin?.role === "admin" ? "mint" : "slate"}>{admin?.role === "admin" ? "Admin" : "View only"}</Badge>
      </div>
      <ul className="divide-y divide-slate-100 overflow-hidden rounded-2xl bg-white ring-1 ring-slate-200">
        {NAV.filter((n) => !n.tab).map((n) => (
          <li key={n.href}>
            <Link href={n.href} className="flex items-center gap-3 px-4 py-4 text-sm font-medium active:bg-slate-50">
              <span aria-hidden className="w-6 text-center text-lg text-slate-500">
                {n.icon}
              </span>
              <span className="flex-1">{n.label}</span>
              <span aria-hidden className="text-slate-300">
                ›
              </span>
            </Link>
          </li>
        ))}
      </ul>
      <Button variant="secondary" className="w-full" onClick={() => void signOut()}>
        Sign out
      </Button>
    </div>
  );
}
