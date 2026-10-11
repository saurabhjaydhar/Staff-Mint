"use client";

import Link from "next/link";
import { SignupsChart } from "@/components/SignupsChart";
import { Alert, Card, PageHeader, Skeleton, cx } from "@/components/ui";
import { count, rupees, rupeesShort } from "@/lib/format";
import type { Stats } from "@/lib/types";
import { useApi } from "@/lib/useApi";

function Tile({ label, value, sub, href }: { label: string; value: string; sub?: string; href?: string }) {
  const body = (
    <>
      <p className="text-xs font-medium text-slate-500">{label}</p>
      <p className="mt-1 text-2xl font-semibold text-slate-900 tabular-nums">{value}</p>
      {sub && <p className="mt-0.5 truncate text-xs text-slate-500">{sub}</p>}
    </>
  );
  const cls = "block rounded-2xl bg-white p-4 ring-1 ring-slate-200";
  return href ? (
    <Link href={href} className={cx(cls, "transition-colors hover:ring-mint-300 active:bg-slate-50")}>
      {body}
    </Link>
  ) : (
    <div className={cls}>{body}</div>
  );
}

function NeedsYou({ s }: { s: Stats }) {
  const items = [
    s.pendingRecoveries > 0 && { href: "/recovery", text: `${s.pendingRecoveries} number recovery request${s.pendingRecoveries === 1 ? "" : "s"} to review`, tone: "amber" },
    s.businesses.pastDue > 0 && { href: "/businesses?status=past_due", text: `${s.businesses.pastDue} business${s.businesses.pastDue === 1 ? "" : "es"} with a failed payment`, tone: "red" },
    s.failedMessages > 0 && { href: "/messages?status=failed", text: `${s.failedMessages} message${s.failedMessages === 1 ? "" : "s"} failed this week`, tone: "red" },
    s.trialsEndingSoon > 0 && { href: "/businesses?status=trial", text: `${s.trialsEndingSoon} trial${s.trialsEndingSoon === 1 ? "" : "s"} ending in 3 days`, tone: "sky" },
  ].filter(Boolean) as { href: string; text: string; tone: string }[];
  if (!items.length) return <p className="text-sm text-slate-500">Nothing needs you right now.</p>;
  return (
    <ul className="-my-1 divide-y divide-slate-100">
      {items.map((i) => (
        <li key={i.href}>
          <Link href={i.href} className="flex items-center gap-3 py-3 text-sm">
            <span aria-hidden className={cx("h-2 w-2 shrink-0 rounded-full", i.tone === "red" ? "bg-red-500" : i.tone === "amber" ? "bg-amber-500" : "bg-sky-500")} />
            <span className="flex-1 text-slate-800">{i.text}</span>
            <span aria-hidden className="text-slate-400">›</span>
          </Link>
        </li>
      ))}
    </ul>
  );
}

export default function HomePage() {
  const { data: s, error, reload } = useApi<Stats>("/admin/stats");

  return (
    <div className="space-y-4">
      <PageHeader title="Home" subtitle="StaffMint at a glance" />
      {error && !s && <Alert onRetry={() => void reload()}>{error}</Alert>}

      {!s ? (
        <div className="space-y-4" aria-busy>
          <Skeleton className="h-28 w-full rounded-2xl" />
          <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
            {Array.from({ length: 4 }, (_, i) => (
              <Skeleton key={i} className="h-24 rounded-2xl" />
            ))}
          </div>
        </div>
      ) : (
        <>
          <section className="rounded-2xl bg-white p-5 ring-1 ring-slate-200">
            <p className="text-xs font-medium text-slate-500">Monthly revenue</p>
            <p className="mt-1 text-5xl font-semibold tracking-tight text-slate-900 tabular-nums" title={rupees(s.mrrPaise)}>
              {rupeesShort(s.mrrPaise)}
            </p>
            <p className="mt-1 text-sm text-slate-500">
              from {count(s.businesses.paid)} paying business{s.businesses.paid === 1 ? "" : "es"}
              {Object.keys(s.paidPlans).length > 0 && (
                <> · {Object.entries(s.paidPlans).map(([p, n]) => `${n} ${p}`).join(", ")}</>
              )}
            </p>
          </section>

          <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
            <Tile label="Businesses" value={count(s.businesses.total)} sub={`${count(s.owners)} owners`} href="/businesses" />
            <Tile label="On free trial" value={count(s.businesses.trial)} sub={s.trialsEndingSoon ? `${s.trialsEndingSoon} ending soon` : undefined} href="/businesses?status=trial" />
            <Tile label="On Free plan" value={count(s.businesses.free)} href="/businesses?status=free" />
            <Tile label="Staff (active)" value={count(s.staff)} />
          </div>

          <div className="grid gap-4 md:grid-cols-5">
            <Card title="Needs you" className="md:col-span-2">
              <NeedsYou s={s} />
            </Card>
            <Card title="New businesses, last 30 days" className="md:col-span-3" action={<span className="text-xs text-slate-500 tabular-nums">{s.signups.week} this week</span>}>
              <SignupsChart days={s.signups.perDay} />
            </Card>
          </div>
        </>
      )}
    </div>
  );
}
