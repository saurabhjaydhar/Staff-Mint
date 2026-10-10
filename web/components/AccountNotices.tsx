"use client";

import { useState } from "react";
import { errorMessage } from "@/lib/api";
import { formatDate } from "@/lib/format";
import type { DictKey } from "@/lib/i18n";
import type { ClosedBusiness, EndedNotice } from "@/lib/types";
import { useAuth, useI18n, useToast } from "./providers";
import { Button } from "./ui";

const REASON_KEY: Record<string, DictKey> = {
  removed: "acc_reason_removed",
  closed: "acc_reason_closed",
  phone_changed: "acc_reason_phone_changed",
  import_rollback: "acc_reason_import_rollback",
};

/** Why a business disappeared ("Your access to X ended on …"), dismissable. */
export function EndedNotices({ notices }: { notices: EndedNotice[] }) {
  const { t } = useI18n();
  const { dismissNotice } = useAuth();
  if (!notices.length) return null;
  return (
    <div className="space-y-2">
      {notices.map((n) => (
        <div key={n.id} data-ended-notice={n.id} className="flex items-start gap-3 rounded-xl bg-amber-50 p-3 text-sm ring-1 ring-amber-200">
          <span className="mt-0.5 text-amber-700" aria-hidden>
            ⓘ
          </span>
          <div className="min-w-0 flex-1">
            <p className="font-semibold text-amber-950">
              {n.endedAt ? t("acc_ended_on").replace("{name}", n.companyName).replace("{date}", formatDate(n.endedAt.slice(0, 10))) : t("acc_ended").replace("{name}", n.companyName)}
            </p>
            <p className="text-amber-800">{t(REASON_KEY[n.endedReason ?? "removed"] ?? "acc_reason_removed")}</p>
          </div>
          <button type="button" className="text-xs font-medium text-amber-800 hover:underline" onClick={() => void dismissNotice(n.id)}>
            {t("acc_dismiss")}
          </button>
        </div>
      ))}
    </div>
  );
}

/** Businesses this person closed, each with a Restore button while the window is open. */
export function ClosedBusinesses({ list, onRestored }: { list: ClosedBusiness[]; onRestored?: () => void }) {
  const { t } = useI18n();
  const { restoreBusiness } = useAuth();
  const toast = useToast();
  const [busy, setBusy] = useState<string | null>(null);
  if (!list.length) return null;
  return (
    <div className="space-y-2">
      <p className="text-xs font-medium uppercase tracking-wide text-slate-400">{t("acc_closed_title")}</p>
      {list.map((b) => (
        <div key={b.companyId} data-closed-business={b.companyId} className="flex items-center gap-3 rounded-xl bg-white p-3 ring-1 ring-slate-200">
          <div className="min-w-0 flex-1">
            <p className="truncate font-semibold text-slate-900">{b.companyName}</p>
            {b.restoreUntil && <p className="text-xs text-slate-500">{t("acc_restore_until").replace("{date}", formatDate(b.restoreUntil.slice(0, 10)))}</p>}
          </div>
          <Button
            size="sm"
            variant="secondary"
            loading={busy === b.companyId}
            disabled={busy !== null}
            onClick={async () => {
              setBusy(b.companyId);
              try {
                await restoreBusiness(b.companyId);
                toast(t("acc_restored").replace("{name}", b.companyName));
                onRestored?.();
              } catch (e) {
                toast(errorMessage(e), "red");
              } finally {
                setBusy(null);
              }
            }}
          >
            {t("acc_restore")}
          </Button>
        </div>
      ))}
    </div>
  );
}
