"use client";

import { useState, type FormEvent } from "react";
import { AccountantsCard, CloseBusinessCard, OwnersCard } from "@/components/AccountCards";
import { useAuth, useI18n, useToast } from "@/components/providers";
import { Alert, Button, Card, Checkbox, EmptyState, Field, Input, Loading, PageHeader, Select, Table, Td, Th } from "@/components/ui";
import { useAction, useAsync } from "@/hooks/useAsync";
import { api } from "@/lib/api";
import { formatDate, WEEKDAYS_EN, WEEKDAYS_HI } from "@/lib/format";
import type { Branch, Company, CompanySettings, Holiday, Shift } from "@/lib/types";

export default function SettingsPage() {
  const { t } = useI18n();
  const company = useAsync(() => api.get<Company>("/company"), "company");
  const [rulesVersion, setRulesVersion] = useState(0);

  return (
    <div className="space-y-6">
      <PageHeader title={t("nav_settings")} subtitle="Every default can be changed here. Changes apply to future attendance and salary calculations." />
      {company.errorText && <Alert onRetry={company.reload}>{company.errorText}</Alert>}
      {!company.data ? (
        company.loading && <Loading />
      ) : (
        <>
          <CompanyForm key={`c-${company.data.id}`} company={company.data} onSaved={company.setData} />
          <div className="grid gap-6 xl:grid-cols-[3fr_2fr]">
            <SettingsForm
              key={`s-${company.data.id}`}
              settings={company.data.settings}
              onSaved={(c) => {
                company.setData(c);
                setRulesVersion((v) => v + 1);
              }}
            />
            <RulesCard version={rulesVersion} />
          </div>
        </>
      )}
      <HolidaysCard />
      <ShiftsCard />
      <BranchesCard />
      <OwnersCard />
      <AccountantsCard />
      <CloseBusinessCard />
    </div>
  );
}

const BUSINESS_TYPES = ["shop", "restaurant", "clinic", "salon", "office", "factory", "other"];

function CompanyForm({ company, onSaved }: { company: Company; onSaved: (c: Company) => void }) {
  const toast = useToast();
  const { refreshMe } = useAuth();
  const [form, setForm] = useState({
    name: company.name,
    businessType: company.businessType,
    lat: String(company.location?.lat ?? ""),
    lng: String(company.location?.lng ?? ""),
    address: company.location?.address ?? "",
  });
  const action = useAction();
  const set = <K extends keyof typeof form>(k: K, v: (typeof form)[K]) => setForm((f) => ({ ...f, [k]: v }));

  async function submit(e: FormEvent) {
    e.preventDefault();
    const lat = Number(form.lat);
    const lng = Number(form.lng);
    if (!Number.isFinite(lat) || !Number.isFinite(lng) || form.lat === "" || form.lng === "") return action.setError("Enter a valid latitude and longitude.");
    const res = await action.run("save", () =>
      api.patch<Company>("/company", {
        name: form.name.trim(),
        businessType: form.businessType,
        location: { lat, lng, ...(form.address.trim() ? { address: form.address.trim() } : {}) },
      }),
    );
    if (res.ok) {
      onSaved(res.value);
      void refreshMe();
      toast("Business details saved");
    }
  }

  return (
    <Card title="Business">
      <form onSubmit={submit} className="grid items-end gap-3 md:grid-cols-6">
        <Field label="Business name" className="md:col-span-2">
          {(id) => <Input id={id} value={form.name} onChange={(e) => set("name", e.target.value)} />}
        </Field>
        <Field label="Type">
          {(id) => (
            <Select id={id} value={form.businessType} onChange={(e) => set("businessType", e.target.value)}>
              {[...new Set([...BUSINESS_TYPES, form.businessType])].map((b) => (
                <option key={b} value={b}>
                  {b}
                </option>
              ))}
            </Select>
          )}
        </Field>
        <Field label="Latitude">{(id) => <Input id={id} inputMode="decimal" value={form.lat} onChange={(e) => set("lat", e.target.value)} />}</Field>
        <Field label="Longitude">{(id) => <Input id={id} inputMode="decimal" value={form.lng} onChange={(e) => set("lng", e.target.value)} />}</Field>
        <Button type="submit" loading={action.busy === "save"}>
          Save
        </Button>
        <Field label="Address" className="md:col-span-4">
          {(id) => <Input id={id} value={form.address} onChange={(e) => set("address", e.target.value)} />}
        </Field>
        <div className="text-xs text-slate-500 md:col-span-2">
          {company.country} · {company.currency} · {company.timezone}
        </div>
      </form>
      {action.error && <Alert className="mt-3">{action.error}</Alert>}
    </Card>
  );
}

