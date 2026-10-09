"use client";

import Link from "next/link";
import { useI18n, useToast } from "@/components/providers";
import { Alert, Badge, Button, Card, EmptyState, Loading, PageHeader, Stat } from "@/components/ui";
import { useAction, useAsync } from "@/hooks/useAsync";
import { api } from "@/lib/api";
import { formatDate, formatTime } from "@/lib/format";
import type { DashboardToday } from "@/lib/types";

const FLAG_LABELS: Record<string, string> = {
  late_sync: "Synced late",
  device_time_drift: "Phone time wrong",
  mock_location: "Fake GPS",
  low_accuracy: "Weak GPS",
  outside_geofence: "Outside shop area",
  phone_lock_failed: "Phone lock didn't open",
  no_phone_lock: "No phone lock",
};

export default function DashboardPage() {
  const { t } = useI18n();
  const toast = useToast();
  const { data, loading, errorText, reload } = useAsync(() => api.get<DashboardToday>("/dashboard/today"), "dashboard");
  const action = useAction();

  async function decideLeave(id: string, decision: "approved" | "rejected") {
    const res = await action.run(`leave:${id}`, () => api.post(`/leaves/${id}/decision`, { decision }));
    if (res.ok) {
      toast(decision === "approved" ? "Leave approved" : "Leave rejected");
      reload();
    }
  }
  async function decidePunch(attendanceId: string, punchId: string, approve: boolean) {
    const res = await action.run(`punch:${punchId}`, () =>
      api.post(`/attendance/${attendanceId}/punches/${punchId}/decision`, { approve }),
    );
    if (res.ok) {
      toast(approve ? "Punch approved" : "Punch rejected");
      reload();
    }
  }

  if (!data && loading) return <Loading label={t("loading")} />;
  if (!data) return <Alert onRetry={reload}>{errorText || "Could not load dashboard"}</Alert>;

  const c = data.counts;
  const na = data.needsAction;
  const nothing = na.leaveRequests.length + na.punchApprovals.length + na.flags.length === 0;
  const nearLimit = data.plan.staffLimit > 0 && data.plan.staffCount >= data.plan.staffLimit;

  return (
    <div className="space-y-6">
      <PageHeader
        title={`${t("dash_today")} · ${formatDate(data.date)}`}
        actions={
          <Button variant="secondary" size="sm" onClick={reload} loading={loading}>
            ↻ Refresh
          </Button>
        }
      />
      {errorText && <Alert onRetry={reload}>{errorText}</Alert>}
      {action.error && <Alert>{action.error}</Alert>}

      <div className="grid grid-cols-2 gap-3 md:grid-cols-4 xl:grid-cols-7">
        <Stat label={t("total")} value={c.total} />
        <Stat label={t("dash_present")} value={c.present} tone="mint" />
        <Stat label={t("dash_late")} value={c.late} tone="amber" />
        <Stat label={t("dash_absent")} value={c.absent} tone="red" />
        <Stat label={t("dash_on_leave")} value={c.onLeave} tone="sky" />
        <Stat label={t("dash_checked_in")} value={c.checkedIn} tone="mint" />
        <Stat label={t("dash_not_marked")} value={c.notMarked} />
      </div>

      <div className="flex flex-wrap items-center gap-2 text-sm text-slate-600">
        {t("dash_staff_plan")}:{" "}
        <Badge tone={nearLimit ? "amber" : "mint"}>
          {data.plan.staffCount} / {data.plan.staffLimit}
        </Badge>
        {nearLimit && (
          <Link href="/billing" className="font-medium text-mint-700 underline">
            Upgrade plan
          </Link>
        )}
      </div>

      <Card title={t("dash_needs_action")} padded={false}>
        {nothing ? (
          <EmptyState>{t("dash_all_clear")}</EmptyState>
        ) : (
          <div className="divide-y divide-slate-100">
            {na.leaveRequests.length > 0 && (
              <div className="p-4">
                <h3 className="mb-2 text-sm font-semibold text-slate-700">{t("dash_leave_requests")}</h3>
                <ul className="space-y-2">
                  {na.leaveRequests.map((l) => (
                    <li key={l.id} className="flex flex-wrap items-center justify-between gap-2 rounded-lg bg-slate-50 px-3 py-2">
                      <div className="text-sm">
                        <span className="font-medium">{l.employeeName}</span> · {l.type} leave · {formatDate(l.from)}
                        {l.to !== l.from && <> → {formatDate(l.to)}</>} ({l.halfDay ? "half day" : `${l.days} day${l.days === 1 ? "" : "s"}`})
                        {l.reason && <div className="text-xs text-slate-500">“{l.reason}”</div>}
                      </div>
                      <div className="flex gap-2">
                        <Button size="sm" loading={action.busy === `leave:${l.id}`} onClick={() => decideLeave(l.id, "approved")}>
                          {t("approve")}
                        </Button>
                        <Button size="sm" variant="secondary" disabled={!!action.busy} onClick={() => decideLeave(l.id, "rejected")}>
                          {t("reject")}
                        </Button>
                      </div>
                    </li>
                  ))}
                </ul>
              </div>
            )}
            {na.punchApprovals.length > 0 && (
              <div className="p-4">
                <h3 className="mb-2 text-sm font-semibold text-slate-700">{t("dash_punch_approvals")}</h3>
                <ul className="space-y-2">
                  {na.punchApprovals.map((p) => (
                    <li key={p.punch.id} className="flex flex-wrap items-center justify-between gap-2 rounded-lg bg-slate-50 px-3 py-2">
                      <div className="text-sm">
                        <span className="font-medium">{p.employeeName}</span> · check-{p.punch.type} at {formatTime(p.punch.serverTime)}
                        {p.punch.distanceM != null && <> · {Math.round(p.punch.distanceM)} m away</>}
                        <div className="mt-1 flex flex-wrap gap-1">
                          {p.punch.flags.map((f) => (
                            <Badge key={f} tone="amber">
                              {FLAG_LABELS[f] ?? f}
                            </Badge>
                          ))}
                        </div>
                      </div>
                      <div className="flex items-center gap-2">
                        {p.punch.selfieUrl && (
                          <a href={p.punch.selfieUrl} target="_blank" rel="noreferrer" className="text-xs text-mint-700 underline">
                            Selfie
                          </a>
                        )}
                        <Button
                          size="sm"
                          loading={action.busy === `punch:${p.punch.id}`}
                          onClick={() => decidePunch(p.attendanceId, p.punch.id, true)}
                        >
                          {t("approve")}
                        </Button>
                        <Button size="sm" variant="secondary" disabled={!!action.busy} onClick={() => decidePunch(p.attendanceId, p.punch.id, false)}>
                          {t("reject")}
                        </Button>
                      </div>
                    </li>
                  ))}
                </ul>
              </div>
            )}
            {na.flags.length > 0 && (
              <div className="p-4">
                <h3 className="mb-2 text-sm font-semibold text-slate-700">{t("dash_flags")}</h3>
                <ul className="space-y-1 text-sm">
                  {na.flags.map((f, i) => (
                    <li key={`${f.employeeName}-${f.date}-${i}`} className="flex flex-wrap items-center gap-2">
                      <span className="font-medium">{f.employeeName}</span>
                      <span className="text-slate-500">{formatDate(f.date)}</span>
                      {f.flags.map((x) => (
                        <Badge key={x} tone="amber">
                          {FLAG_LABELS[x] ?? x}
                        </Badge>
                      ))}
                    </li>
                  ))}
                </ul>
                <Link href="/attendance" className="mt-2 inline-block text-sm font-medium text-mint-700 underline">
                  Open attendance →
                </Link>
              </div>
            )}
          </div>
        )}
      </Card>

      <div className="grid gap-3 sm:grid-cols-3">
        <QuickLink href="/import" title="Import staff from Excel" body="Switch from another app in minutes." />
        <QuickLink href="/payroll" title="Month-end salary" body="Preview, approve and send payslips." />
        <QuickLink href="/reports" title="Download reports" body="Attendance, salary, advances, late list." />
      </div>
    </div>
  );
}

function QuickLink({ href, title, body }: { href: string; title: string; body: string }) {
  return (
    <Link href={href} className="rounded-xl bg-white p-4 shadow-sm ring-1 ring-slate-200 transition hover:ring-mint-300">
      <div className="font-medium text-slate-900">{title}</div>
      <div className="text-sm text-slate-500">{body}</div>
    </Link>
  );
}
