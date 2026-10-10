"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState, type FormEvent } from "react";
import { LanguageToggle, Logo } from "@/components/AppShell";
import { useAuth, useI18n } from "@/components/providers";
import { AccountChooser } from "@/components/AccountChooser";
import { AccountAlerts } from "@/components/AccountAlerts";
import { ClosedBusinesses, EndedNotices } from "@/components/AccountNotices";
import { CompanySetup } from "@/components/CompanySetup";
import { Alert, Button, Field, Input, Loading } from "@/components/ui";
import { api, errorMessage } from "@/lib/api";
import { displayPhone } from "@/lib/profile";
import { homeFor } from "@/lib/roles";
import { getDeviceId } from "@/lib/tokens";
import type { IdentityCheck, OtpRequestResult, OtpVerifyResult } from "@/lib/types";


export default function LoginPage() {
  const { status, me, signIn, logout } = useAuth();
  const { t } = useI18n();
  const router = useRouter();

  const [step, setStep] = useState<"phone" | "otp">("phone");
  /** Several businesses on this number: ask which one before entering. */
  const [choosing, setChoosing] = useState(false);
  /** Login paused: "Is this you?" for a long-idle number on a new device. */
  const [identity, setIdentity] = useState<IdentityCheck | null>(null);
  const [phone, setPhone] = useState("");
  const [code, setCode] = useState("");
  const [otpInfo, setOtpInfo] = useState<OtpRequestResult | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const needsSetup = status === "authenticated" && me?.user.role === "owner" && !me.company;
  const readyToEnter = status === "authenticated" && !needsSetup && !choosing && me;

  useEffect(() => {
    if (readyToEnter) router.replace(homeFor(me.user.role));
  }, [readyToEnter, me, router]);

  async function requestOtp(e?: FormEvent) {
    e?.preventDefault();
    setError(null);
    const digits = phone.replace(/\D/g, "");
    if (digits.length < 10) {
      setError("Enter a valid 10-digit mobile number.");
      return;
    }
    setBusy(true);
    try {
      const res = await api.post<OtpRequestResult>("/auth/otp/request", { phone: phone.trim(), channel: "sms" }, { auth: false });
      setOtpInfo(res);
      setStep("otp");
    } catch (err) {
      setError(errorMessage(err));
    } finally {
      setBusy(false);
    }
  }

  async function verify(e: FormEvent) {
    e.preventDefault();
    setError(null);
    setBusy(true);
    try {
      const res = await api.post<OtpVerifyResult>(
        "/auth/otp/verify",
        { phone: phone.trim(), code: code.trim(), deviceId: getDeviceId(), deviceName: "StaffMint Web" },
        { auth: false },
      );
      if (res.identityCheck) {
        setIdentity(res.identityCheck);
        return;
      }
      if (res.needsAccountChoice) setChoosing(true);
      const loaded = await signIn({ accessToken: res.accessToken, refreshToken: res.refreshToken });
      // Redirect / setup step is derived from auth state.
      if (!loaded) setError("Logged in, but could not load your account. Please try again.");
    } catch (err) {
      setError(errorMessage(err));
    } finally {
      setBusy(false);
    }
  }

  async function answerIdentity(isMe: boolean) {
    if (!identity) return;
    setBusy(true);
    setError(null);
    try {
      const res = await api.post<OtpVerifyResult>(`/auth/identity/${isMe ? "confirm" : "reject"}`, { token: identity.token }, { auth: false });
      setIdentity(null);
      if (res.needsAccountChoice) setChoosing(true);
      await signIn({ accessToken: res.accessToken, refreshToken: res.refreshToken });
    } catch (err) {
      setError(errorMessage(err));
    } finally {
      setBusy(false);
    }
  }

  let content;
  if (identity) {
    content = (
      <div className="space-y-4" data-identity-check>
        <h1 className="text-xl font-semibold">{t("id_title").replace("{name}", identity.maskedName)}</h1>
        <p className="text-sm text-slate-600">{t("id_body")}</p>
        {error && <Alert>{error}</Alert>}
        <div className="flex gap-2">
          <Button variant="secondary" className="flex-1" disabled={busy} onClick={() => void answerIdentity(false)}>
            {t("id_no")}
          </Button>
          <Button className="flex-1" loading={busy} onClick={() => void answerIdentity(true)}>
            {t("id_yes")}
          </Button>
        </div>
      </div>
    );
  } else if (status === "loading" || readyToEnter) {
    content = <Loading label={t("loading")} />;
  } else if (choosing && status === "authenticated" && me) {
    content = (
      <div className="space-y-4">
        <div>
          <h1 className="text-xl font-semibold">{t("acc_choose")}</h1>
          <p className="mt-1 text-sm text-slate-600">{t("acc_choose_hint").replace("{phone}", displayPhone(me.user.phone))}</p>
        </div>
        <AccountChooser memberships={me.memberships ?? []} activeId={me.activeMembershipId} onChosen={() => setChoosing(false)} />
        <p className="text-center text-xs text-slate-500">{t("acc_footer")}</p>
        <div className="text-center">
          <Button variant="ghost" size="sm" onClick={() => { setChoosing(false); void logout(); }}>
            {t("logout")}
          </Button>
        </div>
      </div>
    );
  } else if (needsSetup) {
    content = (
      <div className="space-y-4">
        {/* Why there is no business any more, and businesses that can be brought back. */}
        <EndedNotices notices={me?.endedNotices ?? []} />
        <ClosedBusinesses list={me?.closedBusinesses ?? []} />
        <AccountAlerts />
        <CompanySetup onDone={(tokens) => signIn(tokens)} />
        <Link href="/recover" className="block text-center text-sm font-medium text-mint-700 hover:underline" data-recover-link>
          {t("rec_link")}
        </Link>
      </div>
    );
  } else if (step === "phone") {
    content = (
      <form onSubmit={requestOtp} className="space-y-4">
        <h1 className="text-xl font-semibold">{t("login_title")}</h1>
        <Field label={t("login_phone")} hint="10-digit Indian number or +91…">
          {(id) => (
            <Input
              id={id}
              inputMode="tel"
              autoComplete="tel"
              placeholder="98765 43210"
              value={phone}
              onChange={(e) => setPhone(e.target.value)}
              autoFocus
            />
          )}
        </Field>
        {error && <Alert>{error}</Alert>}
        <Button type="submit" className="w-full" loading={busy}>
          {t("login_send_otp")}
        </Button>
      </form>
    );
  } else {
    content = (
      <form onSubmit={verify} className="space-y-4">
        <h1 className="text-xl font-semibold">{t("login_otp")}</h1>
        <p className="text-sm text-slate-600">
          Sent to <span className="font-medium">{phone}</span>.{" "}
          <button type="button" className="text-mint-700 underline" onClick={() => { setStep("phone"); setCode(""); setError(null); }}>
            {t("login_change_phone")}
          </button>
        </p>
        {otpInfo?.devCode && (
          <Alert tone="sky">
            {t("login_dev_code")}: <span className="font-mono font-semibold tracking-widest">{otpInfo.devCode}</span>
          </Alert>
        )}
        <Field label="OTP">
          {(id) => (
            <Input
              id={id}
              inputMode="numeric"
              autoComplete="one-time-code"
              maxLength={8}
              value={code}
              onChange={(e) => setCode(e.target.value.replace(/\D/g, ""))}
              className="text-center font-mono text-lg tracking-[0.5em]"
              autoFocus
            />
          )}
        </Field>
        {error && <Alert>{error}</Alert>}
        <Button type="submit" className="w-full" loading={busy} disabled={code.length < 4}>
          {t("login_verify")}
        </Button>
        <button type="button" className="w-full text-center text-sm text-slate-500 hover:text-slate-700" onClick={() => void requestOtp()} disabled={busy}>
          Resend OTP
        </button>
      </form>
    );
  }

  return (
    <div className="flex min-h-screen flex-col items-center justify-center bg-gradient-to-b from-mint-50 to-slate-50 p-4">
      <div className="mb-6 flex w-full max-w-md items-center justify-between">
        <Logo />
        <LanguageToggle />
      </div>
      <div className={`w-full rounded-2xl bg-white p-6 shadow-sm ring-1 ring-slate-200 ${needsSetup ? "max-w-2xl" : "max-w-md"}`}>{content}</div>
      <p className="mt-6 text-xs text-slate-500">{t("tagline")}</p>
    </div>
  );
}