type Draft = Omit<CompanySettings, "graceMinutes" | "halfDayHours" | "maxDeviceTimeDriftMin" | "selfieRetentionDays"> & {
  graceMinutes: string;
  halfDayHours: string;
  maxDeviceTimeDriftMin: string;
  selfieRetentionDays: string;
};
const NUMERIC: (keyof CompanySettings)[] = ["graceMinutes", "halfDayHours", "maxDeviceTimeDriftMin", "selfieRetentionDays"];

function toDraft(s: CompanySettings): Draft {
  return {
    ...s,
    graceMinutes: String(s.graceMinutes ?? ""),
    halfDayHours: String(s.halfDayHours ?? ""),
    maxDeviceTimeDriftMin: String(s.maxDeviceTimeDriftMin ?? ""),
    selfieRetentionDays: String(s.selfieRetentionDays ?? ""),
  };
}

function SettingsForm({ settings, onSaved }: { settings: CompanySettings; onSaved: (c: Company) => void }) {
  const toast = useToast();
  const { t } = useI18n();
  const [base, setBase] = useState(settings);
  const [d, setD] = useState<Draft>(() => toDraft(settings));
  const action = useAction();
  const set = <K extends keyof Draft>(k: K, v: Draft[K]) => setD((x) => ({ ...x, [k]: v }));

  function changes(): Partial<CompanySettings> | string {
    const out: Record<string, unknown> = {};
    for (const key of Object.keys(d) as (keyof Draft)[]) {
      let v: unknown = d[key];
      if (NUMERIC.includes(key)) {
        const n = Number(v);
        if (v === "" || !Number.isFinite(n) || n < 0) return `Enter a valid number for ${key}`;
        v = n;
      }
      if (JSON.stringify(v) !== JSON.stringify(base[key])) out[key] = v;
    }
    return out as Partial<CompanySettings>;
  }

  async function submit(e: FormEvent) {
    e.preventDefault();
    const patch = changes();
    if (typeof patch === "string") return action.setError(patch);
    if (Object.keys(patch).length === 0) return toast("Nothing changed", "slate");
    const res = await action.run("save", () => api.patch<Company>("/company/settings", patch));
    if (res.ok) {
      setBase(res.value.settings);
      setD(toDraft(res.value.settings));
      onSaved(res.value);
      toast("Settings saved");
    }
  }

  return (
    <Card title="Attendance & salary rules">
      <form onSubmit={submit} className="space-y-4">
        <div className="grid gap-3 sm:grid-cols-2">
          <Field label="Grace period (minutes)" hint="Late only after this many minutes">
            {(id) => <Input id={id} type="number" min={0} value={d.graceMinutes} onChange={(e) => set("graceMinutes", e.target.value)} />}
          </Field>
          <Field label="Half day if worked less than (hours)">
            {(id) => <Input id={id} type="number" min={0} step="0.5" value={d.halfDayHours} onChange={(e) => set("halfDayHours", e.target.value)} />}
          </Field>
          <Field label="Monthly salary is divided by">
            {(id) => (
              <Select id={id} value={d.monthDivisor} onChange={(e) => set("monthDivisor", e.target.value as Draft["monthDivisor"])}>
                <option value="days_in_month">Days in the month (28–31)</option>
                <option value="30">Always 30</option>
                <option value="26">Always 26</option>
              </Select>
            )}
          </Field>
          <Field label="If someone forgets to check out">
            {(id) => (
              <Select id={id} value={d.missingCheckoutPolicy} onChange={(e) => set("missingCheckoutPolicy", e.target.value as Draft["missingCheckoutPolicy"])}>
                <option value="half_day">Count as half day</option>
                <option value="present">Count as present</option>
                <option value="flag">Flag for me to decide</option>
              </Select>
            )}
          </Field>
          <Field label="Check-in outside the shop area">
            {(id) => (
              <Select id={id} value={d.outsideGeofencePolicy} onChange={(e) => set("outsideGeofencePolicy", e.target.value as Draft["outsideGeofencePolicy"])}>
                <option value="block">Block it</option>
                <option value="request_approval">Allow, but ask me to approve</option>
              </Select>
            )}
          </Field>
          <Field label="Phone lock at check-in (fingerprint, face, PIN or pattern — never stored)">
            {(id) => (
              <Select id={id} value={d.phoneLockPolicy} onChange={(e) => set("phoneLockPolicy", e.target.value as Draft["phoneLockPolicy"])}>
                <option value="off">Don&apos;t ask</option>
                <option value="recommended">Ask, tag me if it doesn&apos;t open</option>
                <option value="required">Ask, I approve if it doesn&apos;t open</option>
              </Select>
            )}
          </Field>
          <Field label="Face check at check-in (Growth plan and above; staff must agree first)">
            {(id) => (
              <Select id={id} value={d.faceMatchPolicy ?? "off"} onChange={(e) => set("faceMatchPolicy", e.target.value as Draft["faceMatchPolicy"])}>
                <option value="off">Off</option>
                <option value="review">On — I approve unclear matches in the app</option>
              </Select>
            )}
          </Field>
          <Field label="Daily summary time">
            {(id) => <Input id={id} type="time" value={d.digestTime} onChange={(e) => set("digestTime", e.target.value)} />}
          </Field>
          <Field label="Language for staff messages & payslips">
            {(id) => (
              <Select id={id} value={d.language} onChange={(e) => set("language", e.target.value as Draft["language"])}>
                <option value="hi">Hindi</option>
                <option value="en">English</option>
              </Select>
            )}
          </Field>
          <Field label="Max phone clock difference (minutes)">
            {(id) => <Input id={id} type="number" min={0} value={d.maxDeviceTimeDriftMin} onChange={(e) => set("maxDeviceTimeDriftMin", e.target.value)} />}
          </Field>
          <Field label="Keep selfies for (days)">
            {(id) => <Input id={id} type="number" min={1} value={d.selfieRetentionDays} onChange={(e) => set("selfieRetentionDays", e.target.value)} />}
          </Field>
        </div>
        <div className="grid gap-2 sm:grid-cols-2">
          <Checkbox label="Weekly offs are paid" checked={d.weekOffsPaid} onChange={(e) => set("weekOffsPaid", e.target.checked)} />
          <Checkbox label="Holidays are paid" checked={d.holidaysPaid} onChange={(e) => set("holidaysPaid", e.target.checked)} />
          <Checkbox label="Sick leave is paid" checked={d.sickLeavePaid} onChange={(e) => set("sickLeavePaid", e.target.checked)} />
          <Checkbox label="Round salary to the nearest rupee" checked={d.roundToRupee} onChange={(e) => set("roundToRupee", e.target.checked)} />
          <Checkbox label="Selfie required at check-in" checked={d.selfieRequired} onChange={(e) => set("selfieRequired", e.target.checked)} />
          <Checkbox label="WhatsApp alerts" checked={d.whatsappAlerts} onChange={(e) => set("whatsappAlerts", e.target.checked)} />
          <Checkbox label={t("set_ex_staff")} checked={d.exStaffPayslips !== false} onChange={(e) => set("exStaffPayslips", e.target.checked)} />
        </div>
        {action.error && <Alert>{action.error}</Alert>}
        <div className="flex justify-end">
          <Button type="submit" loading={action.busy === "save"}>
            Save rules
          </Button>
        </div>
      </form>
    </Card>
  );
}

