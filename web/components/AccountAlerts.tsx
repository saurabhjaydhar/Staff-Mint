"use client";

import { useState } from "react";
import { api, errorMessage } from "@/lib/api";
import { formatDate } from "@/lib/format";
import { getDeviceId } from "@/lib/tokens";
import { useAuth, useI18n, useToast } from "./providers";
import { Button } from "./ui";

/** Things only this person can act on: ownership offers to accept, recoveries to stop. */
export function AccountAlerts() {
  const { t } = useI18n();
  const toast = useToast();
  const { me, refreshMe, acceptTransfer } = useAuth();
  const [busy, setBusy] = useState<string | null>(null);
  const offers = me?.pendingTransfers ?? [];
  const holds = me?.recoveryHolds ?? [];
  if (!offers.length && !holds.length) return null;

  async function run(id: string, fn: () => Promise<unknown>) {
    setBusy(id);
    try {
      await fn();
    } catch (e) {
      toast(errorMessage(e), "red");
    } finally {
      setBusy(null);
    }
  }

  return (
    <div className="space-y-2">
      {offers.map((o) => (
        <div key={o.id} data-offer={o.id} className="flex flex-wrap items-center gap-3 rounded-xl bg-mint-50 p-3 ring-1 ring-mint-200">
          <div className="min-w-0 flex-1 text-sm">
            <p className="font-semibold text-slate-900">{t("offer_title").replace("{name}", o.companyName ?? "")}</p>
            <p className="text-slate-600">{t("offer_body").replace("{from}", o.fromName ?? t("role_owner"))}</p>
          </div>
          <Button size="sm" variant="ghost" disabled={busy !== null} onClick={() => run(o.id, async () => { await api.post(`/me/transfers/${o.id}/decline`, { deviceId: getDeviceId() }); await refreshMe(); })}>
            {t("offer_decline")}
          </Button>
          <Button size="sm" loading={busy === o.id} disabled={busy !== null} onClick={() => run(o.id, () => acceptTransfer(o.id))}>
            {t("offer_accept")}
          </Button>
        </div>
      ))}
      {holds.map((h) => (
        <div key={h.id} data-hold={h.id} className="flex flex-wrap items-center gap-3 rounded-xl bg-red-50 p-3 ring-1 ring-red-200">
          <div className="min-w-0 flex-1 text-sm">
            <p className="font-semibold text-red-900">{t("hold_title").replace("{name}", h.businessName)}</p>
            <p className="text-red-800">{t("hold_body").replace("{date}", formatDate(h.holdUntil?.slice(0, 10)))}</p>
          </div>
          <Button size="sm" variant="danger" loading={busy === h.id} disabled={busy !== null} onClick={() => run(h.id, async () => { await api.post(`/me/recovery-holds/${h.id}/stop`); await refreshMe(); })}>
            {t("hold_stop")}
          </Button>
        </div>
      ))}
    </div>
  );
}
