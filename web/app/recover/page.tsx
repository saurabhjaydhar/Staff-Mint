"use client";

import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { LanguageToggle, Logo } from "@/components/AppShell";
import { useAuth, useI18n, useToast } from "@/components/providers";
import { Alert, Button, Field, Input, Loading } from "@/components/ui";
import { useAsync } from "@/hooks/useAsync";
import { api, errorMessage } from "@/lib/api";
import { indianMobile } from "@/lib/profile";
import type { RecoveryHold } from "@/lib/types";

/** Lost the old number: move the account here by its email, or ask support (PRD F14 row 11). */
export default function RecoverPage() {
  const { status, recoverByEmail } = useAuth();
  const { t } = useI18n();
  const toast = useToast();
  const router = useRouter();
  const mine = useAsync(() => (status === "authenticated" ? api.get<RecoveryHold[]>("/me/recovery-requests") : Promise.resolve([])), `recoveries-${status}`);
  const [email, setEmail] = useState("");
  const [code, setCode] = useState("");
  const [devCode, setDevCode] = useState<string | null>(null);
  const [codeSent, setCodeSent] = useState(false);
  const [support, setSupport] = useState({ oldPhone: "", businessName: "", gstin: "", paymentTxnId: "" });
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (status === "anonymous") router.replace("/login");
  }, [status, router]);

  async function emailStep() {
    setBusy("email");
    setError(null);
    try {
      if (!codeSent) {
        const r = await api.post<{ sent: boolean; devCode?: string }>("/me/recovery/email", { email: email.trim() });
        setDevCode(r.devCode ?? null);
        setCodeSent(true);
      } else {
        await recoverByEmail(email.trim(), code.trim());
        router.replace("/");
      }
    } catch (e) {
      setError(errorMessage(e));
    } finally {
      setBusy(null);
    }
  }

  async function supportStep() {
    const oldPhone = indianMobile(support.oldPhone);
    const proofs = [support.gstin.trim(), support.paymentTxnId.trim()].filter(Boolean).length;
    if (!oldPhone || support.businessName.trim().length < 2) return setError(t("profile_invalid_phone"));
    if (proofs < 2) return setError(t("rec_two"));
    setBusy("support");
    setError(null);
    try {
      await api.post("/me/recovery-requests", {
        oldPhone,
        businessName: support.businessName.trim(),
        gstin: support.gstin.trim() || undefined,
        paymentTxnId: support.paymentTxnId.trim() || undefined,
      });
      toast(t("rec_sent"));
      mine.reload();
    } catch (e) {
      setError(errorMessage(e));
    } finally {
      setBusy(null);
    }
  }

  return (
    <div className="flex min-h-screen flex-col items-center justify-center bg-gradient-to-b from-mint-50 to-slate-50 p-4">
      <div className="mb-6 flex w-full max-w-xl items-center justify-between">
        <Logo />
        <LanguageToggle />
      </div>
      <div className="w-full max-w-xl space-y-6 rounded-2xl bg-white p-6 shadow-sm ring-1 ring-slate-200">
        {status !== "authenticated" ? (
          <Loading label={t("loading")} />
        ) : (
          <>
            <h1 className="text-xl font-semibold">{t("rec_title")}</h1>
            {(mine.data ?? []).map((r) => (
              <Alert key={r.id} tone="sky">
                {r.businessName}: {r.status}
              </Alert>
            ))}
            {error && <Alert>{error}</Alert>}
            <section className="space-y-3">
              <h2 className="font-semibold">{t("rec_email")}</h2>
              <p className="text-sm text-slate-500">{t("rec_email_hint")}</p>
              <Field label="Email">{(id) => <Input id={id} type="email" value={email} onChange={(e) => setEmail(e.target.value)} />}</Field>
              {codeSent && (
                <>
                  {devCode && <p className="text-xs text-slate-500">Test code: {devCode}</p>}
                  <Field label={t("rec_code")}>{(id) => <Input id={id} inputMode="numeric" value={code} onChange={(e) => setCode(e.target.value.replace(/\D/g, ""))} />}</Field>
                </>
              )}
              <Button loading={busy === "email"} onClick={() => void emailStep()} data-recover-email>
                {codeSent ? t("rec_go") : t("rec_send")}
              </Button>
            </section>
            <section className="space-y-3 border-t border-slate-100 pt-5">
              <h2 className="font-semibold">{t("rec_support")}</h2>
              <p className="text-sm text-slate-500">{t("rec_support_hint")}</p>
              <Field label={t("rec_old")}>{(id) => <Input id={id} inputMode="tel" value={support.oldPhone} onChange={(e) => setSupport((s) => ({ ...s, oldPhone: e.target.value }))} />}</Field>
              <Field label={t("setup_business_name")}>{(id) => <Input id={id} value={support.businessName} onChange={(e) => setSupport((s) => ({ ...s, businessName: e.target.value }))} />}</Field>
              <Field label={t("rec_gstin")}>{(id) => <Input id={id} value={support.gstin} onChange={(e) => setSupport((s) => ({ ...s, gstin: e.target.value }))} />}</Field>
              <Field label={t("rec_payment")}>{(id) => <Input id={id} value={support.paymentTxnId} onChange={(e) => setSupport((s) => ({ ...s, paymentTxnId: e.target.value }))} />}</Field>
              <p className="text-xs text-slate-500">{t("rec_two")} — the selfie video option is in the mobile app.</p>
              <Button variant="secondary" loading={busy === "support"} onClick={() => void supportStep()}>
                {t("rec_support")}
              </Button>
            </section>
          </>
        )}
      </div>
    </div>
  );
}
