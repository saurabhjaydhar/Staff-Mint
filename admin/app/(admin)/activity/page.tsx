"use client";

import Link from "next/link";
import { Alert, Card, Empty, ListSkeleton, LoadMore, PageHeader } from "@/components/ui";
import { ago } from "@/lib/format";
import type { AdminActionRow } from "@/lib/types";
import { usePaged } from "@/lib/usePaged";

const LABELS: Record<string, string> = {
  "admin.login": "Signed in",
  "admin.create": "Added an admin",
  "admin.update": "Changed an admin",
  "admin.password_change": "Changed their password",
  "company.trial": "Free trial",
  "company.plan": "Changed a plan",
  "plan.update": "Edited plan prices",
  "flag.update": "Changed a feature flag",
  "config.update": "Changed a setting",
  "recovery.approve": "Approved a number recovery",
  "recovery.reject": "Rejected a number recovery",
};

/** Every change made from the admin app or with the admin key. */
export default function ActivityPage() {
  const { rows, total, error, loadingMore, more, reload } = usePaged<AdminActionRow>("/admin/actions", 30);
  return (
    <div className="space-y-3">
      <PageHeader title="Activity log" subtitle="Who changed what" back="/more" />
      {error && <Alert onRetry={() => void reload()}>{error}</Alert>}
      <Card padded={false}>
        {!rows ? (
          <ListSkeleton />
        ) : rows.length === 0 ? (
          <Empty>No activity yet.</Empty>
        ) : (
          <>
            <ul className="divide-y divide-slate-100">
              {rows.map((a) => (
                <li key={a.id} className="px-4 py-3 text-sm">
                  <p>
                    <span className="font-medium">{LABELS[a.action] ?? a.action}</span>
                    {a.target && <span className="text-slate-600"> · {a.target}</span>}
                  </p>
                  <p className="mt-0.5 text-xs text-slate-500">
                    {a.actor} · {ago(a.createdAt)}
                    {a.companyId && (
                      <>
                        {" · "}
                        <Link href={`/businesses/${a.companyId}`} className="underline">
                          business
                        </Link>
                      </>
                    )}
                  </p>
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
