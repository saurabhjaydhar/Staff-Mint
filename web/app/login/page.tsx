"use client";

import { useRouter } from "next/navigation";
import { useEffect, useState, type FormEvent } from "react";
import { LanguageToggle, Logo } from "@/components/AppShell";
import { useAuth, useI18n } from "@/components/providers";
import { Alert, Button, Checkbox, Field, Input, Loading, Select } from "@/components/ui";
import { api, errorMessage } from "@/lib/api";
import { WEEKDAYS_EN, WEEKDAYS_HI } from "@/lib/format";
import { homeFor } from "@/lib/roles";
import { getDeviceId } from "@/lib/tokens";
import type { CompanySetupInput, CompanySetupResult, OtpRequestResult, OtpVerifyResult } from "@/lib/types";

const BUSINESS_TYPES = [
  { value: "shop", label: "Shop / Retail" },
  { value: "restaurant", label: "Restaurant / Café" },
  { value: "clinic", label: "Clinic / Pharmacy" },
  { value: "salon", label: "Salon / Spa" },
  { value: "office", label: "Office" },
  { value: "factory", label: "Factory / Workshop" },
  { value: "other", label: "Other" },
];

export default function LoginPage() {
  const { status, me, signIn } = useAuth();
  const { t } = useI18n();
  const router = useRouter();

  const [step, setStep] = useState<"phone" | "otp">("phone");
  const [phone, setPhone] = useState("");
  const [code, setCode] = useState("");
  const [otpInfo, setOtpInfo] = useState<OtpRequestResult | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const needsSetup = status === "authenticated" && me?.user.role === "owner" && !me.company;
  const readyToEnter = status === "authenticated" && !needsSetup && me;

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
      const loaded = await signIn({ accessToken: res.accessToken, refreshToken: res.refreshToken });
      // Redirect / setup step is derived from auth state.
      if (!loaded) setError("Logged in, but could not load your account. Please try again.");
    } catch (err) {
      setError(errorMessage(err));
    } finally {
      setBusy(false);
    }
  }

  let content;
  if (status === "loading" || readyToEnter) {
    content = <Loading label={t("loading")} />;
  } else if (needsSetup) {
    content = <CompanySetup onDone={(tokens) => signIn(tokens)} />;
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

function CompanySetup({ onDone }: { onDone: (tokens: { accessToken: string; refreshToken: string }) => Promise<unknown> }) {
  const { t, lang } = useI18n();
  const { logout } = useAuth();
  const [form, setForm] = useState({
    name: "",
    businessType: "shop",
    lat: "",
    lng: "",
    address: "",
    openingTime: "09:00",
    closingTime: "19:00",
    weeklyOff: [0] as number[],
  });
  const [busy, setBusy] = useState(false);
  const [locating, setLocating] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const weekdays = lang === "hi" ? WEEKDAYS_HI : WEEKDAYS_EN;

  const set = <K extends keyof typeof form>(k: K, v: (typeof form)[K]) => setForm((f) => ({ ...f, [k]: v }));

  function useMyLocation() {
    if (!navigator.geolocation) {
      setError("Location is not available in this browser. Enter latitude/longitude manually.");
      return;
    }
    setLocating(true);
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        setForm((f) => ({ ...f, lat: pos.coords.latitude.toFixed(6), lng: pos.coords.longitude.toFixed(6) }));
        setLocating(false);
      },
      (err) => {
        setError(`Could not get location: ${err.message}`);
        setLocating(false);
      },
      { enableHighAccuracy: true, timeout: 15000 },
    );
  }

  async function submit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    const lat = Number(form.lat);
    const lng = Number(form.lng);
    if (!form.name.trim()) return setError("Enter your business name.");
    if (form.lat === "" || form.lng === "" || !Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180) {
      return setError("Enter a valid shop location (latitude and longitude) or use your current location.");
    }
    const body: CompanySetupInput = {
      name: form.name.trim(),
      businessType: form.businessType,
      location: { lat, lng, ...(form.address.trim() ? { address: form.address.trim() } : {}) },
      openingTime: form.openingTime,
      closingTime: form.closingTime || undefined,
      weeklyOff: form.weeklyOff,
      country: "IN",
      timezone: "Asia/Kolkata",
      currency: "INR",
    };
    setBusy(true);
    try {
      const res = await api.post<CompanySetupResult>("/company", body);
      await onDone({ accessToken: res.accessToken, refreshToken: res.refreshToken });
    } catch (err) {
      setError(errorMessage(err));
    } finally {
      setBusy(false);
    }
  }

  return (
    <form onSubmit={submit} className="space-y-4">
      <div>
        <h1 className="text-xl font-semibold">{t("setup_title")}</h1>
        <p className="text-sm text-slate-500">You can change everything later in Settings.</p>
      </div>
      <div className="grid gap-4 sm:grid-cols-2">
        <Field label={t("setup_business_name")}>
          {(id) => <Input id={id} value={form.name} onChange={(e) => set("name", e.target.value)} placeholder="Sharma Kirana Store" autoFocus />}
        </Field>
        <Field label={t("setup_business_type")}>
          {(id) => (
            <Select id={id} value={form.businessType} onChange={(e) => set("businessType", e.target.value)}>
              {BUSINESS_TYPES.map((b) => (
                <option key={b.value} value={b.value}>
                  {b.label}
                </option>
              ))}
            </Select>
          )}
        </Field>
      </div>
      <fieldset className="space-y-2 rounded-lg bg-slate-50 p-3">
        <div className="flex items-center justify-between">
          <legend className="text-sm font-medium text-slate-700">{t("setup_location")}</legend>
          <Button size="sm" variant="secondary" onClick={useMyLocation} loading={locating}>
            ⌖ {t("setup_use_location")}
          </Button>
        </div>
        <div className="grid gap-3 sm:grid-cols-2">
          <Field label="Latitude">
            {(id) => <Input id={id} inputMode="decimal" value={form.lat} onChange={(e) => set("lat", e.target.value)} placeholder="28.6139" />}
          </Field>
          <Field label="Longitude">
            {(id) => <Input id={id} inputMode="decimal" value={form.lng} onChange={(e) => set("lng", e.target.value)} placeholder="77.2090" />}
          </Field>
        </div>
        <Field label="Address (optional)">
          {(id) => <Input id={id} value={form.address} onChange={(e) => set("address", e.target.value)} />}
        </Field>
      </fieldset>
      <div className="grid gap-4 sm:grid-cols-2">
        <Field label={t("setup_opening")}>
          {(id) => <Input id={id} type="time" value={form.openingTime} onChange={(e) => set("openingTime", e.target.value)} required />}
        </Field>
        <Field label={t("setup_closing")}>
          {(id) => <Input id={id} type="time" value={form.closingTime} onChange={(e) => set("closingTime", e.target.value)} />}
        </Field>
      </div>
      <div>
        <div className="mb-1 text-sm font-medium text-slate-700">{t("setup_weekly_off")}</div>
        <div className="flex flex-wrap gap-3">
          {weekdays.map((d, i) => (
            <Checkbox
              key={d}
              label={d}
              checked={form.weeklyOff.includes(i)}
              onChange={(e) =>
                set("weeklyOff", e.target.checked ? [...form.weeklyOff, i].sort() : form.weeklyOff.filter((x) => x !== i))
              }
            />
          ))}
        </div>
      </div>
      {error && <Alert>{error}</Alert>}
      <div className="flex items-center justify-between gap-2">
        <Button variant="ghost" size="sm" onClick={() => void logout()}>
          {t("logout")}
        </Button>
        <Button type="submit" loading={busy}>
          {t("setup_finish")}
        </Button>
      </div>
    </form>
  );
}
