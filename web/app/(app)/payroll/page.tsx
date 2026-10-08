"use client";

import { Fragment, useState, type FormEvent } from "react";
import { useRole } from "@/components/AppShell";
import { useI18n, useToast } from "@/components/providers";
import { Alert, Badge, Button, Card, EmptyState, Field, Input, Loading, PageHeader, Select, Stat, Table, Td, Th, cx, type Tone } from "@/components/ui";
import { useAction, useAsync } from "@/hooks/useAsync";
import { api } from "@/lib/api";
import { defaultPayrollMonth, formatDateTime, formatMonth } from "@/lib/format";
import { formatPaise } from "@/lib/money";
import type { CompareResult, PayrollRun, Payslip } from "@/lib/types";

const RUN_TONE: Record<PayrollRun["status"], Tone> = { draft: "amber", approved: "sky", paid: "mint", superseded: "slate" };
const SLIP_TONE: Record<Payslip["status"], Tone> = { draft: "amber", final: "sky", sent: "mint" };

function pickDefaultRun(runs: PayrollRun[]): PayrollRun | undefined {
  const sorted = [...runs].sort((a, b) => b.revision - a.revision);
  return sorted.find((r) => r.status !== "superseded") ?? sorted[0];
}

export default function PayrollPage() {
  const { t } = useI18n();
  const toast = useToast();
  const { readOnly } = useRole();
  const [month, setMonth] = useState(() => defaultPayrollMonth());
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const action = useAction();

  const runs = useAsync(() => api.get<PayrollRun[]>("/payroll/runs", { month }), `runs:${month}`);
  const activeId = selectedId ?? pickDefaultRun(runs.data ?? [])?.id ?? null;
  const run = useAsync(() => api.get<PayrollRun>(`/payroll/runs/${activeId}`), activeId ? `run:${activeId}` : null);
  const current = activeId ? run.data && run.data.id === activeId ? run.data : undefined : undefined;

  function changeMonth(m: string) {
    setMonth(m);
    setSelectedId(null);
  }

  async function act(key: string, fn: () => Promise<PayrollRun>, message: string) {
    const res = await action.run(key, fn);
    if (res.ok) {
      run.setData(res.value);
      setSelectedId(res.value.id);
      runs.reload();
      toast(message);
    }
  }

  async function createDraft() {
    await act("create", () => api.post<PayrollRun>("/payroll/runs", { month }), "Salary draft ready");
  }

  async function sendPayslips(r: PayrollRun) {
    if (!window.confirm(`Send payslips for ${formatMonth(r.month)} to ${r.totals.employees} staff on WhatsApp/app?`)) return;
    const res = await action.run("send", () => api.post<{ queued: number }>("/payslips/send", { runId: r.id }));
    if (res.ok) {
      toast(`${res.value?.queued ?? 0} payslip(s) queued for sending`);
      run.reload();
    }
  }

  const list = [...(runs.data ?? [])].sort((a, b) => b.revision - a.revision);

  return (
    <div className="space-y-5">
      <PageHeader
        title={t("nav_payroll")}
        subtitle={readOnly ? t("readOnly") : "Draft → check anomalies → approve → send payslips → mark paid."}
        actions={
          <div className="flex items-end gap-2">
            <Field label={t("month")} className="w-44">
              {(id) => <Input id={id} type="month" value={month} onChange={(e) => e.target.value && changeMonth(e.target.value)} />}
            </Field>
            {list.length > 1 && (
              <Field label="Revision" className="w-48">
                {(id) => (
                  <Select id={id} value={activeId ?? ""} onChange={(e) => setSelectedId(e.target.value)}>
                    {list.map((r) => (
                      <option key={r.id} value={r.id}>
                        Rev {r.revision} · {r.status}
                      </option>
                    ))}
                  </Select>
                )}
              </Field>
            )}
          </div>
        }
      />

      {runs.errorText && <Alert onRetry={runs.reload}>{runs.errorText}</Alert>}
      {action.error && <Alert>{action.error}</Alert>}

      {runs.loading && !runs.data ? (
        <Loading />
      ) : list.length === 0 ? (
        <Card>
          <EmptyState>
            <p className="mb-3">No salary run for {formatMonth(month)} yet.</p>
            {!readOnly && (
              <Button onClick={createDraft} loading={action.busy === "create"}>
                {t("payroll_create")}
              </Button>
            )}
          </EmptyState>
        </Card>
      ) : !current ? (
        run.errorText ? <Alert onRetry={run.reload}>{run.errorText}</Alert> : <Loading />
      ) : (
        <>
          <Card
            title={
              <span className="flex flex-wrap items-center gap-2">
                {formatMonth(current.month)} · Revision {current.revision}
                <Badge tone={RUN_TONE[current.status]}>{current.status}</Badge>
              </span>
            }
            actions={
              !readOnly && (
                <RunActions
                  run={current}
                  busy={action.busy}
                  onRecompute={() =>
                    act("recompute", () => api.post<PayrollRun>(`/payroll/runs/${current.id}/recompute`), "Recomputed with latest attendance")
                  }
                  onApprove={() => {
                    if (window.confirm("Approve salaries? Payslip PDFs will be generated.")) {
                      void act("approve", () => api.post<PayrollRun>(`/payroll/runs/${current.id}/approve`), "Salaries approved");
                    }
                  }}
                  onSend={() => void sendPayslips(current)}
                  onPaid={() => {
                    if (window.confirm("Mark this month's salaries as paid?")) {
                      void act("paid", () => api.post<PayrollRun>(`/payroll/runs/${current.id}/mark-paid`), "Marked as paid");
                    }
                  }}
                  onRevise={() => {
                    if (window.confirm("Create a new revision? The current payslips stay as they are; corrections go into a new draft.")) {
                      void act("revise", () => api.post<PayrollRun>(`/payroll/runs/${current.id}/revise`), "New draft revision created");
                    }
                  }}
                />
              )
            }
          >
            <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
              <Stat label="Staff" value={current.totals.employees} />
              <Stat label={t("payroll_gross")} value={formatPaise(current.totals.grossPaise)} />
              <Stat label={t("payroll_deductions")} value={formatPaise(current.totals.deductionsPaise)} tone="red" />
              <Stat label={t("payroll_net")} value={formatPaise(current.totals.netPaise)} tone="mint" />
            </div>
            <div className="mt-3 flex flex-wrap gap-4 text-xs text-slate-500">
              <span>Engine {current.engineVersion}</span>
              {current.approvedAt && <span>Approved {formatDateTime(current.approvedAt)}</span>}
              {current.paidAt && <span>Paid {formatDateTime(current.paidAt)}</span>}
            </div>
          </Card>

          {current.anomalies.length > 0 && (
            <Card title={<span className="flex items-center gap-2">{t("payroll_anomalies")} <Badge tone="amber">{current.anomalies.length}</Badge></span>}>
              <ul className="space-y-1.5 text-sm">
                {current.anomalies.map((a, i) => (
                  <li key={`${a.employeeId}-${a.code}-${i}`} className="flex gap-2">
                    <span className="text-amber-500">⚠</span>
                    <span>
                      <span className="font-medium">{a.employeeName}</span> — {a.message}
                    </span>
                  </li>
                ))}
              </ul>
            </Card>
          )}

          <PayslipTable payslips={current.payslips ?? []} />

          {!readOnly && <CompareCard runId={current.id} />}
        </>
      )}
    </div>
  );
}

