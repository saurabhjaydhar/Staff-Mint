"use client";

import { useMemo, useState } from "react";
import { useAuth, useToast } from "@/components/providers";
import { Alert, Badge, Button, Card, Chips, Empty, Field, Input, ListSkeleton, PageHeader, Sheet, cx } from "@/components/ui";
import { api, errorText } from "@/lib/api";
import { invalidate } from "@/lib/cache";
import { configLabel, configValue, parseConfigInput, rupees } from "@/lib/format";
import type { ConfigRow, Flag, Plan } from "@/lib/types";
import { useApi } from "@/lib/useApi";

function SettingsTab() {
  const { data, error, reload } = useApi<ConfigRow[]>("/admin/configs");
  const { canEdit } = useAuth();
  const toast = useToast();
  const [filter, setFilter] = useState("");
  const [editing, setEditing] = useState<ConfigRow | null>(null);
  const [raw, setRaw] = useState("");
  const [busy, setBusy] = useState(false);
  const [formError, setFormError] = useState<string | null>(null);

  const shown = useMemo(() => (data ?? []).filter((c) => !filter || c.key.toLowerCase().includes(filter.toLowerCase())), [data, filter]);

  async function save(value: unknown) {
    if (!editing) return;
    setBusy(true);
    setFormError(null);
    try {
      await api.put(`/admin/configs/${encodeURIComponent(editing.key)}`, { value });
      invalidate("/admin/configs");
      await reload();
      setEditing(null);
      toast("Setting saved");
    } catch (e) {
      setFormError(errorText(e));
    } finally {
      setBusy(false);
    }
  }

  function submit() {
    if (!editing) return;
    const parsed = parseConfigInput(raw, editing.defaultValue ?? editing.value);
    if (!parsed.ok) return setFormError(parsed.error);
    void save(parsed.value);
  }

  return (
    <div className="space-y-3">
      <Input type="search" placeholder="Find a setting" value={filter} onChange={(e) => setFilter(e.target.value)} aria-label="Find a setting" />
      {error && <Alert onRetry={() => void reload()}>{error}</Alert>}
      <Card padded={false}>
        {!data ? (
          <ListSkeleton />
        ) : shown.length === 0 ? (
          <Empty>No settings match.</Empty>
        ) : (
          <ul className="divide-y divide-slate-100">
            {shown.map((c) => (
              <li key={c.key}>
                <button
                  type="button"
                  disabled={!canEdit}
                  onClick={() => {
                    setEditing(c);
                    setRaw(configValue(c.value) === "—" ? "" : Array.isArray(c.value) ? c.value.join(", ") : typeof c.value === "boolean" ? (c.value ? "on" : "off") : String(c.value));
                    setFormError(null);
                  }}
                  className="flex w-full items-center gap-3 px-4 py-3 text-left enabled:hover:bg-slate-50 enabled:active:bg-slate-100"
                >
                  <span className="min-w-0 flex-1">
                    <span className="block truncate text-sm font-medium">{configLabel(c.key)}</span>
                    <span className="block truncate font-mono text-xs text-slate-400">{c.key}</span>
                  </span>
                  <span className="max-w-[45%] truncate text-right text-sm text-slate-700">{c.key.endsWith("Paise") && typeof c.value === "number" ? rupees(c.value) : configValue(c.value)}</span>
                  {c.changed && <Badge tone="amber">Changed</Badge>}
                </button>
              </li>
            ))}
          </ul>
        )}
      </Card>
      <Sheet
        open={!!editing}
        title={editing ? configLabel(editing.key) : ""}
        onClose={() => setEditing(null)}
        footer={
          <>
            {editing?.changed && editing.defaultValue !== null && (
              <Button variant="ghost" className="flex-1" disabled={busy} onClick={() => void save(editing.defaultValue)}>
                Reset to default
              </Button>
            )}
            <Button className="flex-1" loading={busy} onClick={submit}>
              Save
            </Button>
          </>
        }
      >
        {editing && (
          <div className="space-y-4">
            {formError && <Alert>{formError}</Alert>}
            <Field
              label="Value"
              hint={`${editing.key.endsWith("Paise") ? "In paise (100 = ₹1). " : ""}Default: ${configValue(editing.defaultValue)}${Array.isArray(editing.defaultValue) ? " (separate with commas)" : ""}${editing.businessOverrides ? ` · ${editing.businessOverrides} business(es) have their own value` : ""}`}
            >
              {(id) => <Input id={id} value={raw} autoFocus onChange={(e) => setRaw(e.target.value)} onKeyDown={(e) => e.key === "Enter" && submit()} />}
            </Field>
            <p className="font-mono text-xs text-slate-400">{editing.key}</p>
          </div>
        )}
      </Sheet>
    </div>
  );
}

