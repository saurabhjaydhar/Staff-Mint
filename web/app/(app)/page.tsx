"use client";

import Link from "next/link";
import { useState } from "react";
import { useI18n, useToast } from "@/components/providers";
import { TrialBanner } from "@/components/TrialBanner";
import { Alert, Badge, Button, Card, EmptyState, Loading, PageHeader, Stat } from "@/components/ui";
import { useAction, useAsync } from "@/hooks/useAsync";
import { api } from "@/lib/api";
import { fill } from "@/lib/i18n";
import { formatDate, formatTime } from "@/lib/format";
import type { DictKey } from "@/lib/i18n";
import type { DashboardToday } from "@/lib/types";

const FLAG_LABELS: Record<string, string> = {
  late_sync: "Synced late",
  device_time_drift: "Phone time wrong",
  mock_location: "Fake GPS",
  low_accuracy: "Weak GPS",
  outside_geofence: "Outside shop area",
  phone_lock_failed: "Phone lock didn't open",
  no_phone_lock: "No phone lock",
  face_mismatch: "Face does not match",
  face_unsure: "Face not clear",
  face_no_face: "No face in selfie",
  face_many_faces: "More than one face",
  face_check_failed: "Face check failed",
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
  async function decideDevice(id: string, approve: boolean) {
    const res = await action.run(`device:${id}`, () => api.post(`/device-requests/${id}/${approve ? "approve" : "reject"}`));
    if (res.ok) {
      toast(approve ? "New phone approved" : "Request rejected");
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
  const devices = na.deviceRequests ?? [];
  const nothing = na.leaveRequests.length + na.punchApprovals.length + na.flags.length + devices.length === 0;
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
      <TrialBanner />
      {errorText && <Alert onRetry={reload}>{errorText}</Alert>}
      <p className="text-2xl font-bold" data-testid="at-work">
        {fill(t("at_work"), { n: c.present, total: Math.max(0, c.total - (c.off ?? 0)) })}
      </p>
      {data.setup && <SetupChecklist setup={data.setup} onChanged={reload} />}
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

      <Card title={nothing ? t("dash_needs_action") : needOk(t, na.leaveRequests.length + na.punchApprovals.length + na.flags.length + devices.length)} padded={false}>
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
                        <span className="font-medium">{fill(t("wants_leave"), { name: l.employeeName })}</span> · {l.type} · {formatDate(l.from)}
                        {l.to !== l.from && <> → {formatDate(l.to)}</>} ({l.halfDay ? "half day" : `${l.days} day${l.days === 1 ? "" : "s"}`})
                        {l.reason && <div className="text-xs text-slate-500">“{l.reason}”</div>}
                        {l.balance && (
                          <div className={l.balance.after < 0 ? "text-xs font-medium text-red-600" : "text-xs font-medium text-slate-700"}>
                            {fill(t("leave_effect"), { left: l.balance.left, type: l.type, after: l.balance.after })}
                          </div>
                        )}
                      </div>
                      <div className="flex gap-2">
                        <Button size="sm" loading={action.busy === `leave:${l.id}`} onClick={() => decideLeave(l.id, "approved")}>
                          {t("approve")}
                        </Button>
                        <Button size="sm" variant="secondary" disabled={!!action.busy} onClick={() => decideLeave(l.id, "rejected")}>
                          {t("say_no")}
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
                        <span className="font-medium">
                          {p.punch.distanceM != null && p.punch.insideGeofence === false
                            ? fill(t("checked_in_away"), { name: p.employeeName, m: Math.round(p.punch.distanceM) })
                            : p.employeeName}
                        </span>{" "}
                        · check-{p.punch.type} at {formatTime(p.punch.serverTime)}
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
                          {t("count_it")}
                        </Button>
                        <Button size="sm" variant="secondary" disabled={!!action.busy} onClick={() => decidePunch(p.attendanceId, p.punch.id, false)}>
                          {t("dont_count")}
                        </Button>
                      </div>
                    </li>
                  ))}
                </ul>
              </div>
            )}
            {devices.length > 0 && (
              <div className="p-4">
                <h3 className="mb-2 text-sm font-semibold text-slate-700">{t("acc_device_requests")}</h3>
                <ul className="space-y-2">
                  {devices.map((r) => (
                    <li key={r.id} data-device-request={r.id} className="flex flex-wrap items-center justify-between gap-2 rounded-lg bg-slate-50 px-3 py-2">
                      <div className="text-sm">
                        <span className="font-medium">{r.employeeName}</span>{" "}
                        {t("acc_device_request_body").replace("{device}", r.deviceName ?? t("acc_device_new"))}
                      </div>
                      <div className="flex gap-2">
                        <Button size="sm" loading={action.busy === `device:${r.id}`} onClick={() => decideDevice(r.id, true)}>
                          {t("approve")}
                        </Button>
                        <Button size="sm" variant="secondary" disabled={!!action.busy} onClick={() => decideDevice(r.id, false)}>
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
        <QuickLink href="/payroll" title="Month-end salary" body="Preview, approve and send salary slips." />
        <QuickLink href="/reports" title="Download reports" body="Attendance, salary, advances, late list." />
      </div>
    </div>
  );
}

function needOk(t: (k: DictKey) => string, n: number) {
  return n === 1 ? t("need_ok_one") : fill(t("need_ok_many"), { n });
}

/** "Let's get your shop running · 2 of 5": each step ticks itself; hidden per business. */
function SetupChecklist({ setup, onChanged }: { setup: NonNullable<DashboardToday["setup"]>; onChanged: () => void }) {
  const { t } = useI18n();
  const toast = useToast();
  const action = useAction();
  const key = "sm_setup_hidden";
  const [hidden, setHidden] = useState(() => typeof window !== "undefined" && window.localStorage.getItem(key) === "1");
  if (hidden || setup.done >= setup.total) return null;
  async function remind() {
    const res = await action.run("remind", () => api.post<{ sent: number }>("/employees/remind-invites"));
    if (res.ok) {
      toast(res.value.sent ? fill(t("remind_sent"), { n: res.value.sent }) : t("remind_none"));
      onChanged();
    }
  }
  const steps: { done: boolean; label: string; href?: string; onClick?: () => void; cta?: string }[] = [
    { done: true, label: t("setup_business") },
    { done: setup.steps.staffAdded, label: t("setup_staff"), href: "/staff", cta: t("add") },
    { done: setup.steps.staffJoined, label: t("setup_join"), onClick: setup.notJoined > 0 ? remind : undefined, cta: t("remind") },
    { done: setup.steps.salarySet, label: t("setup_salary"), href: "/staff", cta: t("open") },
    { done: setup.steps.teamAdded, label: t("setup_team"), href: "/settings", cta: t("open") },
  ];
  return (
    <Card
      title={
        <span className="flex items-center gap-2">
          {t("checklist_title")} <Badge tone="mint">{fill(t("setup_count"), { d: setup.done, t: setup.total })}</Badge>
        </span>
      }
      actions={
        <Button
          size="sm"
          variant="ghost"
          onClick={() => {
            window.localStorage.setItem(key, "1");
            setHidden(true);
          }}
        >
          {t("hide")}
        </Button>
      }
    >
      {setup.notJoined > 0 && (
        <div className="mb-3 flex flex-wrap items-center justify-between gap-2 rounded-lg bg-amber-50 px-3 py-2 text-sm font-medium text-amber-800">
          {fill(t("invited_joined"), { n: setup.staff, j: setup.joined })}
          <Button size="sm" variant="secondary" loading={action.busy === "remind"} onClick={remind}>
            {t("remind")}
          </Button>
        </div>
      )}
      <ol className="space-y-1.5">
        {steps.map((st, i) => (
          <li key={st.label} className="flex items-center gap-3 text-sm">
            <span
              className={
                st.done
                  ? "flex h-6 w-6 items-center justify-center rounded-full bg-mint-600 text-xs text-white"
                  : "flex h-6 w-6 items-center justify-center rounded-full bg-slate-200 text-xs font-semibold text-slate-600"
              }
            >
              {st.done ? "✓" : i + 1}
            </span>
            <span className={st.done ? "text-slate-400 line-through" : "font-medium"}>{st.label}</span>
            {!st.done && st.href && (
              <Link href={st.href} className="ml-auto text-sm font-medium text-mint-700 underline">
                {st.cta}
              </Link>
            )}
            {!st.done && st.onClick && (
              <Button size="sm" variant="ghost" className="ml-auto" onClick={st.onClick}>
                {st.cta}
              </Button>
            )}
          </li>
        ))}
      </ol>
      {action.error && <Alert className="mt-2">{action.error}</Alert>}
    </Card>
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