function RunActions({
  run,
  busy,
  onRecompute,
  onApprove,
  onSend,
  onPaid,
  onRevise,
}: {
  run: PayrollRun;
  busy: string | null;
  onRecompute: () => void;
  onApprove: () => void;
  onSend: () => void;
  onPaid: () => void;
  onRevise: () => void;
}) {
  const { t } = useI18n();
  const dis = !!busy;
  if (run.status === "superseded") return <span className="text-xs text-slate-500">Replaced by a newer revision</span>;
  return (
    <>
      {run.status === "draft" && (
        <>
          <Button size="sm" variant="secondary" onClick={onRecompute} loading={busy === "recompute"} disabled={dis}>
            ↻ {t("payroll_recompute")}
          </Button>
          <Button size="sm" onClick={onApprove} loading={busy === "approve"} disabled={dis}>
            ✓ {t("approve")}
          </Button>
        </>
      )}
      {(run.status === "approved" || run.status === "paid") && (
        <Button size="sm" variant="secondary" onClick={onSend} loading={busy === "send"} disabled={dis}>
          ✉ {t("payroll_send")}
        </Button>
      )}
      {run.status === "approved" && (
        <Button size="sm" onClick={onPaid} loading={busy === "paid"} disabled={dis}>
          ₹ {t("payroll_mark_paid")}
        </Button>
      )}
      {(run.status === "approved" || run.status === "paid") && (
        <Button size="sm" variant="ghost" onClick={onRevise} loading={busy === "revise"} disabled={dis}>
          ✎ {t("payroll_revise")}
        </Button>
      )}
    </>
  );
}

