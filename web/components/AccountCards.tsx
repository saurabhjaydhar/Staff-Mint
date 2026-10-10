"use client";

import { useState } from "react";
import { useAsync } from "@/hooks/useAsync";
import { api, errorMessage } from "@/lib/api";
import { displayPhone, indianMobile } from "@/lib/profile";
import type { Accountant } from "@/lib/types";
import { useAuth, useI18n, useToast } from "./providers";
import { Alert, Button, Card, EmptyState, Field, Input, Loading, Modal } from "./ui";

/** Manager or accountant steps away from the open business (PRD F14 row 7). */
export function LeaveBusinessCard() {
  const { t } = useI18n();
  const toast = useToast();
  const { me, leaveAccount } = useAuth();
  const [confirm, setConfirm] = useState(false);
  const [busy, setBusy] = useState(false);
  const active = (me?.memberships ?? []).find((m) => m.id === me?.activeMembershipId);
  if (!active || active.role === "owner") return null;
  const msg = t("acc_leave_confirm").replace("{name}", active.companyName);
  return (
    <Card title={t("acc_leave")}>
      <div className="flex flex-wrap items-center justify-between gap-3">
        <p className="max-w-xl text-sm text-slate-600">{msg}</p>
        <Button variant="danger" data-leave-business onClick={() => setConfirm(true)}>
          {t("acc_leave")}
        </Button>
      </div>
      <Modal
        open={confirm}
        title={t("acc_leave")}
        onClose={() => setConfirm(false)}
        footer={
          <>
            <Button variant="ghost" onClick={() => setConfirm(false)}>
              {t("cancel")}
            </Button>
            <Button
              variant="danger"
              loading={busy}
              onClick={async () => {
                setBusy(true);
                try {
                  await leaveAccount(active.id);
                  toast(t("acc_left").replace("{name}", active.companyName));
                } catch (e) {
                  toast(errorMessage(e), "red");
                  setBusy(false);
                }
              }}
            >
              {t("acc_leave")}
            </Button>
          </>
        }
      >
        <p className="text-sm text-slate-600">{msg}</p>
      </Modal>
    </Card>
  );
}

/** Owner's accountants: list, add, remove (read-only access to reports and payroll). */
export function AccountantsCard() {
  const { t } = useI18n();
  const toast = useToast();
  const list = useAsync(() => api.get<Accountant[]>("/company/accountants"), "accountants");
  const [adding, setAdding] = useState(false);
  const [form, setForm] = useState({ name: "", phone: "" });
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function add() {
    const phone = indianMobile(form.phone);
    if (!form.name.trim() || !phone) return setError(t("profile_invalid_phone"));
    setBusy("add");
    setError(null);
    try {
      await api.post("/company/accountants", { name: form.name.trim(), phone });
      setAdding(false);
      setForm({ name: "", phone: "" });
      list.reload();
    } catch (e) {
      setError(errorMessage(e));
    } finally {
      setBusy(null);
    }
  }

  async function remove(a: Accountant) {
    if (!window.confirm(`${t("acc_remove")} ${a.name || displayPhone(a.phone)}?`)) return;
    setBusy(a.id);
    try {
      await api.delete(`/company/accountants/${a.id}`);
      list.reload();
    } catch (e) {
      toast(errorMessage(e), "red");
    } finally {
      setBusy(null);
    }
  }

  return (
    <Card
      title={t("acc_accountants")}
      actions={
        <Button size="sm" variant="secondary" data-add-accountant onClick={() => setAdding(true)}>
          + {t("acc_add_accountant")}
        </Button>
      }
    >
      <p className="mb-3 text-sm text-slate-500">{t("acc_accountants_hint")}</p>
      {list.errorText && <Alert onRetry={list.reload}>{list.errorText}</Alert>}
      {!list.data ? (
        list.loading && <Loading />
      ) : list.data.length === 0 ? (
        <EmptyState>{t("acc_no_accountants")}</EmptyState>
      ) : (
        <ul className="divide-y divide-slate-100">
          {list.data.map((a) => (
            <li key={a.id} data-accountant={a.id} className="flex items-center justify-between gap-3 py-2">
              <div className="min-w-0">
                <p className="truncate font-medium text-slate-900">{a.name || displayPhone(a.phone)}</p>
                <p className="text-xs text-slate-500">{displayPhone(a.phone)}</p>
              </div>
              <Button size="sm" variant="ghost" className="text-red-600" loading={busy === a.id} onClick={() => void remove(a)}>
                {t("acc_remove")}
              </Button>
            </li>
          ))}
        </ul>
      )}
      <Modal
        open={adding}
        title={t("acc_add_accountant")}
        onClose={() => setAdding(false)}
        footer={
          <>
            <Button variant="ghost" onClick={() => setAdding(false)}>
              {t("cancel")}
            </Button>
            <Button loading={busy === "add"} onClick={() => void add()}>
              {t("add")}
            </Button>
          </>
        }
      >
        <div className="space-y-3">
          <Field label={t("profile_name")}>{(id) => <Input id={id} value={form.name} onChange={(e) => setForm((f) => ({ ...f, name: e.target.value }))} autoFocus />}</Field>
          <Field label={t("profile_mobile")}>
            {(id) => <Input id={id} inputMode="tel" value={form.phone} placeholder="98765 43210" onChange={(e) => setForm((f) => ({ ...f, phone: e.target.value }))} />}
          </Field>
          {error && <Alert>{error}</Alert>}
        </div>
      </Modal>
    </Card>
  );
}

/** Main owner closes the business; restorable for 30 days (PRD F14 row 18). */
export function CloseBusinessCard() {
  const { t } = useI18n();
  const toast = useToast();
  const { me, closeBusiness } = useAuth();
  const [open, setOpen] = useState(false);
  const [typed, setTyped] = useState("");
  const [busy, setBusy] = useState(false);
  const name = me?.company?.name ?? "";
  const matches = typed.trim().toLowerCase() === name.trim().toLowerCase() && name.length > 0;
  return (
    <Card title={t("acc_danger")} className="ring-red-200">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="max-w-xl">
          <p className="font-medium text-red-700">{t("acc_close")}</p>
          <p className="text-sm text-slate-600">{t("acc_close_hint")}</p>
        </div>
        <Button variant="danger" data-close-business onClick={() => setOpen(true)}>
          {t("acc_close_button")}
        </Button>
      </div>
      <Modal
        open={open}
        title={t("acc_close")}
        onClose={() => setOpen(false)}
        footer={
          <>
            <Button variant="ghost" onClick={() => setOpen(false)}>
              {t("cancel")}
            </Button>
            <Button
              variant="danger"
              disabled={!matches}
              loading={busy}
              onClick={async () => {
                setBusy(true);
                try {
                  await closeBusiness(typed);
                  toast(t("acc_closed").replace("{name}", name));
                } catch (e) {
                  toast(errorMessage(e), "red");
                  setBusy(false);
                }
              }}
            >
              {t("acc_close_button")}
            </Button>
          </>
        }
      >
        <p className="mb-3 text-sm text-slate-600">{t("acc_close_hint")}</p>
        <Field label={t("acc_close_type").replace("{name}", name)}>{(id) => <Input id={id} value={typed} onChange={(e) => setTyped(e.target.value)} autoFocus />}</Field>
      </Modal>
    </Card>
  );
}
