"use client";

import { useState } from "react";
import { ExportButton } from "@/components/AppShell";
import { useAuth, useI18n, useToast } from "@/components/providers";
import {
  Alert,
  Badge,
  Button,
  Card,
  Loading,
  PageHeader,
  Segmented,
  cx,
  type Tone,
} from "@/components/ui";
import { useAction, useAsync } from "@/hooks/useAsync";
import { api, errorMessage } from "@/lib/api";
import { formatDate } from "@/lib/format";
import { formatPaise } from "@/lib/money";
import type {
  BillingGroup,
  Plan,
  SubscribeResult,
  Subscription,
  SubscriptionInfo,
} from "@/lib/types";

const FEATURE_LABELS: Record<string, string> = {
  attendance: "Selfie + GPS attendance",
  leave: "Leave management",
  digest: "Daily summary",
  payroll: "Salary calculation",
  advances: "Advances (udhaar)",
  payslips: "Salary slips (PDF)",
  assistant: "Mint AI assistant",
  branches: "Multiple branches",
  reports: "Reports (PDF/Excel)",
  roster: "Weekly roster (shifts)",
  roster_repeat: "Roster repeats every week",
  roster_swaps: "Staff swap shifts (you approve)",
  verification: "Documents check (Aadhaar, PAN, bank)",
  whatsapp_payslips: "Salary slips on WhatsApp",
  whatsapp_assistant: "WhatsApp assistant",
  face_match: "Face check",
  ca_access: "Accountant (CA) access",
  priority_support: "Priority support",
};

const STATUS_TONE: Record<Subscription["status"], Tone> = {
  trialing: "sky",
  active: "mint",
  past_due: "red",
  cancelled: "slate",
  free: "slate",
};

export default function BillingPage() {
  const { t } = useI18n();
  const toast = useToast();
  const { refreshMe } = useAuth();
  const [interval, setBillingInterval] = useState<"monthly" | "yearly">(
    "monthly",
  );
  const plans = useAsync(
    () => api.get<Plan[]>("/billing/plans", undefined, { auth: false }),
    "plans",
  );
  const sub = useAsync(
    () => api.get<SubscriptionInfo>("/billing/subscription"),
    "subscription",
  );
  const action = useAction();

  async function subscribe(plan: Plan) {
    const res = await action.run(`sub:${plan.code}`, () =>
      api.post<SubscribeResult>("/billing/subscribe", {
        planCode: plan.code,
        interval,
      }),
    );
    if (res.ok) {
      if (res.value.checkoutUrl) window.location.assign(res.value.checkoutUrl);
      else {
        toast("Subscription updated");
        sub.reload();
      }
    }
  }

  async function cancel() {
    if (
      !window.confirm(
        "Cancel your subscription? You can still export all your data for 30 days.",
      )
    )
      return;
    const res = await action.run("cancel", () =>
      api.post<{ subscription: Subscription }>("/billing/cancel"),
    );
    if (res.ok) {
      toast("Subscription cancelled");
      sub.reload();
      void refreshMe();
    }
  }

  const current = sub.data;
  const currentCode = current?.subscription.planCode;
  const canCancel =
    current &&
    (current.subscription.status === "active" ||
      current.subscription.status === "trialing" ||
      current.subscription.status === "past_due");
  const yearlyAvailable = (plans.data ?? []).some(
    (p) => p.priceYearlyPaise > 0,
  );

  return (
    <div className="space-y-6">
      <PageHeader
        title={t("nav_billing")}
        subtitle="Simple, fair pricing. No renewal surprises. Your data export is always free."
        actions={<ExportButton />}
      />
      {action.error && <Alert>{action.error}</Alert>}

      <Card title="Current plan">
        {sub.errorText && <Alert onRetry={sub.reload}>{sub.errorText}</Alert>}
        {!current && sub.loading ? (
          <Loading />
        ) : current ? (
          <div className="flex flex-wrap items-center justify-between gap-4">
            <div className="space-y-1">
              <div className="flex items-center gap-2 text-lg font-semibold">
                {current.plan?.name ?? currentCode}
                <Badge tone={STATUS_TONE[current.subscription.status]}>
                  {current.subscription.status.replace("_", " ")}
                </Badge>
              </div>
              <div className="text-sm text-slate-600">
                {current.staffCount} of {current.plan?.staffLimit ?? "—"} staff
                used
                {current.trial && (
                  <span data-billing-trial>
                    {" "}
                    ·{" "}
                    {(current.trial.active ? t("trial_until") : t("trial_ended_on")).replace(
                      "{date}",
                      formatDate(current.trial.endsAt),
                    )}
                  </span>
                )}
                {current.subscription.currentPeriodEnd && (
                  <>
                    {" "}
                    ·{" "}
                    {current.subscription.status === "cancelled"
                      ? "Access until"
                      : current.subscription.status === "trialing"
                        ? "Trial ends"
                        : "Renews"}{" "}
                    {formatDate(current.subscription.currentPeriodEnd)}
                  </>
                )}
              </div>
              {current.subscription.status === "past_due" && (
                <p className="text-sm text-red-600">
                  Your last payment failed. Please subscribe again to keep using
                  paid features.
                </p>
              )}
            </div>
            {canCancel && (
              <Button
                variant="secondary"
                onClick={cancel}
                loading={action.busy === "cancel"}
              >
                Cancel subscription
              </Button>
            )}
          </div>
        ) : null}
      </Card>

      {current?.billedTo ? (
        <Alert tone="sky">
          {t("bill_with").replace("{name}", current.billedTo.name)}
        </Alert>
      ) : (
        <OneBillCard onChange={sub.reload} />
      )}

      {!current?.billedTo && (
        <>
          <div className="flex items-center justify-between">
            <h2 className="text-lg font-semibold">Plans</h2>
            {yearlyAvailable && (
              <Segmented
                value={interval}
                onChange={setBillingInterval}
                options={[
                  { value: "monthly", label: "Monthly" },
                  { value: "yearly", label: "Yearly" },
                ]}
              />
            )}
          </div>
          {plans.errorText && (
            <Alert onRetry={plans.reload}>{plans.errorText}</Alert>
          )}
          {!plans.data && plans.loading ? (
            <Loading />
          ) : (
            <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
              {(plans.data ?? []).map((p) => {
                const isCurrent =
                  p.code === currentCode &&
                  current?.subscription.status !== "cancelled";
                const price =
                  interval === "yearly"
                    ? p.priceYearlyPaise
                    : p.priceMonthlyPaise;
                const free =
                  p.priceMonthlyPaise === 0 && p.priceYearlyPaise === 0;
                return (
                  <div
                    key={p.code}
                    className={cx(
                      "flex flex-col rounded-xl bg-white p-5 shadow-sm ring-1",
                      isCurrent ? "ring-2 ring-mint-500" : "ring-slate-200",
                    )}
                  >
                    <div className="flex items-center justify-between">
                      <h3 className="font-semibold">{p.name}</h3>
                      {isCurrent && <Badge tone="mint">Current</Badge>}
                    </div>
                    <div className="mt-3">
                      <span className="text-3xl font-bold">
                        {free
                          ? "Free"
                          : formatPaise(price, { decimals: "never" })}
                      </span>
                      {!free && (
                        <span className="text-sm text-slate-500">
                          /{interval === "yearly" ? "year" : "month"}
                        </span>
                      )}
                      {p.currency && p.currency !== "INR" && (
                        <span className="ml-1 text-xs text-slate-500">
                          {p.currency}
                        </span>
                      )}
                    </div>
                    <div className="mt-1 text-sm text-slate-600">
                      Up to {p.staffLimit} staff
                      {p.extraStaffPricePaise > 0 && (
                        <>
                          {" "}
                          · {formatPaise(p.extraStaffPricePaise)} per extra
                          staff
                        </>
                      )}
                    </div>
                    {p.trialDays > 0 && (
                      <div className="mt-1 text-xs text-mint-700">
                        {p.trialDays}-day free trial
                      </div>
                    )}
                    <ul className="mt-4 flex-1 space-y-1 text-sm text-slate-700">
                      {p.features.map((f) => (
                        <li key={f} className="flex gap-2">
                          <span className="text-mint-500">✓</span>
                          {FEATURE_LABELS[f] ?? f}
                        </li>
                      ))}
                    </ul>
                    <Button
                      className="mt-5 w-full"
                      variant={isCurrent ? "secondary" : "primary"}
                      disabled={isCurrent || free || !!action.busy}
                      loading={action.busy === `sub:${p.code}`}
                      onClick={() => subscribe(p)}
                    >
                      {isCurrent
                        ? "Your plan"
                        : free
                          ? "Included"
                          : "Choose plan"}
                    </Button>
                  </div>
                );
              })}
            </div>
          )}
        </>
      )}
      <p className="text-xs text-slate-500">
        Prices are set by StaffMint and may include or exclude GST as shown at
        checkout. Payments are processed securely by our payment partner.
      </p>
    </div>
  );
}

