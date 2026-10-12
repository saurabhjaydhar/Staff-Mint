"use client";

import { useState, type FormEvent } from "react";
import { EmployeeSelect, useEmployees } from "@/components/EmployeeSelect";
import { useI18n, useToast } from "@/components/providers";
import { Alert, Badge, Button, Card, EmptyState, Field, Input, Loading, Modal, PageHeader, Segmented, Select, Table, Td, Th } from "@/components/ui";
import { useAction, useAsync } from "@/hooks/useAsync";
import { api } from "@/lib/api";
import { fill } from "@/lib/i18n";
import { currentMonth, formatDate, formatMonth, todayStr } from "@/lib/format";
import { formatPaise, parseRupeesToPaise } from "@/lib/money";
import type { Adjustment, Advance } from "@/lib/types";

export default function AdvancesPage() {
  const { t } = useI18n();
  const [tab, setTab] = useState<"advances" | "adjustments">("advances");
  return (
    <div className="space-y-5">
      <PageHeader
        title={t("nav_advances")}
        subtitle="Advances (udhaar) are recovered from salary automatically. Adjustments add a bonus or deduction to one month."
        actions={
          <Segmented
            value={tab}
            onChange={setTab}
            options={[
              { value: "advances", label: "Advances" },
              { value: "adjustments", label: "Bonus / deductions" },
            ]}
          />
        }
      />
      {tab === "advances" ? <AdvancesTab /> : <AdjustmentsTab />}
    </div>
  );
}

function AdvancesTab() {
  const { t } = useI18n();
  const toast = useToast();
  const [status, setStatus] = useState<"active" | "closed" | "">("active");
  const [adding, setAdding] = useState(false);
  const [skipping, setSkipping] = useState<Advance | null>(null);
  const advances = useAsync(() => api.get<Advance[]>("/advances", { status: status || undefined }), `advances:${status}`);
  const totalBalance = (advances.data ?? []).reduce((s, a) => s + (a.balancePaise || 0), 0);

  return (
    <>
      <Card
        padded={false}
        title={
          <span>
            Advances <span className="ml-2 text-sm font-normal text-slate-500">Outstanding: {formatPaise(totalBalance)}</span>
          </span>
        }
        actions={
          <>
            <Select aria-label="Status" className="h-8 w-32 py-1" value={status} onChange={(e) => setStatus(e.target.value as typeof status)}>
              <option value="active">Active</option>
              <option value="closed">Closed</option>
              <option value="">All</option>
            </Select>
            <Button size="sm" onClick={() => setAdding(true)}>
              + Give advance
            </Button>
          </>
        }
      >
        {advances.errorText && <Alert className="m-4" onRetry={advances.reload}>{advances.errorText}</Alert>}
        {!advances.data && advances.loading ? (
          <Loading />
        ) : !advances.data?.length ? (
          <EmptyState>{t("none")}</EmptyState>
        ) : (
          <Table>
            <thead>
              <tr>
                <Th>{t("employee")}</Th>
                <Th>{t("date")}</Th>
                <Th className="text-right">{t("amount")}</Th>
                <Th>Recovery</Th>
                <Th className="text-right">Repaid</Th>
                <Th className="text-right">Balance</Th>
                <Th>{t("status")}</Th>
                <Th className="text-right">{t("actions")}</Th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {advances.data.map((a) => (
                <tr key={a.id}>
                  <Td>
                    <div className="font-medium">{a.employeeName}</div>
                    {a.note && <div className="text-xs text-slate-500">{a.note}</div>}
                  </Td>
                  <Td>{formatDate(a.date)}</Td>
                  <Td className="text-right">{formatPaise(a.amountPaise)}</Td>
                  <Td className="text-xs">
                    {a.mode === "full_next" ? "Full, next salary" : `${a.installments} × ${formatPaise(a.installmentPaise)}`}
                    {a.skipMonths.length > 0 && <div className="text-slate-500">Skipped: {a.skipMonths.map(formatMonth).join(", ")}</div>}
                  </Td>
                  <Td className="text-right">{formatPaise(a.repaidPaise)}</Td>
                  <Td className="text-right font-semibold">{formatPaise(a.balancePaise)}</Td>
                  <Td>
                    <Badge tone={a.status === "active" ? "amber" : "mint"}>{a.status}</Badge>
                  </Td>
                  <Td className="text-right">
                    {a.status === "active" && (
                      <Button size="sm" variant="ghost" onClick={() => setSkipping(a)}>
                        Skip a month
                      </Button>
                    )}
                  </Td>
                </tr>
              ))}
            </tbody>
          </Table>
        )}
      </Card>
      <AddAdvanceModal
        open={adding}
        onClose={() => setAdding(false)}
        onDone={() => {
          setAdding(false);
          toast("Advance recorded");
          advances.reload();
        }}
      />
      <SkipModal
        advance={skipping}
        onClose={() => setSkipping(null)}
        onDone={() => {
          setSkipping(null);
          toast("Recovery skipped for that month");
          advances.reload();
        }}
      />
    </>
  );
}

