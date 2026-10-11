"use client";

import { useState } from "react";
import { useAuth, useToast } from "@/components/providers";
import { Alert, Badge, Button, Card, Field, Input, PageHeader, Sheet, Skeleton, cx } from "@/components/ui";
import { api, errorText } from "@/lib/api";
import { invalidate } from "@/lib/cache";
import { FEATURE_LABELS, parseRupees, rupees } from "@/lib/format";
import type { Plan } from "@/lib/types";
import { useApi } from "@/lib/useApi";

interface Draft {
  name: string;
  monthly: string;
  yearly: string;
  staffLimit: string;
  trialDays: string;
  features: string[];
  active: boolean;
}

const toDraft = (p: Plan): Draft => ({
  name: p.name,
  monthly: String(p.priceMonthlyPaise / 100),
  yearly: String(p.priceYearlyPaise / 100),
  staffLimit: String(p.staffLimit),
  trialDays: String(p.trialDays ?? 0),
  features: [...p.features],
  active: p.active !== false,
});

export default function PlansPage() {
  const { data: plans, error, reload } = useApi<Plan[]>("/admin/plans");
  const { canEdit } = useAuth();
  const toast = useToast();
  const [editing, setEditing] = useState<Plan | null>(null);
  const [draft, setDraft] = useState<Draft | null>(null);
  const [busy, setBusy] = useState(false);
  const [formError, setFormError] = useState<string | null>(null);

  function open(p: Plan) {
    setEditing(p);
    setDraft(toDraft(p));
    setFormError(null);
  }

  async function save() {
    if (!editing || !draft) return;
    const monthly = parseRupees(draft.monthly);
    const yearly = parseRupees(draft.yearly);
    const staffLimit = Number(draft.staffLimit);
    const trialDays = Number(draft.trialDays);
    if (monthly === null || yearly === null) return setFormError("Enter prices in rupees, like 499");
    if (!Number.isInteger(staffLimit) || staffLimit < 1) return setFormError("Staff limit must be a whole number, 1 or more");
    if (!Number.isInteger(trialDays) || trialDays < 0 || trialDays > 90) return setFormError("Trial days must be 0 to 90");
    if (!draft.name.trim()) return setFormError("Name can't be empty");
    setBusy(true);
    setFormError(null);
    try {
      await api.put(`/admin/plans/${editing.code}`, {
        name: draft.name.trim(),
        priceMonthlyPaise: monthly,
        priceYearlyPaise: yearly,
        staffLimit,
        trialDays,
        features: draft.features,
        active: draft.active,
        extraStaffPricePaise: editing.extraStaffPricePaise ?? 0,
        maxStaffHardCap: Math.max(editing.maxStaffHardCap ?? staffLimit, staffLimit),
        sort: editing.sort,
        country: editing.country ?? "IN",
        currency: editing.currency ?? "INR",
      });
      invalidate("/admin/plans", "/admin/stats");
      await reload();
      setEditing(null);
      toast(`${draft.name} saved`);
    } catch (e) {
      setFormError(errorText(e));
    } finally {
      setBusy(false);
    }
  }

  const allFeatures = Object.keys(FEATURE_LABELS);

  return (
    <div className="space-y-3">
      <PageHeader title="Plans & prices" subtitle="Changes apply to new subscriptions right away" back="/more" />
      {error && <Alert onRetry={() => void reload()}>{error}</Alert>}
      {!plans ? (
        <div className="grid gap-3 md:grid-cols-2">
          {Array.from({ length: 4 }, (_, i) => (
            <Skeleton key={i} className="h-40 rounded-2xl" />
          ))}
        </div>
      ) : (
        <div className="grid gap-3 md:grid-cols-2">
          {plans.map((p) => (
            <Card key={p.code}>
              <div className="flex items-start justify-between gap-3">
                <div>
                  <p className="flex items-center gap-2 font-semibold">
                    {p.name} {p.active === false && <Badge>Hidden</Badge>}
                  </p>
                  <p className="mt-1 text-2xl font-semibold tabular-nums">
                    {rupees(p.priceMonthlyPaise)}
                    <span className="text-sm font-normal text-slate-500">/month</span>
                  </p>
                  <p className="text-sm text-slate-500">
                    {rupees(p.priceYearlyPaise)}/year · up to {p.staffLimit} staff{p.trialDays ? ` · ${p.trialDays}-day trial` : ""}
                  </p>
                </div>
                {canEdit && (
                  <Button size="sm" variant="secondary" onClick={() => open(p)}>
                    Edit
                  </Button>
                )}
              </div>
              <ul className="mt-3 flex flex-wrap gap-1.5">
                {p.features.map((f) => (
                  <li key={f}>
                    <Badge tone="mint">{FEATURE_LABELS[f] ?? f}</Badge>
                  </li>
                ))}
              </ul>
            </Card>
          ))}
        </div>
      )}

      <Sheet
        open={!!editing && !!draft}
        title={`Edit ${editing?.name ?? ""}`}
        onClose={() => setEditing(null)}
        footer={
          <>
            <Button variant="ghost" className="flex-1" onClick={() => setEditing(null)}>
              Cancel
            </Button>
            <Button className="flex-1" loading={busy} onClick={() => void save()}>
              Save
            </Button>
          </>
        }
      >
        {draft && (
          <div className="space-y-4">
            {formError && <Alert>{formError}</Alert>}
            <Field label="Name">{(id) => <Input id={id} value={draft.name} onChange={(e) => setDraft({ ...draft, name: e.target.value })} />}</Field>
            <div className="grid grid-cols-2 gap-3">
              <Field label="Monthly (₹)">{(id) => <Input id={id} inputMode="decimal" value={draft.monthly} onChange={(e) => setDraft({ ...draft, monthly: e.target.value })} />}</Field>
              <Field label="Yearly (₹)">{(id) => <Input id={id} inputMode="decimal" value={draft.yearly} onChange={(e) => setDraft({ ...draft, yearly: e.target.value })} />}</Field>
              <Field label="Staff limit">{(id) => <Input id={id} inputMode="numeric" value={draft.staffLimit} onChange={(e) => setDraft({ ...draft, staffLimit: e.target.value })} />}</Field>
              <Field label="Trial days">{(id) => <Input id={id} inputMode="numeric" value={draft.trialDays} onChange={(e) => setDraft({ ...draft, trialDays: e.target.value })} />}</Field>
            </div>
            <fieldset>
              <legend className="mb-2 text-sm font-medium text-slate-700">Features</legend>
              <div className="flex flex-wrap gap-2">
                {allFeatures.map((f) => {
                  const on = draft.features.includes(f);
                  return (
                    <button
                      key={f}
                      type="button"
                      aria-pressed={on}
                      onClick={() => setDraft({ ...draft, features: on ? draft.features.filter((x) => x !== f) : [...draft.features, f] })}
                      className={cx("h-9 rounded-full px-3 text-sm ring-1", on ? "bg-mint-600 text-white ring-mint-600" : "bg-white text-slate-700 ring-slate-300")}
                    >
                      {on ? "✓ " : ""}
                      {FEATURE_LABELS[f]}
                    </button>
                  );
                })}
              </div>
            </fieldset>
            <label className="flex items-center gap-3 text-sm">
              <input type="checkbox" className="h-5 w-5 accent-mint-600" checked={draft.active} onChange={(e) => setDraft({ ...draft, active: e.target.checked })} />
              Show this plan to businesses
            </label>
            <p className="text-xs text-slate-500">Businesses already paying keep their locked price until their price lock ends.</p>
          </div>
        )}
      </Sheet>
    </div>
  );
}
