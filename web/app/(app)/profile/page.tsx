"use client";

import Link from "next/link";
import { useRef, useState, type FormEvent } from "react";
import { useAuth, useI18n, useToast } from "@/components/providers";
import { Alert, Badge, Button, Card, Field, Input, Loading, Modal, PageHeader, Segmented, cx } from "@/components/ui";
import { useAsync } from "@/hooks/useAsync";
import { api, ApiError, errorMessage } from "@/lib/api";
import { formatDate, formatDateTime } from "@/lib/format";
import type { DictKey } from "@/lib/i18n";
import { displayPhone, EMAIL_RE, fileToJpegBase64, indianMobile, initials } from "@/lib/profile";
import type { Lang, Profile } from "@/lib/types";

const ROLE_KEY: Record<string, DictKey> = { owner: "role_owner", manager: "role_manager", ca: "role_ca", employee: "role_employee" };
const MISSING_KEY: Record<string, DictKey> = { photo: "profile_missing_photo", name: "profile_missing_name", email: "profile_missing_email" };

export default function ProfilePage() {
  const { t } = useI18n();
  const profile = useAsync(() => api.get<Profile>("/me/profile"), "profile");

  return (
    <div className="space-y-6">
      <PageHeader title={t("nav_profile")} subtitle={t("profile_subtitle")} />
      {profile.errorText && <Alert onRetry={profile.reload}>{profile.errorText}</Alert>}
      {!profile.data ? (
        profile.loading && <Loading />
      ) : (
        <div className="grid items-start gap-6 lg:grid-cols-[340px_1fr]">
          <IdentityCard profile={profile.data} onChange={profile.setData} />
          <div className="space-y-6">
            <PersonalCard key={profile.data.user.id + profile.data.user.name + profile.data.user.email} profile={profile.data} onChange={profile.setData} />
            <MobileCard profile={profile.data} onChange={profile.setData} />
            {profile.data.company && <BusinessCard profile={profile.data} />}
            <SecurityCard />
          </div>
        </div>
      )}
    </div>
  );
}

