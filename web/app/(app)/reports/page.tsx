"use client";

import { useState } from "react";
import { ExportButton, useRole } from "@/components/AppShell";
import { useI18n, useToast } from "@/components/providers";
import { Alert, Button, Card, Field, Input, PageHeader } from "@/components/ui";
import { useAction } from "@/hooks/useAsync";
import { api } from "@/lib/api";
import { saveBlob } from "@/lib/download";
import { formatMonth, previousMonth } from "@/lib/format";
import type { DictKey } from "@/lib/i18n";
import { canExport } from "@/lib/roles";
import type { ReportFormat, ReportType } from "@/lib/types";

const REPORTS: { type: ReportType; label: DictKey; body: string; icon: string }[] = [
  { type: "attendance", label: "reports_attendance", body: "P/A/HD/L/WO/H grid for every staff member, with totals.", icon: "✓" },
  { type: "salary", label: "reports_salary", body: "Earnings, deductions and net pay for the month.", icon: "₹" },
  { type: "advances", label: "reports_advances", body: "Advances given, repaid and balance per person.", icon: "⇄" },
  { type: "late", label: "reports_late", body: "Who came late and by how many minutes.", icon: "⏰" },
];

export default function ReportsPage() {
  const { t } = useI18n();
  const toast = useToast();
  const { role } = useRole();
  const [month, setMonth] = useState(() => previousMonth());
  const action = useAction();

  async function download(type: ReportType, format: ReportFormat) {
    const res = await action.run(`${type}:${format}`, () =>
      api.download(`/reports/${type}`, { month, format }, `staffmint-${type}-${month}.${format}`),
    );
    if (res.ok) {
      saveBlob(res.value.blob, res.value.filename);
      toast(`Downloaded ${res.value.filename}`);
    }
  }

  return (
    <div className="space-y-5">
      <PageHeader
        title={t("nav_reports")}
        subtitle="Download monthly reports as PDF or Excel — share them with your accountant."
        actions={canExport(role) && <ExportButton />}
      />
      <Card>
        <Field label={t("month")} className="w-48">
          {(id) => <Input id={id} type="month" value={month} onChange={(e) => e.target.value && setMonth(e.target.value)} />}
        </Field>
      </Card>
      {action.error && <Alert>{action.error}</Alert>}
      <div className="grid gap-4 sm:grid-cols-2">
        {REPORTS.map((r) => (
          <Card key={r.type}>
            <div className="flex items-start gap-3">
              <span className="grid h-10 w-10 shrink-0 place-items-center rounded-lg bg-mint-50 text-lg text-mint-700">{r.icon}</span>
              <div className="flex-1">
                <h2 className="font-semibold">{t(r.label)}</h2>
                <p className="text-sm text-slate-500">{r.body}</p>
                <p className="mt-1 text-xs text-slate-400">{formatMonth(month)}</p>
                <div className="mt-3 flex gap-2">
                  <Button size="sm" variant="secondary" loading={action.busy === `${r.type}:pdf`} disabled={!!action.busy} onClick={() => download(r.type, "pdf")}>
                    ⇩ PDF
                  </Button>
                  <Button size="sm" variant="secondary" loading={action.busy === `${r.type}:xlsx`} disabled={!!action.busy} onClick={() => download(r.type, "xlsx")}>
                    ⇩ Excel
                  </Button>
                </div>
              </div>
            </div>
          </Card>
        ))}
      </div>
    </div>
  );
}
