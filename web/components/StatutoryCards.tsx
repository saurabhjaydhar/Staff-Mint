"use client";

import { useState, type FormEvent, type ReactNode } from "react";
import { useRole } from "@/components/AppShell";
import { useI18n, useToast } from "@/components/providers";
import { Alert, Button, Card, Checkbox, Field, Input, Loading, Modal, Select } from "@/components/ui";
import { useAction, useAsync } from "@/hooks/useAsync";
import { api } from "@/lib/api";
import type { Employee, EmployeeStatutory, StatutorySettings } from "@/lib/types";

const orNull = (v: string) => (v.trim() ? v.trim() : null);
const rupees = (paise: number) => (paise ? String(Math.round(paise / 100)) : "");

function Section({ title, example, on, onToggle, disabled, children }: { title: string; example: string; on: boolean; onToggle: (v: boolean) => void; disabled: boolean; children: ReactNode }) {
  return (
    <div className="rounded-lg p-3 ring-1 ring-slate-200">
      <Checkbox label={<span className="font-semibold">{title}</span>} checked={on} disabled={disabled} onChange={(e) => onToggle(e.target.checked)} />
      <p className="mt-1 rounded-md bg-slate-50 px-2 py-1.5 text-xs text-slate-600">{example}</p>
      {on && <div className="mt-3 grid gap-3 sm:grid-cols-2">{children}</div>}
    </div>
  );
}

/** Settings: PF / ESI / Professional Tax. Off for most small shops. */
export function StatutoryCard() {
  const { t } = useI18n();
  const data = useAsync(() => api.get<StatutorySettings>("/company/statutory"), "statutory");
  return (
    <Card title={t("statutory_title")}>
      {data.errorText && <Alert onRetry={data.reload}>{data.errorText}</Alert>}
      {data.data ? <StatutoryForm key={JSON.stringify(data.data)} initial={data.data} onSaved={data.setData} /> : data.loading && <Loading />}
    </Card>
  );
}

function StatutoryForm({ initial, onSaved }: { initial: StatutorySettings; onSaved: (s: StatutorySettings) => void }) {
  const { t } = useI18n();
  const toast = useToast();
  const { role } = useRole();
  const readOnly = role !== "owner";
  const action = useAction();
  const [pf, setPf] = useState(initial.pfEnabled);
  const [pfNumber, setPfNumber] = useState(initial.pfNumber ?? "");
  const [basic, setBasic] = useState(String(initial.basicPercent));
  const [esi, setEsi] = useState(initial.esiEnabled);
  const [esiNumber, setEsiNumber] = useState(initial.esiNumber ?? "");
  const [pt, setPt] = useState(initial.ptEnabled);
  const [ptState, setPtState] = useState(initial.ptState ?? "");
  const [ptAmount, setPtAmount] = useState(rupees(initial.ptMonthlyPaise));
  const [ptMin, setPtMin] = useState(rupees(initial.ptMinGrossPaise));

  async function submit(e: FormEvent) {
    e.preventDefault();
    const amount = Number(ptAmount || 0);
    const min = Number(ptMin || 0);
    if (pt && (!Number.isFinite(amount) || amount < 0 || amount > 2500)) return action.setError("Professional Tax: enter an amount up to ₹2,500");
    if (!Number.isFinite(min) || min < 0) return action.setError("Enter a valid minimum salary");
    const res = await action.run("save", () =>
      api.patch<StatutorySettings>("/company/statutory", {
        pfEnabled: pf,
        pfNumber: orNull(pfNumber),
        basicPercent: Number(basic),
        esiEnabled: esi,
        esiNumber: orNull(esiNumber),
        ptEnabled: pt,
        ptState: orNull(ptState),
        ptMonthlyPaise: Math.round(amount * 100),
        ptMinGrossPaise: Math.round(min * 100),
      }),
    );
    if (res.ok) {
      onSaved(res.value);
      toast("Saved — applies from the next salary you calculate");
    }
  }

  return (
    <form onSubmit={submit} className="space-y-3">
      <p className="text-sm text-slate-600">{t("statutory_intro")}</p>
      <Section title={t("pf_title")} example={t("pf_example")} on={pf} onToggle={setPf} disabled={readOnly}>
        <Field label={t("pf_number")}>{(id) => <Input id={id} value={pfNumber} disabled={readOnly} onChange={(e) => setPfNumber(e.target.value)} />}</Field>
        <Field label={t("basic_percent")}>
          {(id) => (
            <Select id={id} value={basic} disabled={readOnly} onChange={(e) => setBasic(e.target.value)}>
              {["40", "50", "60", "100"].map((v) => (
                <option key={v} value={v}>
                  {v}%
                </option>
              ))}
              {!["40", "50", "60", "100"].includes(basic) && <option value={basic}>{basic}%</option>}
            </Select>
          )}
        </Field>
      </Section>
      <Section title={t("esi_title")} example={t("esi_example")} on={esi} onToggle={setEsi} disabled={readOnly}>
        <Field label={t("esi_number")}>{(id) => <Input id={id} value={esiNumber} disabled={readOnly} onChange={(e) => setEsiNumber(e.target.value)} />}</Field>
      </Section>
      <Section title={t("pt_title")} example={t("pt_example")} on={pt} onToggle={setPt} disabled={readOnly}>
        <Field label={t("pt_state")}>{(id) => <Input id={id} value={ptState} disabled={readOnly} onChange={(e) => setPtState(e.target.value)} />}</Field>
        <Field label={t("pt_amount")}>{(id) => <Input id={id} inputMode="numeric" value={ptAmount} disabled={readOnly} onChange={(e) => setPtAmount(e.target.value)} />}</Field>
        <Field label={t("pt_min")}>{(id) => <Input id={id} inputMode="numeric" value={ptMin} disabled={readOnly} onChange={(e) => setPtMin(e.target.value)} />}</Field>
      </Section>
      {action.error && <Alert>{action.error}</Alert>}
      {!readOnly && (
        <Button type="submit" loading={action.busy === "save"}>
          {t("save")}
        </Button>
      )}
    </form>
  );
}