/** One bill for several businesses of the same main owner (PRD F14 Phase 4). */
function OneBillCard({ onChange }: { onChange: () => void }) {
  const { t } = useI18n();
  const toast = useToast();
  const group = useAsync(
    () => api.get<BillingGroup>("/billing/group"),
    "billing-group",
  );
  const [busy, setBusy] = useState<string | null>(null);
  const g = group.data;
  if (!g || !g.isPayer || (!g.members.length && !g.candidates.length))
    return null;

  async function run(id: string, fn: () => Promise<BillingGroup>) {
    setBusy(id);
    try {
      group.setData(await fn());
      onChange();
    } catch (e) {
      toast(errorMessage(e), "red");
    } finally {
      setBusy(null);
    }
  }

  return (
    <Card title={t("bill_one")}>
      <p className="mb-3 text-sm text-slate-600">
        {t("bill_one_hint").replace(
          "{price}",
          formatPaise(g.extraBusinessPricePaise),
        )}
      </p>
      {g.members.length > 0 && (
        <p className="mb-2 text-sm font-medium">
          {t("bill_total").replace("{n}", String(g.totalStaff))}
        </p>
      )}
      <ul className="divide-y divide-slate-100">
        {g.members.map((m) => (
          <li
            key={m.companyId}
            data-bill-member={m.companyId}
            className="flex items-center justify-between gap-3 py-2"
          >
            <span>
              <span className="font-medium">{m.name}</span>{" "}
              <Badge tone="mint">{t("bill_on")}</Badge>
            </span>
            <Button
              size="sm"
              variant="ghost"
              loading={busy === m.companyId}
              onClick={() =>
                run(m.companyId, () =>
                  api.delete<BillingGroup>(
                    `/billing/group/members/${m.companyId}`,
                  ),
                )
              }
            >
              {t("bill_remove")}
            </Button>
          </li>
        ))}
        {g.candidates.map((c) => (
          <li
            key={c.companyId}
            data-bill-candidate={c.companyId}
            className="flex items-center justify-between gap-3 py-2"
          >
            <span className="font-medium">{c.name}</span>
            <Button
              size="sm"
              variant="secondary"
              loading={busy === c.companyId}
              onClick={() =>
                run(c.companyId, () =>
                  api.post<BillingGroup>("/billing/group/members", {
                    companyId: c.companyId,
                  }),
                )
              }
            >
              {t("bill_add")}
            </Button>
          </li>
        ))}
      </ul>
    </Card>
  );
}
