"use client";

import { useState, type FormEvent } from "react";
import { useAuth, useToast } from "@/components/providers";
import { Alert, Button, Card, Field, Input, PageHeader, Rows } from "@/components/ui";
import { api, errorText } from "@/lib/api";

export default function AccountPage() {
  const { admin, signOut } = useAuth();
  const toast = useToast();
  const [current, setCurrent] = useState("");
  const [next, setNext] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function change(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      await api.post("/admin/me/password", { current, next });
      toast("Password changed. Sign in again.");
      await signOut();
    } catch (err) {
      setError(errorText(err));
      setBusy(false);
    }
  }

  return (
    <div className="space-y-4">
      <PageHeader title="My account" back="/more" />
      <Card>
        <Rows
          rows={[
            ["Name", admin?.name || "—"],
            ["Email", admin?.email ?? "—"],
            ["Access", admin?.role === "admin" ? "Admin (can change things)" : "View only"],
          ]}
        />
      </Card>
      <Card title="Change password">
        <form onSubmit={change} className="space-y-4">
          {error && <Alert>{error}</Alert>}
          <Field label="Current password">{(id) => <Input id={id} type="password" autoComplete="current-password" required value={current} onChange={(e) => setCurrent(e.target.value)} />}</Field>
          <Field label="New password" hint="At least 10 characters, with letters and numbers. Signs you out on every device.">
            {(id) => <Input id={id} type="password" autoComplete="new-password" required minLength={10} value={next} onChange={(e) => setNext(e.target.value)} />}
          </Field>
          <Button type="submit" loading={busy} className="w-full sm:w-auto">
            Change password
          </Button>
        </form>
      </Card>
      <Button variant="secondary" className="w-full sm:w-auto" onClick={() => void signOut()}>
        Sign out everywhere
      </Button>
    </div>
  );
}