/** Staff list: Employee ID, UAN, ESIC, PAN and PF/ESI exemptions for one person. Owner only. */
export function SlipDetailsModal({ employee, onClose }: { employee: Employee | null; onClose: () => void }) {
  const { t } = useI18n();
  const detail = useAsync(() => api.get<Employee & { statutory?: EmployeeStatutory }>(`/employees/${employee!.id}`), employee ? `emp-statutory:${employee.id}` : null);
  return (
    <Modal open={!!employee} onClose={onClose} title={`${t("slip_details")} · ${employee?.name ?? ""}`}>
      <p className="mb-3 text-sm text-slate-600">{t("slip_details_hint")}</p>
      {detail.errorText && <Alert onRetry={detail.reload}>{detail.errorText}</Alert>}
      {employee && detail.data?.id === employee.id ? (
        <SlipDetailsForm employeeId={employee.id} initial={detail.data.statutory} onDone={onClose} />
      ) : (
        detail.loading && <Loading />
      )}
    </Modal>
  );
}

function SlipDetailsForm({ employeeId, initial, onDone }: { employeeId: string; initial?: EmployeeStatutory; onDone: () => void }) {
  const { t } = useI18n();
  const toast = useToast();
  const action = useAction();
  const [code, setCode] = useState(initial?.employeeCode ?? "");
  const [uan, setUan] = useState(initial?.uan ?? "");
  const [esic, setEsic] = useState(initial?.esicNumber ?? "");
  const [pan, setPan] = useState("");
  const [pfExempt, setPfExempt] = useState(!!initial?.pfExempt);
  const [esiExempt, setEsiExempt] = useState(!!initial?.esiExempt);

  async function submit(e: FormEvent) {
    e.preventDefault();
    const res = await action.run("save", () =>
      api.patch<EmployeeStatutory>(`/employees/${employeeId}/statutory`, {
        employeeCode: orNull(code),
        uan: orNull(uan),
        esicNumber: orNull(esic),
        // PAN only comes back masked, so it is sent only when typed again.
        ...(pan.trim() ? { pan: pan.trim() } : {}),
        pfExempt,
        esiExempt,
      }),
    );
    if (res.ok) {
      toast("Saved");
      onDone();
    }
  }

  return (
    <form onSubmit={submit} className="space-y-3">
      <div className="grid gap-3 sm:grid-cols-2">
        <Field label={t("employee_code")}>{(id) => <Input id={id} value={code} onChange={(e) => setCode(e.target.value)} />}</Field>
        <Field label={t("uan")}>{(id) => <Input id={id} inputMode="numeric" value={uan} onChange={(e) => setUan(e.target.value)} />}</Field>
        <Field label={t("esic")}>{(id) => <Input id={id} inputMode="numeric" value={esic} onChange={(e) => setEsic(e.target.value)} />}</Field>
        <Field label={t("pan")}>{(id) => <Input id={id} value={pan} placeholder={initial?.panMasked ?? ""} onChange={(e) => setPan(e.target.value.toUpperCase())} />}</Field>
      </div>
      <div className="flex flex-wrap gap-4">
        <Checkbox label={t("pf_exempt")} checked={pfExempt} onChange={(e) => setPfExempt(e.target.checked)} />
        <Checkbox label={t("esi_exempt")} checked={esiExempt} onChange={(e) => setEsiExempt(e.target.checked)} />
      </div>
      {action.error && <Alert>{action.error}</Alert>}
      <Button type="submit" loading={action.busy === "save"}>
        {t("save")}
      </Button>
    </form>
  );
}
