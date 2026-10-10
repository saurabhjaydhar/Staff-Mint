"use client";

import { useState, type FormEvent } from "react";
import { api, errorMessage } from "@/lib/api";
import { WEEKDAYS_EN, WEEKDAYS_HI } from "@/lib/format";
import { getDeviceId } from "@/lib/tokens";
import type { CompanySetupInput, CompanySetupResult } from "@/lib/types";
import { useAuth, useI18n } from "./providers";
import { Alert, Button, Checkbox, Field, Input, Select } from "./ui";

const BUSINESS_TYPES = [
  { value: "shop", label: "Shop / Retail" },
  { value: "restaurant", label: "Restaurant / Café" },
  { value: "clinic", label: "Clinic / Pharmacy" },
  { value: "salon", label: "Salon / Spa" },
  { value: "office", label: "Office" },
  { value: "factory", label: "Factory / Workshop" },
  { value: "other", label: "Other" },
];

/**
 * Business setup form. `another`: a signed-in person (owner, staff or CA
 * elsewhere) adding one more business; Cancel goes back instead of logging out.
 */
export function CompanySetup({
  onDone,
  another = false,
  onCancel,
}: {
  onDone: (tokens: { accessToken: string; refreshToken: string }) => Promise<unknown>;
  another?: boolean;
  onCancel?: () => void;
}) {
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
      // This browser moves into the new business; its old session token is retired.
      const res = await api.post<CompanySetupResult>("/company", { ...body, deviceId: getDeviceId(), refreshToken: api.tokens.get()?.refreshToken });
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
        <h1 className="text-xl font-semibold">{another ? t("acc_new_title") : t("setup_title")}</h1>
        <p className="text-sm text-slate-500">You can change everything later in Settings.</p>
      </div>
      {another ? (
        <p className="rounded-lg bg-mint-50 px-3 py-2 text-sm text-mint-900 ring-1 ring-mint-200">{t("acc_new_hint")}</p>
      ) : (
        <p className="rounded-lg bg-amber-50 px-3 py-2 text-sm text-amber-900 ring-1 ring-amber-200">{t("setup_staff_note")}</p>
      )}
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
        <Button variant="ghost" size="sm" onClick={() => (another && onCancel ? onCancel() : void logout())}>
          {another ? t("cancel") : t("logout")}
        </Button>
        <Button type="submit" loading={busy}>
          {t("setup_finish")}
        </Button>
      </div>
    </form>
  );
}