function PayslipTable({ payslips }: { payslips: Payslip[] }) {
  const { t } = useI18n();
  const [open, setOpen] = useState<Record<string, boolean>>({});
  const [filter, setFilter] = useState("");
  const shown = payslips.filter((p) => p.employeeName.toLowerCase().includes(filter.trim().toLowerCase()));

  return (
    <Card
      title={`Payslips (${payslips.length})`}
      actions={<Input className="h-8 w-56 py-1" placeholder={t("search")} value={filter} onChange={(e) => setFilter(e.target.value)} />}
      padded={false}
    >
      {payslips.length === 0 ? (
        <EmptyState>No payslips in this run.</EmptyState>
      ) : (
        <Table>
          <thead>
            <tr>
              <Th className="w-8" />
              <Th>{t("employee")}</Th>
              <Th>Rate</Th>
              <Th className="text-right">Payable days</Th>
              <Th className="text-right">{t("payroll_gross")}</Th>
              <Th className="text-right">{t("payroll_deductions")}</Th>
              <Th className="text-right">{t("payroll_net")}</Th>
              <Th>{t("status")}</Th>
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-100">
            {shown.map((p) => {
              const isOpen = !!open[p.id];
              return (
                <Fragment key={p.id}>
                  <tr className={cx("cursor-pointer hover:bg-slate-50", isOpen && "bg-slate-50")} onClick={() => setOpen((o) => ({ ...o, [p.id]: !o[p.id] }))}>
                    <Td className="text-slate-400">{isOpen ? "▾" : "▸"}</Td>
                    <Td className="font-medium">{p.employeeName}</Td>
                    <Td className="text-xs">
                      {formatPaise(p.ratePaise)}/{p.wageType === "daily" ? "day" : "month"}
                    </Td>
                    <Td className="text-right">
                      {p.payableDays}
                      {p.wageType === "monthly" && <span className="text-xs text-slate-500"> / {p.divisor}</span>}
                    </Td>
                    <Td className="text-right">{formatPaise(p.grossPaise)}</Td>
                    <Td className="text-right text-red-600">{p.deductionsPaise ? `-${formatPaise(p.deductionsPaise)}` : "—"}</Td>
                    <Td className={cx("text-right font-semibold", p.netPaise < 0 && "text-red-600")}>{formatPaise(p.netPaise)}</Td>
                    <Td>
                      <Badge tone={SLIP_TONE[p.status]}>{p.status}</Badge>
                    </Td>
                  </tr>
                  {isOpen && (
                    <tr>
                      <td colSpan={8} className="bg-slate-50 px-6 pb-4">
                        <PayslipDetail payslip={p} />
                      </td>
                    </tr>
                  )}
                </Fragment>
              );
            })}
          </tbody>
        </Table>
      )}
    </Card>
  );
}

