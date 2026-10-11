"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { useState } from "react";
import { useAuth, useToast } from "@/components/providers";
import { Alert, Badge, Button, Card, Chips, Field, PageHeader, Rows, Sheet, Skeleton } from "@/components/ui";
import { api, errorText } from "@/lib/api";
import { invalidate } from "@/lib/cache";
import { STATUS_LABEL, STATUS_TONE, ago, date, dateTime, phone, rupees } from "@/lib/format";
import type { BusinessDetail, Plan } from "@/lib/types";
import { useApi } from "@/lib/useApi";

const ACTION_LABEL: Record<string, string> = {
  "company.trial": "Free trial",
  "company.plan": "Plan changed",
  "config.update": "Setting changed",
};

function actionText(a: BusinessDetail["actions"][number]) {
  const d = a.details as Record<string, unknown>;
  if (a.action === "company.trial") return d.skipped ? "Trial skipped (paid plan)" : Number(d.days) === 0 ? "Trial ended now" : `${d.days}-day ${d.planCode} trial`;
  if (a.action === "company.plan") return d.planCode === "free" ? "Moved to Free" : `${d.planCode} for ${d.months} month${d.months === 1 ? "" : "s"}${d.note ? ` · “${d.note}”` : ""}`;
  return ACTION_LABEL[a.action] ?? a.action;
}

