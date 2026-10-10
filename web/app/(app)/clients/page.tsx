"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { useAuth, useI18n, useToast } from "@/components/providers";
import {
  Alert,
  Badge,
  Button,
  Card,
  EmptyState,
  Loading,
  PageHeader,
  Table,
  Td,
  Th,
} from "@/components/ui";
import { useAsync } from "@/hooks/useAsync";
import { api, errorMessage } from "@/lib/api";
import { formatPaise } from "@/lib/money";
import type { DictKey } from "@/lib/i18n";
import type { CaClient } from "@/lib/types";

const STATUS: Record<
  CaClient["payrollStatus"],
  { key: DictKey; tone: "slate" | "amber" | "mint" | "sky" }
> = {
  not_started: { key: "cl_status_not_started", tone: "slate" },
  draft: { key: "cl_status_draft", tone: "amber" },
  approved: { key: "cl_status_approved", tone: "sky" },
  paid: { key: "cl_status_paid", tone: "mint" },
};

/** Accountant's month-end round: every client at a glance, one click to open (PRD F14 Phase 4). */
export default function ClientsPage() {
  const { t } = useI18n();
  const toast = useToast();
  const router = useRouter();
  const { me, switchAccount, refreshMe } = useAuth();
  const clients = useAsync(() => api.get<CaClient[]>("/me/clients"), "clients");
  const [busy, setBusy] = useState<string | null>(null);

  async function open(c: CaClient) {
    setBusy(c.membershipId);
    try {
      if (c.membershipId !== me?.activeMembershipId)
        await switchAccount(c.membershipId);
      router.push("/payroll");
    } catch (e) {
      toast(errorMessage(e), "red");
    } finally {
      setBusy(null);
    }
  }

  async function pin(c: CaClient) {
    try {
      await api.patch(`/me/accounts/${c.membershipId}`, { pinned: !c.pinned });
      clients.reload();
      void refreshMe();
    } catch (e) {
      toast(errorMessage(e), "red");
    }
  }

  return (
    <div className="space-y-5">
      <PageHeader title={t("cl_title")} subtitle={t("cl_hint")} />
      {clients.errorText && (
        <Alert onRetry={clients.reload}>{clients.errorText}</Alert>
      )}
      <Card padded={false}>
        {!clients.data ? (
          clients.loading && <Loading />
        ) : clients.data.length === 0 ? (
          <EmptyState>{t("cl_empty")}</EmptyState>
        ) : (
          <Table>
            <thead>
              <tr>
                <Th />
                <Th>{t("setup_business_name")}</Th>
                <Th className="text-right">{t("cl_staff")}</Th>
                <Th>
                  {t("cl_payroll").replace("{month}", clients.data[0].month)}
                </Th>
                <Th />
              </tr>
            </thead>
            <tbody>
              {clients.data.map((c) => (
                <tr key={c.membershipId} data-client={c.companyId}>
                  <Td className="w-8">
                    <button
                      type="button"
                      title={c.pinned ? t("acc_unpin") : t("acc_pin")}
                      className={
                        c.pinned
                          ? "text-amber-500"
                          : "text-slate-300 hover:text-slate-500"
                      }
                      onClick={() => void pin(c)}
                    >
                      ★
                    </button>
                  </Td>
                  <Td className="font-medium text-slate-900">
                    {c.companyName}
                  </Td>
                  <Td className="text-right">{c.staffCount}</Td>
                  <Td>
                    <Badge tone={STATUS[c.payrollStatus].tone}>
                      {t(STATUS[c.payrollStatus].key)}
                    </Badge>
                    {c.netPaise != null && (
                      <span className="ml-2 text-sm text-slate-600">
                        {formatPaise(c.netPaise)}
                      </span>
                    )}
                  </Td>
                  <Td className="text-right">
                    <Button
                      size="sm"
                      variant="secondary"
                      loading={busy === c.membershipId}
                      disabled={busy !== null}
                      onClick={() => void open(c)}
                    >
                      {t("cl_open")}
                    </Button>
                  </Td>
                </tr>
              ))}
            </tbody>
          </Table>
        )}
      </Card>
    </div>
  );
}