function AddAdvanceModal({ open, onClose, onDone }: { open: boolean; onClose: () => void; onDone: () => void }) {
  const { t } = useI18n();
  const employees = useEmployees();
  const [form, setForm] = useState(() => ({
    employeeId: "",
    amount: "",
    date: todayStr(),
    mode: "installments" as Advance["mode"],
    installments: "3",
    note: "",
  }));
  const action = useAction();
  const set = <K extends keyof typeof form>(k: K, v: (typeof form)[K]) => setForm((f) => ({ ...f, [k]: v }));
  const paise = parseRupeesToPaise(form.amount);
  const n = Math.max(1, Math.floor(Number(form.installments) || 1));
  const emp = employees.data?.find((e) => e.id === form.employeeId);
  const cut = paise ? (form.mode === "installments" ? Math.round(paise / n) : paise) : 0;
  const first = emp?.name.split(" ")[0] ?? "";
  // Shows the effect on the next salary before saving.
  const preview = !emp || !cut
    ? null
    : emp.wageType === "daily" || !emp.ratePaise
      ? fill(t("advance_cut_preview"), { name: first, cut: formatPaise(cut) })
      : fill(t("advance_preview"), { name: first, after: formatPaise(Math.max(0, emp.ratePaise - cut)), before: formatPaise(emp.ratePaise) });

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (!form.employeeId) return action.setError("Choose an employee.");
    if (!paise) return action.setError("Enter a valid amount.");
    const res = await action.run("add", () =>
      api.post<Advance>("/advances", {
        employeeId: form.employeeId,
        amountPaise: paise,
        date: form.date,
        mode: form.mode,
        ...(form.mode === "installments" ? { installments: n } : {}),
        ...(form.note.trim() ? { note: form.note.trim() } : {}),
      }),
    );
    if (res.ok) onDone();
  }

  return (
    <Modal open={open} onClose={onClose} title="Give advance">
      <form onSubmit={submit} className="space-y-3">
        <Field label="Employee">
          {(id) => <EmployeeSelect id={id} employees={employees.data} value={form.employeeId} onChange={(e) => set("employeeId", e.target.value)} />}
        </Field>
        <div className="grid gap-3 sm:grid-cols-2">
          <Field label="Amount (₹)" hint={paise ? formatPaise(paise) : undefined}>
            {(id) => <Input id={id} inputMode="decimal" value={form.amount} onChange={(e) => set("amount", e.target.value)} placeholder="5000" />}
          </Field>
          <Field label="Date">{(id) => <Input id={id} type="date" value={form.date} onChange={(e) => set("date", e.target.value)} />}</Field>
          <Field label="Recover">
            {(id) => (
              <Select id={id} value={form.mode} onChange={(e) => set("mode", e.target.value as Advance["mode"])}>
                <option value="installments">In monthly installments</option>
                <option value="full_next">Fully from next salary</option>
              </Select>
            )}
          </Field>
          {form.mode === "installments" && (
            <Field label="Installments" hint={paise ? `≈ ${formatPaise(Math.round(paise / n))} per month` : undefined}>
              {(id) => <Input id={id} type="number" min={1} max={24} value={form.installments} onChange={(e) => set("installments", e.target.value)} />}
            </Field>
          )}
        </div>
        <Field label="Note (optional)">{(id) => <Input id={id} value={form.note} onChange={(e) => set("note", e.target.value)} />}</Field>
        {preview && (
          <p className="rounded-lg bg-amber-50 px-3 py-2 text-sm font-medium text-amber-900" data-testid="advance-preview">
            {preview}
          </p>
        )}
        {action.error && <Alert>{action.error}</Alert>}
        <div className="flex justify-end gap-2">
          <Button variant="secondary" onClick={onClose}>
            Cancel
          </Button>
          <Button type="submit" loading={action.busy === "add"}>
            Save advance
          </Button>
        </div>
      </form>
    </Modal>
  );
}

function SkipModal({ advance, onClose, onDone }: { advance: Advance | null; onClose: () => void; onDone: () => void }) {
  const [month, setMonth] = useState(() => currentMonth());
  const action = useAction();
  return (
    <Modal
      open={!!advance}
      onClose={onClose}
      title="Skip recovery for a month"
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>
            Cancel
          </Button>
          <Button
            loading={action.busy === "skip"}
            onClick={async () => {
              if (!advance) return;
              const res = await action.run("skip", () => api.post<Advance>(`/advances/${advance.id}/skip`, { month }));
              if (res.ok) onDone();
            }}
          >
            Skip month
          </Button>
        </>
      }
    >
      <p className="mb-3 text-sm text-slate-600">
        No installment will be deducted from {advance?.employeeName}&apos;s salary for this month.
      </p>
      <Field label="Month">{(id) => <Input id={id} type="month" value={month} onChange={(e) => setMonth(e.target.value)} />}</Field>
      {action.error && <Alert className="mt-3">{action.error}</Alert>}
    </Modal>
  );
}