function RulesCard({ version }: { version: number }) {
  const { lang } = useI18n();
  const rules = useAsync(() => api.get<{ rules: { key: string; text: string }[] }>("/company/rules"), `rules:${lang}:${version}`);
  return (
    <Card title={lang === "hi" ? "आपके नियम, आसान भाषा में" : "Your rules in plain words"}>
      {rules.errorText && <Alert onRetry={rules.reload}>{rules.errorText}</Alert>}
      {!rules.data && rules.loading ? (
        <Loading />
      ) : (
        <ul className="space-y-2 text-sm text-slate-700">
          {(rules.data?.rules ?? []).map((r) => (
            <li key={r.key} className="flex gap-2">
              <span className="text-mint-500">•</span>
              <span>{r.text}</span>
            </li>
          ))}
        </ul>
      )}
      <p className="mt-3 text-xs text-slate-500">This is what your staff see in the app, so everyone knows how salary is calculated.</p>
    </Card>
  );
}

function HolidaysCard() {
  const toast = useToast();
  const [year, setYear] = useState(() => new Date().getFullYear());
  const holidays = useAsync(() => api.get<Holiday[]>("/holidays", { year }), `holidays:${year}`);
  const [form, setForm] = useState({ date: "", name: "" });
  const action = useAction();

  async function add(e: FormEvent) {
    e.preventDefault();
    if (!form.date || !form.name.trim()) return action.setError("Enter a date and a name.");
    const res = await action.run("add", () => api.post<Holiday>("/holidays", { date: form.date, name: form.name.trim() }));
    if (res.ok) {
      setForm({ date: "", name: "" });
      holidays.reload();
      toast("Holiday added");
    }
  }
  async function remove(h: Holiday) {
    if (!window.confirm(`Remove holiday “${h.name}”?`)) return;
    const res = await action.run(`del:${h.id}`, () => api.delete(`/holidays/${h.id}`));
    if (res.ok) holidays.setData((prev) => (prev ?? []).filter((x) => x.id !== h.id));
  }

  const sorted = [...(holidays.data ?? [])].sort((a, b) => a.date.localeCompare(b.date));

  return (
    <Card
      title="Holidays"
      actions={
        <Select aria-label="Year" className="h-8 w-28 py-1" value={year} onChange={(e) => setYear(Number(e.target.value))}>
          {[-1, 0, 1].map((o) => {
            const y = new Date().getFullYear() + o;
            return (
              <option key={y} value={y}>
                {y}
              </option>
            );
          })}
        </Select>
      }
    >
      <form onSubmit={add} className="mb-4 flex flex-wrap items-end gap-3">
        <Field label="Date">{(id) => <Input id={id} type="date" value={form.date} onChange={(e) => setForm((f) => ({ ...f, date: e.target.value }))} />}</Field>
        <Field label="Name" className="min-w-56 flex-1">
          {(id) => <Input id={id} value={form.name} onChange={(e) => setForm((f) => ({ ...f, name: e.target.value }))} placeholder="Diwali" />}
        </Field>
        <Button type="submit" loading={action.busy === "add"}>
          + Add
        </Button>
      </form>
      {action.error && <Alert className="mb-3">{action.error}</Alert>}
      {holidays.errorText && <Alert onRetry={holidays.reload}>{holidays.errorText}</Alert>}
      {!holidays.data && holidays.loading ? (
        <Loading />
      ) : sorted.length === 0 ? (
        <EmptyState>No holidays for {year}.</EmptyState>
      ) : (
        <ul className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
          {sorted.map((h) => (
            <li key={h.id} className="flex items-center justify-between rounded-lg bg-slate-50 px-3 py-2 text-sm">
              <span>
                <span className="font-medium">{h.name}</span> <span className="text-slate-500">· {formatDate(h.date)}</span>
              </span>
              <button type="button" className="text-xs text-red-600 hover:underline" onClick={() => remove(h)} disabled={action.busy === `del:${h.id}`}>
                Remove
              </button>
            </li>
          ))}
        </ul>
      )}
    </Card>
  );
}

