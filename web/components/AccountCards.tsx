"use client";

import { useState } from "react";
import { useAsync } from "@/hooks/useAsync";
import { api, errorMessage } from "@/lib/api";
import { displayPhone, indianMobile } from "@/lib/profile";
import type { Accountant, OwnerItem, TransferOffer } from "@/lib/types";
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

/** Owners: co-owners (billing only if allowed), handover, and recovery for a lost owner number. */
export function OwnersCard() {
  const { t } = useI18n();
  const toast = useToast();
  const { me } = useAuth();
  const owners = useAsync(() => api.get<OwnerItem[]>("/company/owners"), "owners");
  const transfer = useAsync(() => api.get<TransferOffer | null>("/company/transfer"), "transfer");
  const [modal, setModal] = useState<"add" | "transfer" | "recover" | null>(null);
  const [form, setForm] = useState({ name: "", phone: "", billing: false, keepAs: "co_owner" as "co_owner" | "leave", code: "" });
  const [codeSent, setCodeSent] = useState(false);
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const list = owners.data ?? [];
  const iAmMain = list.some((o) => o.isYou && o.isMain);

  function open(m: "add" | "transfer" | "recover") {
    setForm({ name: "", phone: "", billing: false, keepAs: "co_owner", code: "" });
    setCodeSent(false);
    setError(null);
    setModal(m);
  }

  async function run(key: string, fn: () => Promise<unknown>, after?: () => void) {
    setBusy(key);
    setError(null);
    try {
      await fn();
      after?.();
    } catch (e) {
      setError(errorMessage(e));
      if (!modal) toast(errorMessage(e), "red");
    } finally {
      setBusy(null);
    }
  }

  async function submit() {
    const phone = indianMobile(form.phone);
    if (!phone) return setError(t("profile_invalid_phone"));
    if (modal === "add") {
      if (!form.name.trim()) return setError(t("profile_required"));
      await run("submit", () => api.post("/company/owners", { name: form.name.trim(), phone, canManageBilling: form.billing }), () => {
        setModal(null);
        owners.reload();
      });
    } else if (modal === "transfer") {
      if (!codeSent) {
        // The main owner's own OTP confirms the handover.
        return run("submit", () => api.post("/auth/otp/request", { phone: me?.user.phone, channel: "sms" }, { auth: false }), () => setCodeSent(true));
      }
      await run("submit", () => api.post("/company/transfer", { phone, keepAs: form.keepAs, code: form.code.trim() }), () => {
        setModal(null);
        transfer.reload();
      });
    } else if (modal === "recover") {
      await run("submit", () => api.post("/company/owner-recovery", { newPhone: phone }), () => {
        setModal(null);
        transfer.reload();
      });
    }
  }

  return (
    <Card
      title={t("own_title")}
      actions={
        iAmMain ? (
          <Button size="sm" variant="secondary" data-add-owner onClick={() => open("add")}>
            + {t("own_add")}
          </Button>
        ) : null
      }
    >
      <p className="mb-3 text-sm text-slate-500">{t("own_hint")}</p>
      {owners.errorText && <Alert onRetry={owners.reload}>{owners.errorText}</Alert>}
      {!owners.data && owners.loading && <Loading />}
      <ul className="divide-y divide-slate-100">
        {list.map((o) => (
          <li key={o.id} data-owner={o.id} className="flex flex-wrap items-center justify-between gap-3 py-2">
            <div className="min-w-0">
              <p className="truncate font-medium text-slate-900">
                {o.name || displayPhone(o.phone)} {o.isYou && <span className="text-xs text-slate-400">({t("own_you")})</span>}
              </p>
              <p className="text-xs text-slate-500">
                {o.isMain ? t("own_main") : t("own_co")} · {displayPhone(o.phone)}
              </p>
            </div>
            {!o.isMain && (
              <div className="flex items-center gap-2">
                <label className="flex items-center gap-1.5 text-xs text-slate-600">
                  <input
                    type="checkbox"
                    data-billing={o.id}
                    checked={o.canManageBilling}
                    disabled={!iAmMain || busy !== null}
                    onChange={(e) => run(`bill:${o.id}`, () => api.patch(`/company/owners/${o.id}`, { canManageBilling: e.target.checked }), owners.reload)}
                  />
                  {t("own_billing")}
                </label>
                {iAmMain && (
                  <Button size="sm" variant="ghost" className="text-red-600" loading={busy === `rm:${o.id}`} onClick={() => window.confirm(`${t("acc_remove")}?`) && run(`rm:${o.id}`, () => api.delete(`/company/owners/${o.id}`), owners.reload)}>
                    {t("acc_remove")}
                  </Button>
                )}
              </div>
            )}
          </li>
        ))}
      </ul>
      <div className="mt-3 border-t border-slate-100 pt-3">
        {transfer.data ? (
          <div className="flex flex-wrap items-center justify-between gap-2 rounded-lg bg-amber-50 px-3 py-2 text-sm ring-1 ring-amber-200">
            <span>{t("own_pending").replace("{phone}", transfer.data.toPhoneMasked)}</span>
            <Button size="sm" variant="ghost" loading={busy === "cancel"} onClick={() => run("cancel", () => api.delete("/company/transfer"), transfer.reload)}>
              {t("own_cancel")}
            </Button>
          </div>
        ) : iAmMain ? (
          <div className="flex flex-wrap items-center justify-between gap-2">
            <p className="max-w-xl text-sm text-slate-600">{t("own_transfer_hint")}</p>
            <Button size="sm" variant="secondary" data-transfer onClick={() => open("transfer")}>
              {t("own_transfer")}
            </Button>
          </div>
        ) : (
          <div className="flex flex-wrap items-center justify-between gap-2">
            <p className="max-w-xl text-sm text-slate-600">{t("own_lost_hint")}</p>
            <Button size="sm" variant="secondary" onClick={() => open("recover")}>
              {t("own_lost")}
            </Button>
          </div>
        )}
      </div>
      <Modal
        open={modal !== null}
        title={modal === "add" ? t("own_add") : modal === "transfer" ? t("own_transfer") : t("own_lost")}
        onClose={() => setModal(null)}
        footer={
          <>
            <Button variant="ghost" onClick={() => setModal(null)}>
              {t("cancel")}
            </Button>
            <Button loading={busy === "submit"} onClick={() => void submit()}>
              {modal === "transfer" && !codeSent ? t("own_send_code") : t("confirm")}
            </Button>
          </>
        }
      >
        <div className="space-y-3">
          {modal === "add" && (
            <Field label={t("profile_name")}>{(id) => <Input id={id} value={form.name} onChange={(e) => setForm((f) => ({ ...f, name: e.target.value }))} autoFocus />}</Field>
          )}
          <Field label={modal === "transfer" ? t("own_new_number") : modal === "recover" ? t("own_lost_number") : t("profile_mobile")}>
            {(id) => <Input id={id} inputMode="tel" value={form.phone} placeholder="98765 43210" onChange={(e) => setForm((f) => ({ ...f, phone: e.target.value }))} />}
          </Field>
          {modal === "add" && (
            <label className="flex items-center gap-2 text-sm">
              <input type="checkbox" checked={form.billing} onChange={(e) => setForm((f) => ({ ...f, billing: e.target.checked }))} /> {t("own_billing")}
            </label>
          )}
          {modal === "transfer" && (
            <div className="space-y-1 text-sm">
              {(["co_owner", "leave"] as const).map((k) => (
                <label key={k} className="flex items-center gap-2">
                  <input type="radio" name="keepAs" checked={form.keepAs === k} onChange={() => setForm((f) => ({ ...f, keepAs: k }))} />
                  {k === "co_owner" ? t("own_keep") : t("own_leave")}
                </label>
              ))}
            </div>
          )}
          {modal === "transfer" && codeSent && (
            <Field label={t("own_code")}>{(id) => <Input id={id} inputMode="numeric" value={form.code} onChange={(e) => setForm((f) => ({ ...f, code: e.target.value.replace(/\D/g, "") }))} />}</Field>
          )}
          {error && <Alert>{error}</Alert>}
        </div>
      </Modal>
    </Card>
  );
}