export default function BusinessPage() {
  const { id } = useParams<{ id: string }>();
  const path = `/admin/companies/${id}`;
  const { data: b, error, reload } = useApi<BusinessDetail>(path);
  const { data: plans } = useApi<Plan[]>("/admin/plans");
  const { canEdit } = useAuth();
  const toast = useToast();
  const [sheet, setSheet] = useState<null | "trial" | "plan">(null);
  const [days, setDays] = useState("14");
  const [planCode, setPlanCode] = useState("pro");
  const [months, setMonths] = useState("1");
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);
  const [sheetError, setSheetError] = useState<string | null>(null);

  const paidPlans = (plans ?? []).filter((p) => p.code !== "free" && p.active !== false);

  async function run(label: string, fn: () => Promise<unknown>) {
    setBusy(true);
    setSheetError(null);
    try {
      await fn();
      invalidate(path, "/admin/companies?", "/admin/stats");
      await reload();
      setSheet(null);
      toast(label);
    } catch (e) {
      setSheetError(errorText(e));
    } finally {
      setBusy(false);
    }
  }

  if (!b) {
    return (
      <div className="space-y-4">
        <PageHeader title="Business" back="/businesses" />
        {error ? <Alert onRetry={() => void reload()}>{error}</Alert> : <Skeleton className="h-64 w-full rounded-2xl" />}
      </div>
    );
  }

  const owner = b.people.find((p) => p.main) ?? b.people.find((p) => p.role === "owner");
  const waNumber = owner?.phone.replace(/\D/g, "");

  return (
    <div className="space-y-4">
      <PageHeader title={b.name} subtitle={`${b.businessType} · since ${date(b.createdAt)}`} back="/businesses" />

      <Card>
        <div className="flex flex-wrap items-center gap-2">
          <Badge tone={STATUS_TONE[b.status]}>{STATUS_LABEL[b.status]}</Badge>
          <span className="text-sm font-medium text-slate-800">{b.plan.name} plan</span>
          {b.trial?.active && <span className="text-sm text-slate-500">· trial ends {date(b.trial.endsAt)} ({b.trial.daysLeft === 1 ? "last day" : `${b.trial.daysLeft} days left`})</span>}
          {b.trial?.ended && <span className="text-sm text-slate-500">· trial ended {date(b.trial.endsAt)}</span>}
        </div>
        {b.billedTo && (
          <p className="mt-2 text-sm text-slate-600">
            Paid with{" "}
            <Link className="font-medium text-mint-700 underline" href={`/businesses/${b.billedTo.id}`}>
              {b.billedTo.name}
            </Link>
          </p>
        )}
        {canEdit && !b.closedAt && (
          <div className="mt-4 grid grid-cols-2 gap-2 sm:flex">
            <Button variant="secondary" onClick={() => setSheet("trial")}>
              Give free trial
            </Button>
            <Button variant="secondary" onClick={() => setSheet("plan")}>
              Change plan
            </Button>
          </div>
        )}
      </Card>

      <div className="grid gap-4 md:grid-cols-2">
        <Card title="Business">
          <Rows
            rows={[
              ["Staff", `${b.staff.active} active of ${b.staff.total} (limit ${b.plan.staffLimit})`],
              ["Branches", b.branches],
              ["Time zone", b.timezone],
              ["Address", b.address ?? "—"],
              ["Closed", b.closedAt ? date(b.closedAt) : "No"],
              ...(b.onThisBill.length ? ([["Also on this bill", b.onThisBill.map((c) => c.name).join(", ")]] as [string, string][]) : []),
            ]}
          />
        </Card>

        <Card title="People">
          <ul className="-my-1 divide-y divide-slate-100">
            {b.people.map((p, i) => (
              <li key={i} className="flex items-center gap-3 py-2.5 text-sm">
                <span className="min-w-0 flex-1">
                  <span className="block truncate font-medium">{p.name || "No name"}</span>
                  <span className="text-xs text-slate-500">
                    {p.main ? "Main owner" : p.role === "ca" ? "Accountant" : p.role === "owner" ? "Co-owner" : "Manager"} · {phone(p.phone)}
                  </span>
                </span>
                {p.phone && (
                  <a href={`tel:${p.phone}`} className="rounded-lg px-2 py-1 text-xs font-medium text-mint-700 ring-1 ring-mint-200">
                    Call
                  </a>
                )}
              </li>
            ))}
          </ul>
          {waNumber && (
            <a href={`https://wa.me/${waNumber}`} target="_blank" rel="noreferrer" className="mt-3 inline-block text-sm font-medium text-mint-700 underline">
              WhatsApp the owner
            </a>
          )}
        </Card>
      </div>

      <Card title="Subscriptions" padded={false}>
        <ul className="divide-y divide-slate-100">
          {b.subscriptions.map((s) => (
            <li key={s.id} className="flex items-center gap-3 px-4 py-3 text-sm">
              <span className="min-w-0 flex-1">
                <span className="font-medium capitalize">{s.planCode}</span> <span className="text-slate-500">· {s.status}</span>
                <span className="block text-xs text-slate-500">
                  {s.provider} · {s.trialEndsAt ? `trial to ${date(s.trialEndsAt)}` : s.currentPeriodEnd ? `until ${date(s.currentPeriodEnd)}` : "no end"}
                  {s.pricePaise ? ` · ${rupees(s.pricePaise)}/${s.interval === "yearly" ? "yr" : "mo"}` : ""}
                </span>
              </span>
              <span className="shrink-0 text-xs text-slate-400">{date(s.createdAt)}</span>
            </li>
          ))}
        </ul>
      </Card>

      {b.failedMessages.length > 0 && (
        <Card title="Failed messages" padded={false}>
          <ul className="divide-y divide-slate-100">
            {b.failedMessages.map((m) => (
              <li key={m.id} className="px-4 py-3 text-sm">
                <span className="font-medium">{m.template ?? m.channel}</span> <span className="text-slate-500">to {phone(m.to)}</span>
                <span className="block text-xs text-red-600">{m.error ?? "Failed"}</span>
                <span className="text-xs text-slate-400">{dateTime(m.createdAt)}</span>
              </li>
            ))}
          </ul>
        </Card>
      )}

      <Card title="Changes by admins" padded={false}>
        {b.actions.length === 0 ? (
          <p className="px-4 py-6 text-sm text-slate-500">No admin changes yet.</p>
        ) : (
          <ul className="divide-y divide-slate-100">
            {b.actions.map((a) => (
              <li key={a.id} className="px-4 py-3 text-sm">
                <span className="font-medium">{actionText(a)}</span>
                <span className="block text-xs text-slate-500">
                  {a.actor} · {ago(a.createdAt)}
                </span>
              </li>
            ))}
          </ul>
        )}
      </Card>

      <Sheet
        open={sheet === "trial"}
        title="Give a free trial"
        onClose={() => setSheet(null)}
        footer={
          <>
            <Button variant="ghost" className="flex-1" onClick={() => setSheet(null)}>
              Cancel
            </Button>
            <Button className="flex-1" loading={busy} onClick={() => void run(days === "0" ? "Trial ended" : "Trial started", () => api.post("/admin/trials", { companyId: b.id, days: Number(days), planCode }))}>
              {days === "0" ? "End trial now" : "Start trial"}
            </Button>
          </>
        }
      >
        <div className="space-y-4">
          {sheetError && <Alert>{sheetError}</Alert>}
          <p className="text-sm text-slate-600">Replaces any trial this business has. Businesses on a paid plan are left alone.</p>
          <Field label="Length">
            {() => (
              <Chips
                value={days}
                onChange={setDays}
                options={[
                  { value: "7", label: "7 days" },
                  { value: "14", label: "14 days" },
                  { value: "30", label: "30 days" },
                  { value: "0", label: "End now" },
                ]}
              />
            )}
          </Field>
          {days !== "0" && (
            <Field label="Plan">{() => <Chips value={planCode} onChange={setPlanCode} options={paidPlans.map((p) => ({ value: p.code, label: p.name }))} />}</Field>
          )}
        </div>
      </Sheet>

      <Sheet
        open={sheet === "plan"}
        title="Change plan"
        onClose={() => setSheet(null)}
        footer={
          <>
            <Button variant="ghost" className="flex-1" onClick={() => setSheet(null)}>
              Cancel
            </Button>
            <Button
              className="flex-1"
              loading={busy}
              onClick={() => void run("Plan changed", () => api.post(`/admin/companies/${b.id}/plan`, { planCode, months: Number(months), note: note.trim() || undefined }))}
            >
              Save
            </Button>
          </>
        }
      >
        <div className="space-y-4">
          {sheetError && <Alert>{sheetError}</Alert>}
          <p className="text-sm text-slate-600">For deals, free months or fixing a stuck payment. No money is charged; the business sees the plan right away.</p>
          <Field label="Plan">
            {() => <Chips value={planCode} onChange={setPlanCode} options={[...paidPlans.map((p) => ({ value: p.code, label: p.name })), { value: "free", label: "Free" }]} />}
          </Field>
          {planCode !== "free" && (
            <Field label="For how long">
              {() => (
                <Chips
                  value={months}
                  onChange={setMonths}
                  options={[
                    { value: "1", label: "1 month" },
                    { value: "3", label: "3 months" },
                    { value: "6", label: "6 months" },
                    { value: "12", label: "1 year" },
                  ]}
                />
              )}
            </Field>
          )}
          <Field label="Note (optional)" hint="Why — shows in the change log.">
            {(fid) => <input id={fid} value={note} maxLength={300} onChange={(e) => setNote(e.target.value)} className="h-11 w-full rounded-xl border border-slate-300 px-3 text-base outline-none focus:border-mint-500 md:text-sm" />}
          </Field>
        </div>
      </Sheet>
    </div>
  );
}
