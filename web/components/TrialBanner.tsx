"use client";

import Link from "next/link";
import { useState } from "react";
import type { DictKey } from "@/lib/i18n";
import { trialBanner, trialDismissKey } from "@/lib/trial";
import { useAuth, useI18n } from "./providers";
import { cx } from "./ui";

const readDismissed = (companyId: string) => {
  try {
    return localStorage.getItem(trialDismissKey(companyId));
  } catch {
    return null;
  }
};

/** "Pro free trial: 9 days left" for owners; after the trial, what keeps working and what is paused. */
export function TrialBanner() {
  const { t } = useI18n();
  const { me } = useAuth();
  const company = me?.company;
  const [dismissed, setDismissed] = useState<string | null>(() => (company ? readDismissed(company.id) : null));
  if (!company) return null;
  const state = trialBanner(company.trial, { isOwner: me?.user.role === "owner", dismissedFor: dismissed });
  if (state.kind === "none") return null;

  if (state.kind === "active") {
    const title = (state.days <= 1 ? t("trial_last_day") : t("trial_left")).replace("{plan}", state.planName).replace("{n}", String(state.days));
    const body = (state.soon ? t("trial_ends_soon") : t("trial_all_on")).replace("{date}", state.endsOn);
    return (
      <div
        data-trial="active"
        className={cx(
          "flex flex-wrap items-center gap-3 rounded-xl p-3 ring-1",
          state.soon ? "bg-amber-50 ring-amber-200" : "bg-mint-50 ring-mint-200",
        )}
      >
        <span aria-hidden className="text-xl">✨</span>
        <div className="min-w-0 flex-1 text-sm">
          <p className={cx("font-semibold", state.soon ? "text-amber-800" : "text-mint-800")}>{title}</p>
          <p className="text-slate-600">{body}</p>
        </div>
        <Link href="/billing" className="text-sm font-medium text-mint-700 underline">
          {t("trial_see_plans")}
        </Link>
      </div>
    );
  }

  const paused = state.paused.map((f) => t(`feat_${f}` as DictKey) || f).join(", ");
  return (
    <div data-trial="ended" className="flex flex-wrap items-center gap-3 rounded-xl bg-slate-50 p-3 ring-1 ring-slate-200">
      <span aria-hidden className="text-xl">ℹ️</span>
      <div className="min-w-0 flex-1 text-sm">
        <p className="font-semibold text-slate-900">{t("trial_ended_title")}</p>
        <p className="text-slate-600">
          {t("trial_ended_body")} {paused && t("trial_paused").replace("{list}", paused)}
        </p>
      </div>
      <Link href="/billing" className="text-sm font-medium text-mint-700 underline">
        {t("trial_upgrade")}
      </Link>
      <button
        type="button"
        aria-label={t("acc_dismiss")}
        className="px-1 text-lg leading-none text-slate-400 hover:text-slate-600"
        onClick={() => {
          const endsAt = company.trial!.endsAt;
          try {
            localStorage.setItem(trialDismissKey(company.id), endsAt);
          } catch {
            // private mode: hide for this visit only
          }
          setDismissed(endsAt);
        }}
      >
        ×
      </button>
    </div>
  );
}