function AdjustmentsTab() {
  const { t } = useI18n();
  const toast = useToast();
  const [month, setMonth] = useState(() => currentMonth());
  const adjustments = useAsync(() => api.get<Adjustment[]>("/adjustments", { month }), `adjustments:${month}`);
  const employees = useEmployees();
  const [form, setForm] = useState({ employeeId: "", type: "bonus" as Adjustment["type"], amount: "", note: "" });
  const action = useAction();
  const set = <K extends keyof typeof form>(k: K, v: (typeof form)[K]) => setForm((f) => ({ ...f, [k]: v }));

  async function add(e: FormEvent) {
    e.preventDefault();
    const paise = parseRupeesToPaise(form.amount);
    if (!form.employeeId) return action.setError("Choose an employee.");
    if (!paise) return action.setError("Enter a valid amount.");
    const res = await action.run("add", () =>
      api.post<Adjustment>("/adjustments", {
        employeeId: form.employeeId,
        month,
        type: form.type,
        amountPaise: paise,
        ...(form.note.trim() ? { note: form.note.trim() } : {}),
      }),
    );
    if (res.ok) {
      setForm({ employeeId: "", type: form.type, amount: "", note: "" });
      toast("Adjustment added — recompute the salary draft to include it");
      adjustments.reload();
    }
  }

  async function remove(a: Adjustment) {
    if (!window.confirm(`Delete ${a.type} of ${formatPaise(a.amountPaise)} for ${a.employeeName}?`)) return;
    const res = await action.run(`del:${a.id}`, () => api.delete(`/adjustments/${a.id}`));
    if (res.ok) {
      adjustments.setData((prev) => (prev ?? []).filter((x) => x.id !== a.id));
      toast("Adjustment deleted");
    }
  }

  return (
    <div className="space-y-4">
      <Card title="Add bonus or deduction">
        <form onSubmit={add} className="grid items-end gap-3 md:grid-cols-[10rem_1fr_9rem_9rem_1fr_auto]">
          <Field label={t("month")}>{(id) => <Input id={id} type="month" value={month} onChange={(e) => e.target.value && setMonth(e.target.value)} />}</Field>
          <Field label={t("employee")}>
            {(id) => <EmployeeSelect id={id} employees={employees.data} value={form.employeeId} onChange={(e) => set("employeeId", e.target.value)} />}
          </Field>
          <Field label="Type">
            {(id) => (
              <Select id={id} value={form.type} onChange={(e) => set("type", e.target.value as Adjustment["type"])}>
                <option value="bonus">Bonus (+)</option>
                <option value="deduction">Deduction (−)</option>
              </Select>
            )}
          </Field>
          <Field label="Amount (₹)">{(id) => <Input id={id} inputMode="decimal" value={form.amount} onChange={(e) => set("amount", e.target.value)} />}</Field>
          <Field label={t("note")}>{(id) => <Input id={id} value={form.note} onChange={(e) => set("note", e.target.value)} placeholder="Diwali bonus" />}</Field>
          <Button type="submit" loading={action.busy === "add"}>
            {t("add")}
          </Button>
        </form>
        {action.error && <Alert className="mt-3">{action.error}</Alert>}
      </Card>
      <Card title={`Adjustments · ${formatMonth(month)}`} padded={false}>
        {adjustments.errorText && <Alert className="m-4" onRetry={adjustments.reload}>{adjustments.errorText}</Alert>}
        {!adjustments.data && adjustments.loading ? (
          <Loading />
        ) : !adjustments.data?.length ? (
          <EmptyState>{t("none")}</EmptyState>
        ) : (
          <Table>
            <thead>
              <tr>
                <Th>{t("employee")}</Th>
                <Th>Type</Th>
                <Th className="text-right">{t("amount")}</Th>
                <Th>{t("note")}</Th>
                <Th className="text-right">{t("actions")}</Th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {adjustments.data.map((a) => (
                <tr key={a.id}>
                  <Td className="font-medium">{a.employeeName}</Td>
                  <Td>
                    <Badge tone={a.type === "bonus" ? "mint" : "red"}>{a.type}</Badge>
                  </Td>
                  <Td className="text-right">
                    {a.type === "deduction" ? "-" : "+"}
                    {formatPaise(a.amountPaise)}
                  </Td>
                  <Td className="text-xs text-slate-600">{a.note || "—"}</Td>
                  <Td className="text-right">
                    <Button size="sm" variant="ghost" className="text-red-600" loading={action.busy === `del:${a.id}`} onClick={() => remove(a)}>
                      {t("delete")}
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
