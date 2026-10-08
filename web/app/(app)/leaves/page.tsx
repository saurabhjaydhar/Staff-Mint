"use client";

import { useState, type FormEvent } from "react";
import { EmployeeSelect, useEmployees } from "@/components/EmployeeSelect";
import { useI18n, useToast } from "@/components/providers";
import { Alert, Badge, Button, Card, Checkbox, EmptyState, Field, Input, Loading, Modal, PageHeader, Select, Table, Td, Th, type Tone } from "@/components/ui";
import { useAction, useAsync } from "@/hooks/useAsync";
import { api } from "@/lib/api";
import { formatDate, todayStr } from "@/lib/format";
import type { Leave, LeaveType } from "@/lib/types";

const STATUS_TONE: Record<Leave["status"], Tone> = { pending: "amber", approved: "mint", rejected: "red", cancelled: "slate" };

export default function LeavesPage() {
  const { t } = useI18n();
  const toast = useToast();
  const [status, setStatus] = useState<"pending" | "approved" | "rejected" | "cancelled" | "">("pending");
  const [adding, setAdding] = useState(false);
  const [deciding, setDeciding] = useState<{ leave: Leave; decision: "approved" | "rejected" } | null>(null);
  const leaves = useAsync(() => api.get<Leave[]>("/leaves", { status: status || undefined }), `leaves:${status}`);

  return (
    <div className="space-y-5">
      <PageHeader title={t("nav_leaves")} actions={<Button onClick={() => setAdding(true)}>+ Add leave</Button>} />
      <Card padded={false}>
        <div className="flex flex-wrap items-end gap-3 border-b border-slate-100 p-4">
          <Field label={t("status")} className="w-44">
            {(id) => (
              <Select id={id} value={status} onChange={(e) => setStatus(e.target.value as typeof status)}>
                <option value="pending">Pending</option>
                <option value="approved">Approved</option>
                <option value="rejected">Rejected</option>
                <option value="cancelled">Cancelled</option>
                <option value="">All</option>
              </Select>
            )}
          </Field>
        </div>
        {leaves.errorText && <Alert className="m-4" onRetry={leaves.reload}>{leaves.errorText}</Alert>}
        {!leaves.data && leaves.loading ? (
          <Loading />
        ) : !leaves.data?.length ? (
          <EmptyState>{status === "pending" ? "No pending leave requests." : t("none")}</EmptyState>
        ) : (
          <Table>
            <thead>
              <tr>
                <Th>{t("employee")}</Th>
                <Th>Type</Th>
                <Th>Dates</Th>
                <Th className="text-right">Days</Th>
                <Th>{t("reason")}</Th>
                <Th>{t("status")}</Th>
                <Th className="text-right">{t("actions")}</Th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {leaves.data.map((l) => (
                <tr key={l.id}>
                  <Td className="font-medium">{l.employeeName}</Td>
                  <Td className="capitalize">{l.type}</Td>
                  <Td>
                    {formatDate(l.from)}
                    {l.to !== l.from && <> → {formatDate(l.to)}</>}
                  </Td>
                  <Td className="text-right">{l.halfDay ? "½" : l.days}</Td>
                  <Td className="max-w-56 text-xs text-slate-600">
                    {l.reason || "—"}
                    {l.note && <div className="text-slate-400">Note: {l.note}</div>}
                  </Td>
                  <Td>
                    <Badge tone={STATUS_TONE[l.status]}>{l.status}</Badge>
                  </Td>
                  <Td className="text-right whitespace-nowrap">
                    {l.status === "pending" && (
                      <>
                        <Button size="sm" onClick={() => setDeciding({ leave: l, decision: "approved" })}>
                          {t("approve")}
                        </Button>{" "}
                        <Button size="sm" variant="secondary" onClick={() => setDeciding({ leave: l, decision: "rejected" })}>
                          {t("reject")}
                        </Button>
                      </>
                    )}
                  </Td>
                </tr>
              ))}
            </tbody>
          </Table>
        )}
      </Card>

      <DecisionModal
        target={deciding}
        onClose={() => setDeciding(null)}
        onDone={(l) => {
          setDeciding(null);
          toast(`Leave ${l.status}`);
          leaves.reload();
        }}
      />
      <AddLeaveModal
        open={adding}
        onClose={() => setAdding(false)}
        onDone={() => {
          setAdding(false);
          toast("Leave added");
          leaves.reload();
        }}
      />
    </div>
  );
}

