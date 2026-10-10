"use client";

import Link from "next/link";
import { useState } from "react";
import { errorMessage } from "@/lib/api";
import { ROLE_KEY, ROLE_TONE, businessIcon, newBusinessLabel, webCanOpen } from "@/lib/accounts";
import type { Membership } from "@/lib/types";
import { useAuth, useI18n, useToast } from "./providers";
import { Badge, Spinner, cx } from "./ui";

/**
 * Every business this number can open, with its role. Picking one opens it
 * in this browser; staff accounts are shown but open only in the mobile app.
 */
export function AccountChooser({
  memberships,
  activeId,
  onChosen,
  showNew = true,
}: {
  memberships: Membership[];
  activeId: string | null | undefined;
  onChosen: (m: Membership, switched: boolean) => void;
  showNew?: boolean;
}) {
  const { switchAccount } = useAuth();
  const { t } = useI18n();
  const toast = useToast();
  const [busy, setBusy] = useState<string | null>(null);

  async function pick(m: Membership) {
    if (m.id === activeId) return onChosen(m, false);
    setBusy(m.id);
    try {
      await switchAccount(m.id);
      toast(t("acc_switched").replace("{name}", m.companyName));
      onChosen(m, true);
    } catch (e) {
      toast(errorMessage(e), "red");
    } finally {
      setBusy(null);
    }
  }

  return (
    <div className="space-y-2.5">
      {memberships.map((m) => {
        const active = m.id === activeId;
        const usable = webCanOpen(m);
        return (
          <button
            key={m.id}
            type="button"
            data-account={m.id}
            disabled={!usable || busy !== null}
            onClick={() => void pick(m)}
            className={cx(
              "flex w-full items-center gap-3 rounded-xl p-3 text-left ring-1 transition-colors",
              active && usable ? "bg-mint-50 ring-2 ring-mint-400" : "bg-white ring-slate-200",
              usable ? "hover:bg-mint-50/60" : "cursor-not-allowed opacity-70",
            )}
          >
            <span
              className={cx("grid h-11 w-11 shrink-0 place-items-center rounded-xl text-xl", active && usable ? "bg-mint-500 text-white" : "bg-mint-50 text-mint-700")}
              aria-hidden
            >
              {businessIcon(m.businessType)}
            </span>
            <span className="min-w-0 flex-1">
              <span className="block truncate font-semibold text-slate-900">{m.companyName}</span>
              <span className="mt-1 flex flex-wrap items-center gap-2 text-xs">
                <Badge tone={ROLE_TONE[m.role]}>{t(ROLE_KEY[m.role])}</Badge>
                {active && usable && <span className="font-medium text-mint-700">{t("acc_open_now")}</span>}
                {!usable && <span className="text-slate-500">{t("acc_app_only")}</span>}
              </span>
            </span>
            <span className="w-5 shrink-0 text-center text-slate-400" aria-hidden>
              {busy === m.id ? <Spinner /> : active && usable ? <span className="text-mint-600">✓</span> : usable ? "›" : ""}
            </span>
          </button>
        );
      })}
      {showNew && (
        <Link
          href="/business/new"
          data-new-business
          className="flex items-center gap-3 rounded-xl p-3 text-left border border-dashed border-mint-300 transition-colors hover:bg-mint-50/60"
        >
          <span className="grid h-11 w-11 shrink-0 place-items-center rounded-xl bg-mint-50 text-xl font-semibold text-mint-700" aria-hidden>
            ＋
          </span>
          <span className="min-w-0 flex-1">
            <span className="block font-semibold text-mint-700">{t(newBusinessLabel(memberships))}</span>
            <span className="block text-xs text-slate-500">{t("acc_new_hint")}</span>
          </span>
        </Link>
      )}
    </div>
  );
}