function WeekdayPicker({ value, onChange }: { value: number[]; onChange: (v: number[]) => void }) {
  const { lang } = useI18n();
  const days = lang === "hi" ? WEEKDAYS_HI : WEEKDAYS_EN;
  return (
    <div className="flex flex-wrap gap-1">
      {days.map((d, i) => {
        const on = value.includes(i);
        return (
          <button
            key={d}
            type="button"
            onClick={() => onChange(on ? value.filter((x) => x !== i) : [...value, i].sort())}
            className={`rounded-md px-2 py-1 text-xs font-medium ${on ? "bg-mint-500 text-white" : "bg-slate-100 text-slate-600 hover:bg-slate-200"}`}
            aria-pressed={on}
          >
            {d}
          </button>
        );
      })}
    </div>
  );
}

type ShiftDraft = { name: string; start: string; end: string; graceMinutes: string; weeklyOff: number[] };

function shiftBody(s: ShiftDraft) {
  return {
    name: s.name.trim(),
    start: s.start,
    end: s.end,
    graceMinutes: s.graceMinutes === "" ? null : Number(s.graceMinutes),
    weeklyOff: s.weeklyOff,
  };
}

function ShiftsCard() {
  const toast = useToast();
  const shifts = useAsync(() => api.get<Shift[]>("/shifts"), "shifts");
  const [edits, setEdits] = useState<Record<string, ShiftDraft>>({});
  const [newShift, setNewShift] = useState<ShiftDraft>({ name: "", start: "09:00", end: "18:00", graceMinutes: "", weeklyOff: [0] });
  const action = useAction();

  const draftOf = (s: Shift): ShiftDraft =>
    edits[s.id] ?? { name: s.name, start: s.start, end: s.end, graceMinutes: s.graceMinutes == null ? "" : String(s.graceMinutes), weeklyOff: s.weeklyOff };
  const edit = (s: Shift, p: Partial<ShiftDraft>) => setEdits((e) => ({ ...e, [s.id]: { ...draftOf(s), ...p } }));

  async function save(s: Shift) {
    const res = await action.run(`save:${s.id}`, () => api.patch<Shift>(`/shifts/${s.id}`, shiftBody(draftOf(s))));
    if (res.ok) {
      shifts.setData((prev) => (prev ?? []).map((x) => (x.id === s.id ? res.value : x)));
      setEdits((e) => {
        const n = { ...e };
        delete n[s.id];
        return n;
      });
      toast("Shift saved");
    }
  }
  async function add(e: FormEvent) {
    e.preventDefault();
    if (!newShift.name.trim()) return action.setError("Give the shift a name.");
    const res = await action.run("add", () => api.post<Shift>("/shifts", shiftBody(newShift)));
    if (res.ok) {
      shifts.setData((prev) => [...(prev ?? []), res.value]);
      setNewShift({ name: "", start: "09:00", end: "18:00", graceMinutes: "", weeklyOff: [0] });
      toast("Shift added");
    }
  }

  return (
    <Card title="Shifts" padded={false}>
      {action.error && <Alert className="m-4">{action.error}</Alert>}
      {shifts.errorText && <Alert className="m-4" onRetry={shifts.reload}>{shifts.errorText}</Alert>}
      {!shifts.data && shifts.loading ? (
        <Loading />
      ) : (
        <Table>
          <thead>
            <tr>
              <Th>Name</Th>
              <Th>Start</Th>
              <Th>End</Th>
              <Th>Grace (min)</Th>
              <Th>Weekly off</Th>
              <Th />
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-100">
            {(shifts.data ?? []).map((s) => {
              const d = draftOf(s);
              return (
                <tr key={s.id}>
                  <Td><Input className="h-8 w-40 py-1" value={d.name} onChange={(e) => edit(s, { name: e.target.value })} aria-label="Shift name" /></Td>
                  <Td><Input className="h-8 w-28 py-1" type="time" value={d.start} onChange={(e) => edit(s, { start: e.target.value })} aria-label="Start" /></Td>
                  <Td><Input className="h-8 w-28 py-1" type="time" value={d.end} onChange={(e) => edit(s, { end: e.target.value })} aria-label="End" /></Td>
                  <Td><Input className="h-8 w-24 py-1" type="number" min={0} placeholder="Default" value={d.graceMinutes} onChange={(e) => edit(s, { graceMinutes: e.target.value })} aria-label="Grace minutes" /></Td>
                  <Td><WeekdayPicker value={d.weeklyOff} onChange={(v) => edit(s, { weeklyOff: v })} /></Td>
                  <Td className="text-right">
                    {edits[s.id] && (
                      <Button size="sm" loading={action.busy === `save:${s.id}`} onClick={() => save(s)}>
                        Save
                      </Button>
                    )}
                  </Td>
                </tr>
              );
            })}
            <tr className="bg-slate-50/60">
              <Td><Input className="h-8 w-40 py-1" placeholder="New shift name" value={newShift.name} onChange={(e) => setNewShift((n) => ({ ...n, name: e.target.value }))} aria-label="New shift name" /></Td>
              <Td><Input className="h-8 w-28 py-1" type="time" value={newShift.start} onChange={(e) => setNewShift((n) => ({ ...n, start: e.target.value }))} aria-label="New shift start" /></Td>
              <Td><Input className="h-8 w-28 py-1" type="time" value={newShift.end} onChange={(e) => setNewShift((n) => ({ ...n, end: e.target.value }))} aria-label="New shift end" /></Td>
              <Td><Input className="h-8 w-24 py-1" type="number" min={0} placeholder="Default" value={newShift.graceMinutes} onChange={(e) => setNewShift((n) => ({ ...n, graceMinutes: e.target.value }))} aria-label="New shift grace" /></Td>
              <Td><WeekdayPicker value={newShift.weeklyOff} onChange={(v) => setNewShift((n) => ({ ...n, weeklyOff: v }))} /></Td>
              <Td className="text-right">
                <form onSubmit={add}>
                  <Button size="sm" type="submit" loading={action.busy === "add"}>
                    + Add
                  </Button>
                </form>
              </Td>
            </tr>
          </tbody>
        </Table>
      )}
    </Card>
  );
}