/** Cover band, photo with hover-to-change, role, completeness ring and checklist. */
function IdentityCard({ profile, onChange }: { profile: Profile; onChange: (p: Profile) => void }) {
  const { t } = useI18n();
  const toast = useToast();
  const { refreshMe } = useAuth();
  const fileRef = useRef<HTMLInputElement>(null);
  const [busy, setBusy] = useState(false);
  const u = profile.user;
  const pct = profile.completeness.percent;
  const r = 34;
  const circ = 2 * Math.PI * r;

  async function upload(file: File) {
    setBusy(true);
    try {
      const b64 = await fileToJpegBase64(file);
      onChange(await api.put<Profile>("/me/photo", { photoBase64: b64 }));
      void refreshMe();
    } catch (e) {
      toast(errorMessage(e), "red");
    } finally {
      setBusy(false);
      if (fileRef.current) fileRef.current.value = "";
    }
  }

  async function remove() {
    setBusy(true);
    try {
      onChange(await api.delete<Profile>("/me/photo"));
    } catch (e) {
      toast(errorMessage(e), "red");
    } finally {
      setBusy(false);
    }
  }

  return (
    <section className="overflow-hidden rounded-2xl bg-white shadow-sm ring-1 ring-slate-200 lg:sticky lg:top-6">
      <div className="h-24 bg-gradient-to-br from-mint-500 via-mint-700 to-slate-900" />
      <div className="-mt-12 flex flex-col items-center px-6 pb-6 text-center">
        <button
          type="button"
          onClick={() => fileRef.current?.click()}
          className="group relative h-24 w-24 rounded-full ring-4 ring-white focus-visible:outline-none focus-visible:ring-mint-300"
          aria-label={t("profile_photo_change")}
          disabled={busy}
        >
          {u.photoUrl ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={u.photoUrl} alt="" className="h-24 w-24 rounded-full object-cover" />
          ) : (
            <span className="grid h-24 w-24 place-items-center rounded-full bg-mint-100 text-3xl font-bold text-mint-700">{initials(u.name || u.phone)}</span>
          )}
          <span className="absolute inset-0 grid place-items-center rounded-full bg-slate-900/55 text-xs font-medium text-white opacity-0 transition-opacity group-hover:opacity-100 group-focus-visible:opacity-100">
            {busy ? "…" : `📷 ${t("profile_photo_change")}`}
          </span>
          <span className="absolute -bottom-0.5 -right-0.5 grid h-8 w-8 place-items-center rounded-full bg-mint-500 text-sm text-white ring-4 ring-white" aria-hidden>
            📷
          </span>
        </button>
        <input ref={fileRef} type="file" accept="image/*" className="hidden" onChange={(e) => e.target.files?.[0] && void upload(e.target.files[0])} />
        {u.photoUrl && (
          <button type="button" onClick={() => void remove()} disabled={busy} className="mt-2 text-xs text-slate-500 underline-offset-2 hover:text-red-600 hover:underline">
            {t("profile_photo_remove")}
          </button>
        )}
        <h2 className="mt-3 text-xl font-semibold text-slate-900">{u.name || displayPhone(u.phone)}</h2>
        <div className="mt-2 flex flex-wrap items-center justify-center gap-2">
          <Badge tone="mint">{t(ROLE_KEY[u.role] ?? "role_owner")}</Badge>
          {profile.company && <span className="text-sm text-slate-600">{profile.company.name}</span>}
        </div>
        <p className="mt-1 text-sm text-slate-500">{displayPhone(u.phone)}</p>

        <div className="mt-6 w-full rounded-xl bg-slate-50 p-4 text-left">
          <div className="flex items-center gap-4">
            <svg width="84" height="84" viewBox="0 0 84 84" className="shrink-0" role="img" aria-label={t("profile_complete").replace("{p}", String(pct))}>
              <circle cx="42" cy="42" r={r} fill="none" stroke="#e2e8f0" strokeWidth="8" />
              <circle
                cx="42"
                cy="42"
                r={r}
                fill="none"
                stroke="#2bb673"
                strokeWidth="8"
                strokeLinecap="round"
                strokeDasharray={circ}
                strokeDashoffset={circ * (1 - pct / 100)}
                transform="rotate(-90 42 42)"
                className="transition-[stroke-dashoffset] duration-700"
              />
              <text x="42" y="47" textAnchor="middle" className="fill-slate-900 text-[15px] font-bold">
                {pct}%
              </text>
            </svg>
            <div>
              <p className="font-semibold text-slate-900">{pct === 100 ? t("profile_complete_done") : t("profile_complete").replace("{p}", String(pct))}</p>
              {profile.completeness.missing.length > 0 && (
                <ul className="mt-1 space-y-1">
                  {profile.completeness.missing
                    .filter((m) => MISSING_KEY[m])
                    .map((m) => (
                      <li key={m}>
                        <button
                          type="button"
                          className="text-sm font-medium text-mint-700 hover:underline"
                          onClick={() => (m === "photo" ? fileRef.current?.click() : document.querySelector<HTMLInputElement>(`[data-profile="${m}"]`)?.focus())}
                        >
                          + {t(MISSING_KEY[m])}
                        </button>
                      </li>
                    ))}
                </ul>
              )}
            </div>
          </div>
        </div>
        <div className="mt-4 w-full space-y-1 text-left text-xs text-slate-500">
          {u.memberSince && <p>{t("profile_member_since").replace("{d}", formatDate(u.memberSince))}</p>}
          {u.lastLoginAt && <p>{t("profile_last_login").replace("{d}", formatDateTime(u.lastLoginAt))}</p>}
        </div>
      </div>
    </section>
  );
}