/** Download everything about me, or delete my account (OTP to my own number). */
export function DataCard() {
  const { t } = useI18n();
  const toast = useToast();
  const { me, logout } = useAuth();
  const [open, setOpen] = useState(false);
  const [codeSent, setCodeSent] = useState(false);
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function download() {
    try {
      const data = await api.get("/me/export");
      const url = URL.createObjectURL(new Blob([JSON.stringify(data, null, 2)], { type: "application/json" }));
      const a = document.createElement("a");
      a.href = url;
      a.download = "staffmint-my-data.json";
      a.click();
      URL.revokeObjectURL(url);
    } catch (e) {
      toast(errorMessage(e), "red");
    }
  }

  async function next() {
    setBusy(true);
    setError(null);
    try {
      if (!codeSent) {
        await api.post("/auth/otp/request", { phone: me?.user.phone, channel: "sms" }, { auth: false });
        setCodeSent(true);
      } else {
        await api.post("/me/delete", { code: code.trim() });
        await logout();
      }
    } catch (e) {
      setError(errorMessage(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <Card title={t("data_title")}>
      <div className="flex flex-wrap items-center justify-between gap-3">
        <p className="max-w-xl text-sm text-slate-600">{t("data_delete_hint")}</p>
        <div className="flex gap-2">
          <Button variant="secondary" data-export-me onClick={() => void download()}>
            {t("data_export")}
          </Button>
          <Button variant="danger" data-delete-me onClick={() => setOpen(true)}>
            {t("data_delete")}
          </Button>
        </div>
      </div>
      <Modal
        open={open}
        title={t("data_delete")}
        onClose={() => setOpen(false)}
        footer={
          <>
            <Button variant="ghost" onClick={() => setOpen(false)}>
              {t("cancel")}
            </Button>
            <Button variant="danger" loading={busy} onClick={() => void next()}>
              {codeSent ? t("data_delete_forever") : t("own_send_code")}
            </Button>
          </>
        }
      >
        <p className="mb-3 text-sm text-slate-600">{t("data_delete_hint")}</p>
        {codeSent && <Field label={t("own_code")}>{(id) => <Input id={id} inputMode="numeric" value={code} onChange={(e) => setCode(e.target.value.replace(/\D/g, ""))} autoFocus />}</Field>}
        {error && <Alert className="mt-3">{error}</Alert>}
      </Modal>
    </Card>
  );
}