function PayslipDetail({ payslip: p }: { payslip: Payslip }) {
  const [explain, setExplain] = useState<{ text: string; lines: string[] } | null>(null);
  const action = useAction();
  const s = p.summary;
  const summary: [string, number][] = [
    ["Present", s.present],
    ["Half day", s.halfDay],
    ["Absent", s.absent],
    ["Paid leave", s.paidLeave],
    ["Unpaid leave", s.unpaidLeave],
    ["Holidays", s.holidays],
    ["Week offs", s.weekOffs],
    ["Unmarked", s.unmarked],
  ];
  return (
    <div className="grid gap-4 pt-2 lg:grid-cols-[1fr_2fr]">
      <div>
        <h4 className="mb-1 text-xs font-semibold uppercase text-slate-500">Days ({p.daysInMonth} in month)</h4>
        <dl className="grid grid-cols-2 gap-x-4 gap-y-0.5 text-sm">
          {summary.map(([k, v]) => (
            <Fragment key={k}>
              <dt className="text-slate-600">{k}</dt>
              <dd className={cx("text-right font-medium", k === "Unmarked" && v > 0 && "text-amber-600")}>{v}</dd>
            </Fragment>
          ))}
        </dl>
        <div className="mt-3 flex flex-wrap gap-2">
          {p.pdfUrl && (
            <a href={p.pdfUrl} target="_blank" rel="noreferrer" className="text-sm font-medium text-mint-700 underline">
              Open PDF
            </a>
          )}
          {p.sentAt && <span className="text-xs text-slate-500">Sent {formatDateTime(p.sentAt)}</span>}
        </div>
      </div>
      <div>
        <h4 className="mb-1 text-xs font-semibold uppercase text-slate-500">Lines</h4>
        <ul className="divide-y divide-slate-200 rounded-lg bg-white ring-1 ring-slate-200">
          {p.lines.map((l, i) => (
            <li key={`${l.code}-${i}`} className="flex items-start justify-between gap-3 px-3 py-2 text-sm">
              <div>
                <div className="font-medium">{l.label}</div>
                <div className="text-xs text-slate-500">{l.explanation}</div>
              </div>
              <div className={cx("whitespace-nowrap font-medium", l.kind === "deduction" ? "text-red-600" : "text-slate-900")}>
                {l.kind === "deduction" ? "-" : "+"}
                {formatPaise(l.amountPaise)}
              </div>
            </li>
          ))}
          <li className="flex justify-between px-3 py-2 text-sm font-semibold">
            <span>Net pay</span>
            <span>{formatPaise(p.netPaise)}</span>
          </li>
        </ul>
        <div className="mt-2">
          {explain ? (
            <div className="rounded-lg bg-mint-50 p-3 text-sm text-mint-900">
              <p>{explain.text}</p>
              {explain.lines.length > 0 && (
                <ul className="mt-1 list-disc pl-5">
                  {explain.lines.map((l, i) => (
                    <li key={i}>{l}</li>
                  ))}
                </ul>
              )}
            </div>
          ) : (
            <Button
              size="sm"
              variant="ghost"
              loading={action.busy === "explain"}
              onClick={async () => {
                const res = await action.run("explain", () => api.get<{ text: string; lines: string[] }>(`/payslips/${p.id}/explain`));
                if (res.ok) setExplain(res.value);
              }}
            >
              💬 Explain in plain words
            </Button>
          )}
          {action.error && <Alert className="mt-2">{action.error}</Alert>}
        </div>
      </div>
    </div>
  );
}