function PersonalCard({ profile, onChange }: { profile: Profile; onChange: (p: Profile) => void }) {
  const { t, lang, setLang } = useI18n();
  const toast = useToast();
  const { refreshMe } = useAuth();
  const [name, setName] = useState(profile.user.name);
  const [email, setEmail] = useState(profile.user.email ?? "");
  const [errors, setErrors] = useState<{ name?: string; email?: string }>({});
  const [busy, setBusy] = useState(false);
  const dirty = name.trim() !== profile.user.name || email.trim() !== (profile.user.email ?? "");

  async function submit(e: FormEvent) {
    e.preventDefault();
    const next: typeof errors = {};
    if (!name.trim()) next.name = t("profile_required");
    if (email.trim() && !EMAIL_RE.test(email.trim())) next.email = t("profile_invalid_email");
    setErrors(next);
    if (Object.keys(next).length) return;
    setBusy(true);
    try {
      onChange(await api.patch<Profile>("/me/profile", { name: name.trim(), email: email.trim() || null }));
      void refreshMe();
      toast(t("profile_saved"), "mint");
    } catch (err) {
      const field = err instanceof ApiError && err.details && typeof err.details === "object" ? (err.details as { field?: string }).field : undefined;
      if (field === "email" || field === "name") setErrors({ [field]: errorMessage(err) });
      else toast(errorMessage(err), "red");
    } finally {
      setBusy(false);
    }
  }

  async function changeLanguage(l: Lang) {
    setLang(l);
    try {
      onChange(await api.patch<Profile>("/me/profile", { language: l }));
    } catch (err) {
      toast(errorMessage(err), "red");
    }
  }

  return (
    <Card title={t("profile_personal")}>
      <form onSubmit={submit} className="grid gap-4 md:grid-cols-2" noValidate>
        <Field label={t("profile_name")} error={errors.name}>
          {(id) => <Input id={id} data-profile="name" value={name} invalid={!!errors.name} onChange={(e) => setName(e.target.value)} maxLength={80} autoComplete="name" />}
        </Field>
        <Field label={t("profile_email")} hint={t("profile_email_hint")} error={errors.email}>
          {(id) => (
            <Input id={id} data-profile="email" type="email" value={email} invalid={!!errors.email} onChange={(e) => setEmail(e.target.value)} placeholder="you@example.com" maxLength={120} autoComplete="email" />
          )}
        </Field>
        <div className="space-y-1">
          <span className="block text-sm font-medium text-slate-700">{t("profile_language")}</span>
          <Segmented
            value={lang}
            options={[
              { value: "hi" as Lang, label: "हिन्दी" },
              { value: "en" as Lang, label: "English" },
            ]}
            onChange={(l) => void changeLanguage(l)}
          />
        </div>
        <div className="flex items-end justify-end gap-2 md:col-span-2">
          {dirty && (
            <Button
              variant="ghost"
              onClick={() => {
                setName(profile.user.name);
                setEmail(profile.user.email ?? "");
                setErrors({});
              }}
            >
              {t("cancel")}
            </Button>
          )}
          <Button type="submit" loading={busy} disabled={!dirty}>
            {t("save")}
          </Button>
        </div>
      </form>
    </Card>
  );
}