function DecisionModal({
  target,
  onClose,
  onDone,
}: {
  target: { leave: Leave; decision: "approved" | "rejected" } | null;
  onClose: () => void;
  onDone: (l: Leave) => void;
}) {
  const [note, setNote] = useState("");
  const action = useAction();
  const approve = target?.decision === "approved";
  return (
    <Modal
      open={!!target}
      onClose={onClose}
      title={approve ? "Approve leave" : "Reject leave"}
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>
            Cancel
          </Button>
          <Button
            variant={approve ? "primary" : "danger"}
            loading={action.busy === "decide"}
            onClick={async () => {
              if (!target) return;
              const res = await action.run("decide", () =>
                api.post<Leave>(`/leaves/${target.leave.id}/decision`, { decision: target.decision, ...(note.trim() ? { note: note.trim() } : {}) }),
              );
              if (res.ok) {
                setNote("");
                onDone(res.value);
              }
            }}
          >
            {approve ? "Approve" : "Reject"}
          </Button>
        </>
      }
    >
      {target && (
        <p className="mb-3 text-sm text-slate-600">
          {target.leave.employeeName} · {target.leave.type} · {formatDate(target.leave.from)}
          {target.leave.to !== target.leave.from && <> → {formatDate(target.leave.to)}</>}
        </p>
      )}
      <Field label="Note to employee (optional)">{(id) => <Input id={id} value={note} onChange={(e) => setNote(e.target.value)} />}</Field>
      {action.error && <Alert className="mt-3">{action.error}</Alert>}
    </Modal>
  );
}

function AddLeaveModal({ open, onClose, onDone }: { open: boolean; onClose: () => void; onDone: () => void }) {
  const employees = useEmployees();
  const [form, setForm] = useState(() => ({ employeeId: "", type: "paid" as LeaveType, from: todayStr(), to: todayStr(), halfDay: false, reason: "" }));
  const action = useAction();
  const set = <K extends keyof typeof form>(k: K, v: (typeof form)[K]) => setForm((f) => ({ ...f, [k]: v }));

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (!form.employeeId) return action.setError("Choose an employee.");
    if (form.to < form.from) return action.setError("End date is before start date.");
    const res = await action.run("add", () =>
      api.post<Leave>("/leaves", {
        employeeId: form.employeeId,
        type: form.type,
        from: form.from,
        to: form.halfDay ? form.from : form.to,
        halfDay: form.halfDay,
        ...(form.reason.trim() ? { reason: form.reason.trim() } : {}),
      }),
    );
    if (res.ok) onDone();
  }

  return (
    <Modal open={open} onClose={onClose} title="Add leave for an employee">
      <form onSubmit={submit} className="space-y-3">
        <Field label="Employee">
          {(id) => <EmployeeSelect id={id} employees={employees.data} value={form.employeeId} onChange={(e) => set("employeeId", e.target.value)} />}
        </Field>
        <div className="grid gap-3 sm:grid-cols-3">
          <Field label="Type">
            {(id) => (
              <Select id={id} value={form.type} onChange={(e) => set("type", e.target.value as LeaveType)}>
                <option value="paid">Paid</option>
                <option value="sick">Sick</option>
                <option value="unpaid">Unpaid</option>
              </Select>
            )}
          </Field>
          <Field label="From">{(id) => <Input id={id} type="date" value={form.from} onChange={(e) => set("from", e.target.value)} />}</Field>
          <Field label="To">
            {(id) => <Input id={id} type="date" value={form.halfDay ? form.from : form.to} disabled={form.halfDay} onChange={(e) => set("to", e.target.value)} />}
          </Field>
        </div>
        <Checkbox label="Half day" checked={form.halfDay} onChange={(e) => set("halfDay", e.target.checked)} />
        <Field label="Reason (optional)">{(id) => <Input id={id} value={form.reason} onChange={(e) => set("reason", e.target.value)} />}</Field>
        {action.error && <Alert>{action.error}</Alert>}
        <div className="flex justify-end gap-2">
          <Button variant="secondary" onClick={onClose}>
            Cancel
          </Button>
          <Button type="submit" loading={action.busy === "add"}>
            Add leave
          </Button>
        </div>
      </form>
    </Modal>
  );
}