function CompareCard({ runId }: { runId: string }) {
  const { t } = useI18n();
  const [file, setFile] = useState<File | null>(null);
  const [result, setResult] = useState<{ runId: string; data: CompareResult } | null>(null);
  const [onlyDiffs, setOnlyDiffs] = useState(true);
  const action = useAction();
  const data = result?.runId === runId ? result.data : null;

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (!file) return action.setError("Choose your old app's salary report first.");
    const fd = new FormData();
    fd.append("file", file);
    const res = await action.run("compare", () => api.post<CompareResult>(`/payroll/runs/${runId}/compare`, fd));
    if (res.ok) setResult({ runId, data: res.value });
  }

  const unmatchedList = data && Array.isArray(data.unmatched) ? data.unmatched : [];
  const unmatchedCount = data ? (Array.isArray(data.unmatched) ? data.unmatched.length : data.unmatched) : 0;
  const rows = data ? data.rows.filter((r) => !onlyDiffs || r.diffPaise !== 0) : [];

  return (
    <Card title={t("payroll_compare")}>
      <p className="mb-3 text-sm text-slate-600">
        Running StaffMint alongside your old app this month? Upload the old app&apos;s salary report (Excel/CSV) to see every difference with a reason.
      </p>
      <form onSubmit={submit} className="flex flex-wrap items-end gap-3">
        <Field label="Old app's salary report" className="min-w-64">
          {(id) => (
            <Input
              id={id}
              type="file"
              accept=".xlsx,.xls,.csv"
              onChange={(e) => setFile(e.target.files?.[0] ?? null)}
              className="file:mr-3 file:rounded-md file:border-0 file:bg-mint-50 file:px-3 file:py-1 file:text-mint-700"
            />
          )}
        </Field>
        <Button type="submit" loading={action.busy === "compare"} disabled={!file}>
          Compare
        </Button>
      </form>
      {action.error && <Alert className="mt-3">{action.error}</Alert>}
      {data && (
        <div className="mt-4 space-y-3">
          <div className="flex flex-wrap items-center gap-2 text-sm">
            <Badge tone="mint">{data.matched} matched</Badge>
            <Badge tone={unmatchedCount ? "amber" : "slate"}>{unmatchedCount} not matched</Badge>
            <Badge tone="sky">{data.rows.filter((r) => r.diffPaise === 0).length} identical</Badge>
            <label className="ml-auto inline-flex items-center gap-2 text-sm text-slate-600">
              <input type="checkbox" className="accent-mint-500" checked={onlyDiffs} onChange={(e) => setOnlyDiffs(e.target.checked)} />
              Only show differences
            </label>
          </div>
          <Table>
            <thead>
              <tr>
                <Th>{t("employee")}</Th>
                <Th className="text-right">StaffMint</Th>
                <Th className="text-right">Old app</Th>
                <Th className="text-right">Difference</Th>
                <Th>Why</Th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {rows.map((r, i) => (
                <tr key={`${r.employeeName}-${i}`}>
                  <Td className="font-medium">{r.employeeName}</Td>
                  <Td className="text-right">{formatPaise(r.ours)}</Td>
                  <Td className="text-right">{formatPaise(r.theirs)}</Td>
                  <Td
                    className={cx(
                      "text-right font-semibold",
                      r.diffPaise == null ? "text-slate-400" : r.diffPaise > 0 ? "text-mint-700" : r.diffPaise < 0 ? "text-red-600" : "text-slate-500",
                    )}
                  >
                    {r.diffPaise == null ? "—" : `${r.diffPaise > 0 ? "+" : ""}${formatPaise(r.diffPaise)}`}
                  </Td>
                  <Td className="text-xs text-slate-600">
                    {r.reasons.length ? (
                      <ul className="list-disc pl-4">
                        {r.reasons.map((x, j) => (
                          <li key={j}>{x}</li>
                        ))}
                      </ul>
                    ) : (
                      "—"
                    )}
                  </Td>
                </tr>
              ))}
              {rows.length === 0 && (
                <tr>
                  <Td colSpan={5} className="text-center text-sm text-mint-800">
                    ✓ No differences — both apps agree.
                  </Td>
                </tr>
              )}
            </tbody>
          </Table>
          {unmatchedList.length > 0 && (
            <p className="text-xs text-slate-600">
              Not matched:{" "}
              {unmatchedList.map((u) => (typeof u === "string" ? u : u.employeeName || u.name || "?")).join(", ")}
            </p>
          )}
        </div>
      )}
    </Card>
  );
}