function MobileCard({ profile, onChange }: { profile: Profile; onChange: (p: Profile) => void }) {
  const { t } = useI18n();
  const toast = useToast();
  const { refreshMe } = useAuth();
  const [open, setOpen] = useState(false);
  const [step, setStep] = useState<"phone" | "code">("phone");
  const [phone, setPhone] = useState("");
  const [code, setCode] = useState("");
  const [devCode, setDevCode] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  function close() {
    setOpen(false);
    setStep("phone");
    setPhone("");
    setCode("");
    setDevCode(null);
    setError(null);
  }

  async function send() {
    const p = indianMobile(phone);
    if (!p) return setError(t("profile_invalid_phone"));
    setBusy(true);
    setError(null);
    try {
      const r = await api.post<{ devCode?: string }>("/me/phone/request", { phone: p });
      setDevCode(r.devCode ?? null);
      setStep("code");
    } catch (e) {
      setError(errorMessage(e));
    } finally {
      setBusy(false);
    }
  }

  async function verify() {
    setBusy(true);
    setError(null);
    try {
      onChange(await api.post<Profile>("/me/phone/verify", { phone: indianMobile(phone), code: code.trim() }));
      void refreshMe();
      toast(t("profile_mobile_changed"), "mint");
      close();
    } catch (e) {
      setError(errorMessage(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <Card title={t("profile_mobile")} actions={<Button variant="secondary" size="sm" onClick={() => setOpen(true)}>{t("profile_change")}</Button>}>
      <div className="flex items-center gap-3">
        <span className="grid h-10 w-10 place-items-center rounded-lg bg-mint-50 text-lg text-mint-700" aria-hidden>
          ☎
        </span>
        <div>
          <p className="font-semibold text-slate-900">{displayPhone(profile.user.phone)}</p>
          <p className="text-sm text-slate-500">{t("profile_mobile_hint")}</p>
        </div>
      </div>
      <Modal
        open={open}
        title={t("profile_change_mobile")}
        onClose={close}
        footer={
          <>
            <Button variant="ghost" onClick={close}>
              {t("cancel")}
            </Button>
            {step === "phone" ? (
              <Button loading={busy} onClick={() => void send()}>
                {t("profile_send_code")}
              </Button>
            ) : (
              <Button loading={busy} disabled={code.trim().length < 4} onClick={() => void verify()}>
                {t("profile_verify")}
              </Button>
            )}
          </>
        }
      >
        {step === "phone" ? (
          <Field label={t("profile_new_mobile")} error={error}>
            {(id) => (
              <div className="flex">
                <span className="inline-flex items-center rounded-l-lg bg-slate-100 px-3 text-sm text-slate-600 ring-1 ring-inset ring-slate-300">+91</span>
                <Input id={id} className="rounded-l-none" inputMode="numeric" autoFocus value={phone} onChange={(e) => setPhone(e.target.value)} onKeyDown={(e) => e.key === "Enter" && void send()} placeholder="98765 43210" />
              </div>
            )}
          </Field>
        ) : (
          <div className="space-y-3">
            <p className="text-sm text-slate-600">{t("profile_code_sent").replace("{phone}", displayPhone(`+91${indianMobile(phone)}`))}</p>
            {devCode && <p className="rounded-lg bg-mint-50 px-3 py-2 text-sm text-mint-800">{t("profile_test_code").replace("{code}", devCode)}</p>}
            <Input
              aria-label="OTP"
              inputMode="numeric"
              autoFocus
              maxLength={6}
              value={code}
              onChange={(e) => setCode(e.target.value.replace(/\D/g, ""))}
              onKeyDown={(e) => e.key === "Enter" && void verify()}
              className="text-center text-2xl tracking-[0.6em]"
              placeholder="••••••"
            />
            {error && <p className="text-xs text-red-600">{error}</p>}
          </div>
        )}
      </Modal>
    </Card>
  );
}

function BusinessCard({ profile }: { profile: Profile }) {
  const { t } = useI18n();
  const c = profile.company!;
  const isOwner = profile.user.role === "owner";
  return (
    <Card
      title={t("profile_business")}
      actions={
        isOwner && (
          <>
            <Link href="/billing" className="text-sm font-medium text-slate-600 hover:text-slate-900">
              {t("profile_billing")}
            </Link>
            <Link href="/settings" className="text-sm font-medium text-mint-700 hover:underline">
              {t("profile_business_settings")} →
            </Link>
          </>
        )
      }
    >
      <dl className="grid gap-4 sm:grid-cols-3">
        {[
          [t("profile_business"), c.name],
          [t("profile_business_type"), c.businessType],
          [t("profile_plan"), c.planName ?? "—"],
        ].map(([k, v]) => (
          <div key={k} className="rounded-lg bg-slate-50 px-3 py-2">
            <dt className="text-xs text-slate-500">{k}</dt>
            <dd className={cx("font-semibold capitalize text-slate-900")}>{v}</dd>
          </div>
        ))}
      </dl>
    </Card>
  );
}

function SecurityCard() {
  const { t } = useI18n();
  const toast = useToast();
  const { logout } = useAuth();
  const [confirm, setConfirm] = useState(false);
  const [busy, setBusy] = useState(false);

  async function logoutAll() {
    setBusy(true);
    try {
      await api.post("/me/logout-all");
      await logout();
    } catch (e) {
      toast(errorMessage(e), "red");
      setBusy(false);
    }
  }

  return (
    <Card title={t("profile_security")}>
      <div className="flex flex-wrap items-center justify-between gap-3">
        <p className="max-w-xl text-sm text-slate-600">{t("profile_logout_all_hint")}</p>
        <Button variant="danger" onClick={() => setConfirm(true)}>
          {t("profile_logout_all")}
        </Button>
      </div>
      <Modal
        open={confirm}
        title={t("profile_logout_all_confirm")}
        onClose={() => setConfirm(false)}
        footer={
          <>
            <Button variant="ghost" onClick={() => setConfirm(false)}>
              {t("cancel")}
            </Button>
            <Button variant="danger" loading={busy} onClick={() => void logoutAll()}>
              {t("profile_logout_all")}
            </Button>
          </>
        }
      >
        <p className="text-sm text-slate-600">{t("profile_logout_all_hint")}</p>
      </Modal>
    </Card>
  );
}