type BranchDraft = { name: string; lat: string; lng: string; address: string; radiusM: string; shiftId: string };

function branchBody(b: BranchDraft) {
  const lat = Number(b.lat);
  const lng = Number(b.lng);
  if (!b.name.trim()) return "Branch name is required.";
  if (b.lat === "" || b.lng === "" || !Number.isFinite(lat) || !Number.isFinite(lng)) return "Enter a valid latitude and longitude.";
  const radius = Number(b.radiusM);
  return {
    name: b.name.trim(),
    location: { lat, lng, ...(b.address.trim() ? { address: b.address.trim() } : {}) },
    ...(b.radiusM !== "" && Number.isFinite(radius) ? { radiusM: radius } : {}),
    ...(b.shiftId ? { shiftId: b.shiftId } : {}),
  };
}

function BranchesCard() {
  const toast = useToast();
  const branches = useAsync(() => api.get<Branch[]>("/branches"), "branches");
  const shifts = useAsync(() => api.get<Shift[]>("/shifts"), "shifts:branches");
  const [edits, setEdits] = useState<Record<string, BranchDraft>>({});
  const empty: BranchDraft = { name: "", lat: "", lng: "", address: "", radiusM: "100", shiftId: "" };
  const [nb, setNb] = useState<BranchDraft>(empty);
  const action = useAction();

  const draftOf = (b: Branch): BranchDraft =>
    edits[b.id] ?? {
      name: b.name,
      lat: String(b.location?.lat ?? ""),
      lng: String(b.location?.lng ?? ""),
      address: b.location?.address ?? "",
      radiusM: String(b.radiusM ?? ""),
      shiftId: b.shiftId ?? "",
    };
  const edit = (b: Branch, p: Partial<BranchDraft>) => setEdits((e) => ({ ...e, [b.id]: { ...draftOf(b), ...p } }));

  async function save(b: Branch) {
    const body = branchBody(draftOf(b));
    if (typeof body === "string") return action.setError(body);
    const res = await action.run(`save:${b.id}`, () => api.patch<Branch>(`/branches/${b.id}`, body));
    if (res.ok) {
      branches.setData((prev) => (prev ?? []).map((x) => (x.id === b.id ? res.value : x)));
      setEdits((e) => {
        const n = { ...e };
        delete n[b.id];
        return n;
      });
      toast("Branch saved");
    }
  }
  async function add(e: FormEvent) {
    e.preventDefault();
    const body = branchBody(nb);
    if (typeof body === "string") return action.setError(body);
    const res = await action.run("add", () => api.post<Branch>("/branches", body));
    if (res.ok) {
      branches.setData((prev) => [...(prev ?? []), res.value]);
      setNb(empty);
      toast("Branch added");
    }
  }

  const shiftOptions = shifts.data ?? [];
  const row = (d: BranchDraft, on: (p: Partial<BranchDraft>) => void, label: string) => (
    <>
      <Td><Input className="h-8 w-36 py-1" value={d.name} placeholder="Branch name" onChange={(e) => on({ name: e.target.value })} aria-label={`${label} name`} /></Td>
      <Td><Input className="h-8 w-28 py-1" inputMode="decimal" value={d.lat} placeholder="28.61" onChange={(e) => on({ lat: e.target.value })} aria-label={`${label} latitude`} /></Td>
      <Td><Input className="h-8 w-28 py-1" inputMode="decimal" value={d.lng} placeholder="77.20" onChange={(e) => on({ lng: e.target.value })} aria-label={`${label} longitude`} /></Td>
      <Td><Input className="h-8 w-24 py-1" type="number" min={10} value={d.radiusM} onChange={(e) => on({ radiusM: e.target.value })} aria-label={`${label} radius`} /></Td>
      <Td><Input className="h-8 w-44 py-1" value={d.address} placeholder="Address" onChange={(e) => on({ address: e.target.value })} aria-label={`${label} address`} /></Td>
      <Td>
        <Select className="h-8 w-36 py-1" value={d.shiftId} onChange={(e) => on({ shiftId: e.target.value })} aria-label={`${label} shift`}>
          <option value="">Default</option>
          {shiftOptions.map((s) => (
            <option key={s.id} value={s.id}>
              {s.name}
            </option>
          ))}
        </Select>
      </Td>
    </>
  );

  return (
    <Card title="Branches & check-in area" padded={false}>
      <p className="px-4 pt-3 text-xs text-slate-500">Staff can check in only within the radius (in metres) around each branch location.</p>
      {action.error && <Alert className="m-4">{action.error}</Alert>}
      {branches.errorText && <Alert className="m-4" onRetry={branches.reload}>{branches.errorText}</Alert>}
      {!branches.data && branches.loading ? (
        <Loading />
      ) : (
        <Table>
          <thead>
            <tr>
              <Th>Name</Th>
              <Th>Latitude</Th>
              <Th>Longitude</Th>
              <Th>Radius (m)</Th>
              <Th>Address</Th>
              <Th>Shift</Th>
              <Th />
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-100">
            {(branches.data ?? []).map((b) => (
              <tr key={b.id}>
                {row(draftOf(b), (p) => edit(b, p), b.name)}
                <Td className="text-right">
                  {edits[b.id] && (
                    <Button size="sm" loading={action.busy === `save:${b.id}`} onClick={() => save(b)}>
                      Save
                    </Button>
                  )}
                </Td>
              </tr>
            ))}
            <tr className="bg-slate-50/60">
              {row(nb, (p) => setNb((x) => ({ ...x, ...p })), "New branch")}
              <Td className="text-right">
                <form onSubmit={add}>
                  <Button size="sm" type="submit" loading={action.busy === "add"}>
                    + Add
                  </Button>
                </form>
              </Td>
            </tr>
          </tbody>
        </Table>
      )}
    </Card>
  );
}