function FlagsTab() {
  const { data, error, reload } = useApi<Flag[]>("/admin/flags");
  const { data: plans } = useApi<Plan[]>("/admin/plans");
  const { canEdit } = useAuth();
  const toast = useToast();
  const [busy, setBusy] = useState<string | null>(null);
  const [adding, setAdding] = useState(false);
  const [newKey, setNewKey] = useState("");

  async function saveFlag(f: Flag, done: string) {
    setBusy(f.key);
    try {
      await api.put("/admin/flags", { key: f.key, enabled: f.enabled, plans: f.plans, companyIds: f.companyIds, description: f.description });
      invalidate("/admin/flags");
      await reload();
      toast(done);
    } catch (e) {
      toast(errorText(e), "red");
    } finally {
      setBusy(null);
    }
  }

  return (
    <div className="space-y-3">
      {error && <Alert onRetry={() => void reload()}>{error}</Alert>}
      {canEdit && (
        <Button variant="secondary" className="w-full sm:w-auto" onClick={() => setAdding(true)}>
          Add a flag
        </Button>
      )}
      <Card padded={false}>
        {!data ? (
          <ListSkeleton rows={3} />
        ) : data.length === 0 ? (
          <Empty>No feature flags yet.</Empty>
        ) : (
          <ul className="divide-y divide-slate-100">
            {data.map((f) => (
              <li key={f.key} className="space-y-2 px-4 py-3">
                <div className="flex items-center gap-3">
                  <span className="min-w-0 flex-1">
                    <span className="block truncate font-mono text-sm font-medium">{f.key}</span>
                    {f.description && <span className="block truncate text-xs text-slate-500">{f.description}</span>}
                  </span>
                  <button
                    type="button"
                    role="switch"
                    aria-checked={f.enabled}
                    aria-label={`${f.key} on for everyone`}
                    disabled={!canEdit || busy === f.key}
                    onClick={() => void saveFlag({ ...f, enabled: !f.enabled }, f.enabled ? "Turned off for everyone" : "Turned on for everyone")}
                    className={cx("relative h-7 w-12 shrink-0 rounded-full transition-colors disabled:opacity-60", f.enabled ? "bg-mint-600" : "bg-slate-300")}
                  >
                    <span className={cx("absolute top-0.5 h-6 w-6 rounded-full bg-white shadow transition-all", f.enabled ? "left-[22px]" : "left-0.5")} />
                  </button>
                </div>
                <div className="flex flex-wrap items-center gap-1.5 text-xs">
                  <span className="text-slate-500">On for plans:</span>
                  {(plans ?? []).map((p) => {
                    const on = f.plans.includes(p.code);
                    return (
                      <button
                        key={p.code}
                        type="button"
                        disabled={!canEdit || busy === f.key}
                        aria-pressed={on}
                        onClick={() => void saveFlag({ ...f, plans: on ? f.plans.filter((x) => x !== p.code) : [...f.plans, p.code] }, "Flag saved")}
                        className={cx("h-7 rounded-full px-2.5 ring-1 disabled:opacity-60", on ? "bg-mint-50 text-mint-800 ring-mint-300" : "bg-white text-slate-600 ring-slate-200")}
                      >
                        {p.name}
                      </button>
                    );
                  })}
                  {f.companyIds.length > 0 && <Badge tone="violet">+{f.companyIds.length} businesses</Badge>}
                </div>
              </li>
            ))}
          </ul>
        )}
      </Card>
      <Sheet
        open={adding}
        title="Add a feature flag"
        onClose={() => setAdding(false)}
        footer={
          <Button
            className="flex-1"
            disabled={!/^[a-z0-9_.-]{2,80}$/.test(newKey)}
            loading={busy === newKey}
            onClick={async () => {
              await saveFlag({ key: newKey, enabled: false, plans: [], companyIds: [] }, "Flag added (off)");
              setAdding(false);
              setNewKey("");
            }}
          >
            Add (starts off)
          </Button>
        }
      >
        <Field label="Key" hint="Lowercase, like new_reports. The app checks this name.">
          {(id) => <Input id={id} value={newKey} autoFocus onChange={(e) => setNewKey(e.target.value.toLowerCase().replace(/\s+/g, "_"))} />}
        </Field>
      </Sheet>
    </div>
  );
}

export default function SettingsPage() {
  const [tab, setTab] = useState<"settings" | "flags">("settings");
  return (
    <div className="space-y-3">
      <PageHeader title="Settings & flags" subtitle="Change how StaffMint behaves without an app update" back="/more" />
      <Chips
        value={tab}
        onChange={setTab}
        options={[
          { value: "settings", label: "Settings" },
          { value: "flags", label: "Feature flags" },
        ]}
      />
      {tab === "settings" ? <SettingsTab /> : <FlagsTab />}
    </div>
  );
}
