"use client";

import Link from "next/link";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { Suspense, useEffect, useState } from "react";
import { Alert, Badge, Card, Chips, Empty, Input, ListSkeleton, LoadMore, PageHeader } from "@/components/ui";
import { qs } from "@/lib/api";
import { STATUS_LABEL, STATUS_TONE, ago, daysUntil, phone } from "@/lib/format";
import type { BusinessRow, BusinessStatus } from "@/lib/types";
import { useDebounced } from "@/lib/useDebounced";
import { usePaged } from "@/lib/usePaged";

type Filter = "" | BusinessStatus;
const FILTERS: { value: Filter; label: string }[] = [
  { value: "", label: "All" },
  { value: "trial", label: "Trial" },
  { value: "paid", label: "Paid" },
  { value: "past_due", label: "Payment due" },
  { value: "free", label: "Free" },
  { value: "billed_with", label: "On another bill" },
  { value: "closed", label: "Closed" },
];

function planLine(b: BusinessRow) {
  if (b.status === "trial" && b.trialEndsAt) {
    const d = daysUntil(b.trialEndsAt);
    return `${b.planCode} trial · ${d === 1 ? "last day" : `${d} days left`}`;
  }
  if (b.status === "paid" || b.status === "past_due") return b.planCode;
  return STATUS_LABEL[b.status];
}

function BusinessList() {
  const params = useSearchParams();
  const router = useRouter();
  const pathname = usePathname();
  const [search, setSearch] = useState(params.get("q") ?? "");
  const status = (params.get("status") ?? "") as Filter;
  const q = useDebounced(search.trim(), 300);

  // Keep the search in the URL so Back and shared links land on the same list.
  useEffect(() => {
    const next = qs({ q, status });
    if (next !== (params.toString() ? `?${params.toString()}` : "")) router.replace(`${pathname}${next}`, { scroll: false });
  }, [q, status, params, pathname, router]);

  const { rows, total, error, loadingMore, more, reload } = usePaged<BusinessRow>(`/admin/companies${qs({ search: q, status })}`);

  return (
    <div className="space-y-3">
      <PageHeader title="Businesses" subtitle={rows ? `${total.toLocaleString("en-IN")} found` : " "} />
      <Input type="search" inputMode="search" placeholder="Search name or owner phone" value={search} onChange={(e) => setSearch(e.target.value)} aria-label="Search businesses" />
      <Chips value={status} options={FILTERS} onChange={(v) => router.replace(`${pathname}${qs({ q, status: v })}`, { scroll: false })} />
      {error && <Alert onRetry={() => void reload()}>{error}</Alert>}
      <Card padded={false}>
        {!rows ? (
          <ListSkeleton />
        ) : rows.length === 0 ? (
          <Empty>No businesses match.</Empty>
        ) : (
          <>
            <ul className="divide-y divide-slate-100">
              {rows.map((b) => (
                <li key={b.id}>
                  <Link href={`/businesses/${b.id}`} className="flex items-center gap-3 px-4 py-3 transition-colors hover:bg-slate-50 active:bg-slate-100">
                    <span aria-hidden className="grid h-10 w-10 shrink-0 place-items-center rounded-xl bg-mint-50 text-sm font-semibold text-mint-700">
                      {b.name.trim().charAt(0).toUpperCase() || "?"}
                    </span>
                    <span className="min-w-0 flex-1">
                      <span className="flex items-center gap-2">
                        <span className="truncate font-medium text-slate-900">{b.name}</span>
                        <Badge tone={STATUS_TONE[b.status]}>{STATUS_LABEL[b.status]}</Badge>
                      </span>
                      <span className="mt-0.5 block truncate text-xs text-slate-500">
                        {planLine(b)} · {b.staffCount} staff · {b.owner ? phone(b.owner.phone) : "no owner"}
                      </span>
                    </span>
                    <span className="hidden shrink-0 text-xs text-slate-400 sm:block">{ago(b.createdAt)}</span>
                    <span aria-hidden className="text-slate-300">
                      ›
                    </span>
                  </Link>
                </li>
              ))}
            </ul>
            <LoadMore shown={rows.length} total={total} loading={loadingMore} onMore={() => void more()} />
          </>
        )}
      </Card>
    </div>
  );
}

export default function BusinessesPage() {
  return (
    <Suspense>
      <BusinessList />
    </Suspense>
  );
}
