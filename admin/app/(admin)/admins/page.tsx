"use client";

import { useState } from "react";
import { useAuth, useToast } from "@/components/providers";
import { Alert, Badge, Button, Card, Chips, Field, Input, ListSkeleton, PageHeader, Sheet } from "@/components/ui";
import { api, errorText } from "@/lib/api";
import { invalidate } from "@/lib/cache";
import { ago } from "@/lib/format";
import type { Admin, AdminRole } from "@/lib/types";
import { useApi } from "@/lib/useApi";

export default function AdminsPage() {
  const { data, error, reload } = useApi<Admin[]>("/admin/admins");
  const { admin: me, canEdit } = useAuth();
  const toast = useToast();
  const [adding, setAdding] = useState(false);
  const [form, setForm] = useState({ email: "", name: "", password: "", role: "viewer" as AdminRole });
  const [busy, setBusy] = useState<string | null>(null);
  const [formError, setFormError] = useState<string | null>(null);

  async function run(key: string, fn: () => Promise<unknown>, done: string) {
    setBusy(key);
    try {
      await fn();
      invalidate("/admin/admins");
      await reload();
      toast(done);
      return true;
    } catch (e) {
      if (key === "add") setFormError(errorText(e));
      else toast(errorText(e), "red");
      return false;
    } finally {
      setBusy(null);
    }
  }

  return (
    <div className="space-y-3">
      <PageHeader title="Admins" subtitle="People who can open this app" back="/more" />
      {error && <Alert onRetry={() => void reload()}>{error}</Alert>}
      {canEdit && (
        <Button
          variant="secondary"
          className="w-full sm:w-auto"
          onClick={() => {
            setForm({ email: "", name: "", password: "", role: "viewer" });
            setFormError(null);
            setAdding(true);
          }}
        >
          Add an admin
        </Button>
      )}
      <Card padded={false}>
        {!data ? (
          <ListSkeleton rows={3} />
        ) : (
          <ul className="divide-y divide-slate-100">
            {data.map((a) => {
              const self = a.id === me?.id;
              return (
                <li key={a.id} className="flex flex-wrap items-center gap-3 px-4 py-3">
                  <span className="min-w-0 flex-1">
                    <span className="flex items-center gap-2">
                      <span className="truncate font-medium">{a.name || a.email}</span>
                      {self && <Badge tone="sky">You</Badge>}
                      {!a.active && <Badge tone="red">Disabled</Badge>}
                    </span>
                    <span className="block truncate text-xs text-slate-500">
                      {a.email} · {a.role === "admin" ? "Admin" : "View only"} · last sign-in {a.lastLoginAt ? ago(a.lastLoginAt) : "never"}
                    </span>
                  </span>
                  {canEdit && !self && a.id && (
                    <span className="flex gap-2">
                      <Button size="sm" variant="ghost" loading={busy === `role:${a.id}`} onClick={() => void run(`role:${a.id}`, () => api.patch(`/admin/admins/${a.id}`, { role: a.role === "admin" ? "viewer" : "admin" }), "Access changed")}>
                        {a.role === "admin" ? "Make view only" : "Make admin"}
                      </Button>
                      <Button size="sm" variant={a.active ? "secondary" : "primary"} loading={busy === `active:${a.id}`} onClick={() => void run(`active:${a.id}`, () => api.patch(`/admin/admins/${a.id}`, { active: !a.active }), a.active ? "Disabled and signed out" : "Enabled")}>
                        {a.active ? "Disable" : "Enable"}
                      </Button>
                    </span>
                  )}
                </li>
              );
            })}
          </ul>
        )}
      </Card>
      <Sheet
        open={adding}
        title="Add an admin"
        onClose={() => setAdding(false)}
        footer={
          <>
            <Button variant="ghost" className="flex-1" onClick={() => setAdding(false)}>
              Cancel
            </Button>
            <Button
              className="flex-1"
              loading={busy === "add"}
              onClick={async () => {
                setFormError(null);
                if (await run("add", () => api.post("/admin/admins", form), "Admin added")) setAdding(false);
              }}
            >
              Add
            </Button>
          </>
        }
      >
        <div className="space-y-4">
          {formError && <Alert>{formError}</Alert>}
          <Field label="Email">{(id) => <Input id={id} type="email" value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} />}</Field>
          <Field label="Name">{(id) => <Input id={id} value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} />}</Field>
          <Field label="First password" hint="At least 10 characters, with letters and numbers. Share it privately; they can change it in My account.">
            {(id) => <Input id={id} type="text" autoComplete="off" value={form.password} onChange={(e) => setForm({ ...form, password: e.target.value })} />}
          </Field>
          <Field label="Access">
            {() => (
              <Chips
                value={form.role}
                onChange={(role) => setForm({ ...form, role })}
                options={[
                  { value: "viewer", label: "View only" },
                  { value: "admin", label: "Admin" },
                ]}
              />
            )}
          </Field>
        </div>
      </Sheet>
    </div>
  );
}
