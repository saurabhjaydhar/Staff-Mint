"use client";

import Link from "next/link";
import { useMemo, useState, type FormEvent } from "react";
import { useRole } from "@/components/AppShell";
import { DocumentsModal } from "@/components/DocumentsModal";
import { SlipDetailsModal } from "@/components/StatutoryCards";
import { useI18n, useToast } from "@/components/providers";
import { Alert, Badge, Button, Card, EmptyState, Field, Input, Loading, Modal, PageHeader, Select, Table, Td, Th, cx } from "@/components/ui";
import { useAction, useAsync, useDebounced } from "@/hooks/useAsync";
import { api, errorMessage, isApiError } from "@/lib/api";
import { fill } from "@/lib/i18n";
import { formatPaise, paiseToRupeeInput, parseRupeesToPaise } from "@/lib/money";
import type { Branch, Employee, EmployeeInput, Shift, WageType } from "@/lib/types";

type RowEdit = { designation?: string; wageType?: WageType; rate?: string; shiftId?: string };

export default function StaffPage() {
  const { t } = useI18n();
  const toast = useToast();
  const { role } = useRole();
  const [status, setStatus] = useState<"active" | "inactive" | "all">("active");
  const [search, setSearch] = useState("");
  const [edits, setEdits] = useState<Record<string, RowEdit>>({});
  const [rowErrors, setRowErrors] = useState<Record<string, string>>({});
  const [effectiveFrom, setEffectiveFrom] = useState("");
  const [adding, setAdding] = useState(false);
  const [deactivating, setDeactivating] = useState<Employee | null>(null);
  const [slipFor, setSlipFor] = useState<Employee | null>(null);
  const [docsFor, setDocsFor] = useState<Employee | null>(null);
  const action = useAction();
  const q = useDebounced(search.trim());

  const employees = useAsync(
    () => api.get<Employee[]>("/employees", { status, search: q || undefined }),
    `employees:${status}:${q}`,
  );
  const refs = useAsync(async () => {
    const [branches, shifts] = await Promise.all([
      api.get<Branch[]>("/branches").catch(() => [] as Branch[]),
      api.get<Shift[]>("/shifts").catch(() => [] as Shift[]),
    ]);
    return { branches, shifts };
  }, "staff-refs");
  const shifts = refs.data?.shifts ?? [];
  const branches = refs.data?.branches ?? [];

  const list = useMemo(() => employees.data ?? [], [employees.data]);
  const changes = useMemo(() => computeChanges(list, edits), [list, edits]);
  const changedCount = Object.keys(changes.patches).length;

  function edit(id: string, patch: RowEdit) {
    setEdits((e) => ({ ...e, [id]: { ...e[id], ...patch } }));
  }

  async function saveAll() {
    if (Object.keys(changes.invalid).length) {
      setRowErrors(changes.invalid);
      return;
    }
    const ids = Object.keys(changes.patches);
    await action.run("save", async () => {
      const results = await Promise.allSettled(
        ids.map((id) => {
          const body: Record<string, unknown> = { ...changes.patches[id] };
          if (body.ratePaise !== undefined && effectiveFrom) body.effectiveFrom = effectiveFrom;
          return api.patch<Employee>(`/employees/${id}`, body);
        }),
      );
      const errs: Record<string, string> = {};
      const updated: Record<string, Employee> = {};
      results.forEach((r, i) => {
        if (r.status === "fulfilled") updated[ids[i]] = r.value;
        else errs[ids[i]] = errorMessage(r.reason);
      });
      employees.setData((prev) => (prev ?? []).map((e) => updated[e.id] ?? e));
      setEdits((prev) => {
        const next = { ...prev };
        for (const id of Object.keys(updated)) delete next[id];
        return next;
      });
      setRowErrors(errs);
      const ok = Object.keys(updated).length;
      const failed = Object.keys(errs).length;
      toast(failed ? `${ok} saved, ${failed} failed` : `${ok} employee${ok === 1 ? "" : "s"} updated`, failed ? "red" : "mint");
    });
  }

  async function invite(emp: Employee) {
    const res = await action.run(`invite:${emp.id}`, () => api.post<{ invitedAt: string }>(`/employees/${emp.id}/invite`));
    if (res.ok) {
      employees.setData((prev) => (prev ?? []).map((e) => (e.id === emp.id ? { ...e, invitedAt: res.value.invitedAt } : e)));
      toast(t("acc_invite_sent"));
    }
  }

  async function toggleManager(emp: Employee) {
    const toManager = emp.appRole !== "manager";
    if (!window.confirm(fill(t(toManager ? "make_manager_q" : "back_to_staff_q"), { name: emp.name }))) return;
    const res = await action.run(`role:${emp.id}`, () => api.post<Employee>(`/employees/${emp.id}/role`, { role: toManager ? "manager" : "employee" }));
    if (res.ok) {
      employees.setData((prev) => (prev ?? []).map((e) => (e.id === emp.id ? res.value : e)));
      toast(res.value.name);
    }
  }

  async function resetDevice(emp: Employee) {
    if (!window.confirm(`Reset the registered phone for ${emp.name}? They can then log in from a new phone.`)) return;
    const res = await action.run(`reset:${emp.id}`, () => api.post<Employee>(`/employees/${emp.id}/reset-device`));
    if (res.ok) {
      employees.setData((prev) => (prev ?? []).map((e) => (e.id === emp.id ? res.value : e)));
      toast("Device reset");
    }
  }

  return (
    <div className="space-y-5">
      <PageHeader
        title={t("nav_staff")}
        subtitle="Edit many people at once: change rates, wage type, designation or shift, then save all changes."
        actions={
          <>
            {role === "owner" && (
              <Link href="/import" className="text-sm font-medium text-mint-700 underline">
                Import from Excel
              </Link>
            )}
            <Button onClick={() => setAdding(true)}>+ Add employee</Button>
          </>
        }
      />

      <Card padded={false}>
        <div className="flex flex-wrap items-end gap-3 border-b border-slate-100 p-4">
          <Field label={t("search")} className="w-64">
            {(id) => <Input id={id} value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Name or phone" />}
          </Field>
          <Field label={t("status")} className="w-40">
            {(id) => (
              <Select id={id} value={status} onChange={(e) => setStatus(e.target.value as typeof status)}>
                <option value="active">Active</option>
                <option value="inactive">Inactive</option>
                <option value="all">All</option>
              </Select>
            )}
          </Field>
          <Field label="Rate changes effective from" hint="Optional — leave blank for the server default" className="w-56">
            {(id) => <Input id={id} type="date" value={effectiveFrom} onChange={(e) => setEffectiveFrom(e.target.value)} />}
          </Field>
          <div className="ml-auto flex items-center gap-2">
            {changedCount > 0 && (
              <Button variant="ghost" size="sm" onClick={() => { setEdits({}); setRowErrors({}); }}>
                Discard
              </Button>
            )}
            <Button onClick={saveAll} disabled={changedCount === 0} loading={action.busy === "save"}>
              {t("save")} {changedCount > 0 ? `${changedCount} changed row${changedCount === 1 ? "" : "s"}` : ""}
            </Button>
          </div>
        </div>
        {action.error && <Alert className="m-4">{action.error}</Alert>}
        {employees.errorText && <Alert className="m-4" onRetry={employees.reload}>{employees.errorText}</Alert>}
        {!employees.data && employees.loading ? (
          <Loading />
        ) : list.length === 0 ? (
          <EmptyState>No employees found. Add one or import your staff list.</EmptyState>
        ) : (
          <Table>
            <thead>
              <tr>
                <Th>{t("name")}</Th>
                <Th>Designation</Th>
                <Th>Wage type</Th>
                <Th>Rate (₹)</Th>
                <Th>Shift</Th>
                <Th>Device</Th>
                <Th className="text-right">{t("actions")}</Th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {list.map((emp) => {
                const e = edits[emp.id] ?? {};
                const dirty = !!changes.patches[emp.id];
                const err = rowErrors[emp.id] || changes.invalid[emp.id];
                const inactive = emp.status === "inactive";
                return (
                  <tr key={emp.id} className={cx(dirty && "bg-mint-50/60", inactive && "opacity-60")}>
                    <Td>
                      <div className="font-medium">{emp.name}</div>
                      <div className="text-xs text-slate-500">
                        {emp.phone}
                        {branches.length > 1 && emp.branchId && <> · {branches.find((b) => b.id === emp.branchId)?.name}</>}
                      </div>
                      {err && <div className="text-xs text-red-600">{err}</div>}
                    </Td>
                    <Td>
                      <Input
                        aria-label={`Designation for ${emp.name}`}
                        className="h-8 w-36 py-1"
                        value={e.designation ?? emp.designation ?? ""}
                        disabled={inactive}
                        onChange={(ev) => edit(emp.id, { designation: ev.target.value })}
                      />
                    </Td>
                    <Td>
                      <Select
                        aria-label={`Wage type for ${emp.name}`}
                        className="h-8 w-32 py-1"
                        value={e.wageType ?? emp.wageType}
                        disabled={inactive}
                        onChange={(ev) => edit(emp.id, { wageType: ev.target.value as WageType })}
                      >
                        <option value="monthly">Monthly</option>
                        <option value="daily">Daily</option>
                      </Select>
                    </Td>
                    <Td>
                      <Input
                        aria-label={`Rate for ${emp.name}`}
                        className="no-spin h-8 w-28 py-1 text-right"
                        inputMode="decimal"
                        value={e.rate ?? paiseToRupeeInput(emp.ratePaise)}
                        disabled={inactive}
                        invalid={!!changes.invalid[emp.id]}
                        onChange={(ev) => edit(emp.id, { rate: ev.target.value })}
                      />
                      <div className="mt-0.5 text-right text-[11px] text-slate-500">
                        {formatPaise(changes.patches[emp.id]?.ratePaise ?? emp.ratePaise)}/{(e.wageType ?? emp.wageType) === "daily" ? "day" : "month"}
                      </div>
                    </Td>
                    <Td>
                      <Select
                        aria-label={`Shift for ${emp.name}`}
                        className="h-8 w-48 py-1"
                        value={e.shiftId ?? emp.shiftId ?? ""}
                        disabled={inactive}
                        onChange={(ev) => edit(emp.id, { shiftId: ev.target.value })}
                      >
                        <option value="">Default</option>
                        {shifts.map((s) => (
                          <option key={s.id} value={s.id}>
                            {s.name} ({s.start}–{s.end})
                          </option>
                        ))}
                      </Select>
                    </Td>
                    <Td>
                      {emp.hasDevice ? <Badge tone="mint">Registered</Badge> : emp.linked === false && !inactive ? <Badge tone="amber">{t("acc_not_joined")}</Badge> : <Badge>Not yet</Badge>}
                      {inactive && <Badge className="ml-1">Inactive</Badge>}
                      {emp.appRole === "manager" && (
                        <Badge tone="sky" className="ml-1">
                          {t("manager")}
                        </Badge>
                      )}
                      {emp.verification === "verified" && (
                        <Badge tone="mint" className="ml-1">
                          {t("doc_verified")}
                        </Badge>
                      )}
                      {emp.verification === "needs_attention" && (
                        <Badge tone="amber" className="ml-1">
                          {t("doc_needs_look")}
                        </Badge>
                      )}
                    </Td>
                    <Td className="text-right whitespace-nowrap">
                      {emp.hasDevice && !inactive && (
                        <Button size="sm" variant="ghost" loading={action.busy === `reset:${emp.id}`} onClick={() => resetDevice(emp)}>
                          Reset device
                        </Button>
                      )}
                      {emp.linked === false && !inactive && (
                        <Button size="sm" variant="ghost" data-invite={emp.id} loading={action.busy === `invite:${emp.id}`} onClick={() => invite(emp)}>
                          {emp.invitedAt ? t("acc_resend") : t("acc_invite")}
                        </Button>
                      )}
                      {role === "owner" && !inactive && (
                        <Button size="sm" variant="ghost" data-role={emp.id} loading={action.busy === `role:${emp.id}`} onClick={() => toggleManager(emp)}>
                          {emp.appRole === "manager" ? t("back_to_staff") : t("make_manager")}
                        </Button>
                      )}
                      {role === "owner" && (
                        <Button size="sm" variant="ghost" data-docs={emp.id} onClick={() => setDocsFor(emp)}>
                          {t("docs_button")}
                        </Button>
                      )}
                      {role === "owner" && (
                        <Button size="sm" variant="ghost" onClick={() => setSlipFor(emp)}>
                          {t("slip_details")}
                        </Button>
                      )}
                      {!inactive && (
                        <Button size="sm" variant="ghost" className="text-red-600" onClick={() => setDeactivating(emp)}>
                          Deactivate
                        </Button>
                      )}
                    </Td>
                  </tr>
                );
              })}
            </tbody>
          </Table>
        )}
      </Card>

      <AddEmployeeModal
        open={adding}
        onClose={() => setAdding(false)}
        branches={branches}
        shifts={shifts}
        onCreated={(emp) => {
          setAdding(false);
          employees.setData((prev) => [emp, ...(prev ?? [])]);
          toast(`${emp.name} added`);
        }}
      />
      <SlipDetailsModal employee={slipFor} onClose={() => setSlipFor(null)} />
      <DocumentsModal employee={docsFor} onClose={() => setDocsFor(null)} onChanged={employees.reload} />
      <DeactivateModal
        employee={deactivating}
        onClose={() => setDeactivating(null)}
        onDone={(emp) => {
          setDeactivating(null);
          employees.setData((prev) => (status === "active" ? (prev ?? []).filter((e) => e.id !== emp.id) : (prev ?? []).map((e) => (e.id === emp.id ? emp : e))));
          toast(`${emp.name} deactivated`);
        }}
      />
    </div>
  );
}

function computeChanges(list: Employee[], edits: Record<string, RowEdit>) {
  const patches: Record<string, Partial<Pick<Employee, "designation" | "wageType" | "ratePaise" | "shiftId">>> = {};
  const invalid: Record<string, string> = {};
  for (const emp of list) {
    const e = edits[emp.id];
    if (!e) continue;
    const p: (typeof patches)[string] = {};
    if (e.designation !== undefined && e.designation.trim() !== (emp.designation ?? "")) p.designation = e.designation.trim();
    if (e.wageType !== undefined && e.wageType !== emp.wageType) p.wageType = e.wageType;
    if (e.shiftId !== undefined && e.shiftId !== (emp.shiftId ?? "") && e.shiftId) p.shiftId = e.shiftId;
    if (e.rate !== undefined) {
      const paise = parseRupeesToPaise(e.rate);
      if (paise === null) invalid[emp.id] = "Enter a valid amount, e.g. 15000 or 15k";
      else if (paise !== emp.ratePaise) p.ratePaise = paise;
    }
    if (Object.keys(p).length) patches[emp.id] = p;
  }
  return { patches, invalid };
}

function AddEmployeeModal({
  open,
  onClose,
  onCreated,
  branches,
  shifts,
}: {
  open: boolean;
  onClose: () => void;
  onCreated: (e: Employee) => void;
  branches: Branch[];
  shifts: Shift[];
}) {
  const empty = { name: "", phone: "", wageType: "monthly" as WageType, rate: "", designation: "", branchId: "", shiftId: "", joiningDate: "" };
  const [form, setForm] = useState(empty);
  const action = useAction();
  const [planLimit, setPlanLimit] = useState(false);
  const set = <K extends keyof typeof form>(k: K, v: (typeof form)[K]) => setForm((f) => ({ ...f, [k]: v }));

  async function submit(e: FormEvent) {
    e.preventDefault();
    setPlanLimit(false);
    if (!form.name.trim() || form.phone.replace(/\D/g, "").length < 10) {
      return action.setError("Name and a valid 10-digit phone are required.");
    }
    const ratePaise = form.rate ? parseRupeesToPaise(form.rate) : undefined;
    if (ratePaise === null) return action.setError("Enter a valid salary amount.");
    const body: EmployeeInput = {
      name: form.name.trim(),
      phone: form.phone.trim(),
      wageType: form.wageType,
      ...(ratePaise !== undefined ? { ratePaise } : {}),
      ...(form.designation.trim() ? { designation: form.designation.trim() } : {}),
      ...(form.branchId ? { branchId: form.branchId } : {}),
      ...(form.shiftId ? { shiftId: form.shiftId } : {}),
      ...(form.joiningDate ? { joiningDate: form.joiningDate } : {}),
    };
    const res = await action.run("add", () => api.post<Employee>("/employees", body));
    if (res.ok) {
      setForm(empty);
      onCreated(res.value);
    } else if (isApiError(res.error) && res.error.code === "PLAN_LIMIT") {
      setPlanLimit(true);
    }
  }

  return (
    <Modal open={open} onClose={onClose} title="Add employee">
      <form onSubmit={submit} className="space-y-3">
        <div className="grid gap-3 sm:grid-cols-2">
          <Field label="Name">{(id) => <Input id={id} value={form.name} onChange={(e) => set("name", e.target.value)} autoFocus />}</Field>
          <Field label="Phone">{(id) => <Input id={id} inputMode="tel" value={form.phone} onChange={(e) => set("phone", e.target.value)} />}</Field>
          <Field label="Wage type">
            {(id) => (
              <Select id={id} value={form.wageType} onChange={(e) => set("wageType", e.target.value as WageType)}>
                <option value="monthly">Monthly</option>
                <option value="daily">Daily</option>
              </Select>
            )}
          </Field>
          <Field label={form.wageType === "daily" ? "Rate per day (₹)" : "Monthly salary (₹)"}>
            {(id) => <Input id={id} inputMode="decimal" value={form.rate} onChange={(e) => set("rate", e.target.value)} placeholder="15000" />}
          </Field>
          <Field label="Designation">{(id) => <Input id={id} value={form.designation} onChange={(e) => set("designation", e.target.value)} />}</Field>
          <Field label="Joining date">{(id) => <Input id={id} type="date" value={form.joiningDate} onChange={(e) => set("joiningDate", e.target.value)} />}</Field>
          {branches.length > 0 && (
            <Field label="Branch">
              {(id) => (
                <Select id={id} value={form.branchId} onChange={(e) => set("branchId", e.target.value)}>
                  <option value="">Default</option>
                  {branches.map((b) => (
                    <option key={b.id} value={b.id}>
                      {b.name}
                    </option>
                  ))}
                </Select>
              )}
            </Field>
          )}
          {shifts.length > 0 && (
            <Field label="Shift">
              {(id) => (
                <Select id={id} value={form.shiftId} onChange={(e) => set("shiftId", e.target.value)}>
                  <option value="">Default</option>
                  {shifts.map((s) => (
                    <option key={s.id} value={s.id}>
                      {s.name}
                    </option>
                  ))}
                </Select>
              )}
            </Field>
          )}
        </div>
        {action.error && (
          <Alert>
            {action.error}
            {planLimit && (
              <>
                {" "}
                <Link href="/billing" className="font-medium underline">
                  Upgrade plan
                </Link>
              </>
            )}
          </Alert>
        )}
        <div className="flex justify-end gap-2 pt-2">
          <Button variant="secondary" onClick={onClose}>
            Cancel
          </Button>
          <Button type="submit" loading={action.busy === "add"}>
            Add employee
          </Button>
        </div>
      </form>
    </Modal>
  );
}

function DeactivateModal({ employee, onClose, onDone }: { employee: Employee | null; onClose: () => void; onDone: (e: Employee) => void }) {
  const [reason, setReason] = useState("");
  const action = useAction();
  return (
    <Modal
      open={!!employee}
      onClose={onClose}
      title={`Deactivate ${employee?.name ?? ""}`}
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>
            Cancel
          </Button>
          <Button
            variant="danger"
            loading={action.busy === "deactivate"}
            onClick={async () => {
              if (!employee) return;
              const res = await action.run("deactivate", () =>
                api.post<Employee>(`/employees/${employee.id}/deactivate`, reason.trim() ? { reason: reason.trim() } : {}),
              );
              if (res.ok) {
                setReason("");
                onDone(res.value);
              }
            }}
          >
            Deactivate
          </Button>
        </>
      }
    >
      <p className="mb-3 text-sm text-slate-600">They will no longer be able to check in. Past attendance and salary records are kept.</p>
      <Field label="Reason (optional)">{(id) => <Input id={id} value={reason} onChange={(e) => setReason(e.target.value)} placeholder="Left the job" />}</Field>
      {action.error && <Alert className="mt-3">{action.error}</Alert>}
    </Modal>
  );
}
