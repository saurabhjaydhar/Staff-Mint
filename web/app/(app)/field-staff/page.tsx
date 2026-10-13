"use client";

import { useEffect, useMemo, useState } from "react";
import { useI18n, useToast } from "@/components/providers";
import { TrackMap, type MapMarker } from "@/components/TrackMap";
import { Alert, Button, Card, EmptyState, Field, Input, Loading, PageHeader } from "@/components/ui";
import { useAction, useAsync } from "@/hooks/useAsync";
import { api } from "@/lib/api";
import { saveBlob } from "@/lib/download";
import { formatDate, todayStr } from "@/lib/format";
import { fill } from "@/lib/i18n";
import type { LiveStaff, TrackDay } from "@/lib/types";

const COLOR: Record<string, string> = { live: "#1f9d66", recent: "#d97706", stale: "#94a3b8", ended: "#94a3b8" };
const km = (m: number) => (m / 1000).toFixed(m < 10000 ? 1 : 0);
const initials = (n: string) =>
  n
    .trim()
    .split(/\s+/)
    .slice(0, 2)
    .map((p) => p[0]?.toUpperCase() ?? "")
    .join("") || "?";
const time = (iso: string) => new Date(iso).toLocaleTimeString("en-IN", { hour: "numeric", minute: "2-digit" });

/** Owner/manager: where field staff are now, each person's day (route, stops, km), and Excel. */
export default function FieldStaffPage() {
  const { t } = useI18n();
  const toast = useToast();
  const action = useAction();
  const live = useAsync(() => api.get<LiveStaff[]>("/tracking/live"), "tracking:live");
  const [picked, setPicked] = useState<string | null>(null);
  const [date, setDate] = useState(todayStr());
  const [month, setMonth] = useState(todayStr().slice(0, 7));
  const day = useAsync(() => api.get<TrackDay>("/tracking/day", { employeeId: picked!, date }), picked ? `tracking:day:${picked}:${date}` : null);
  const { reload } = live;
  const [now, setNow] = useState(() => Date.now());

  // Fresh every minute while the page is open.
  useEffect(() => {
    const id = setInterval(() => {
      setNow(Date.now());
      reload();
    }, 60_000);
    return () => clearInterval(id);
  }, [reload]);

  const ago = (iso: string | null) => {
    if (!iso) return "";
    const m = Math.max(0, Math.round((now - new Date(iso).getTime()) / 60_000));
    return m < 1 ? t("trk_just_now") : m < 60 ? fill(t("trk_min_ago"), { n: m }) : fill(t("trk_h_ago"), { n: Math.floor(m / 60) });
  };
  const status = (s: LiveStaff) =>
    ({ waiting_consent: t("trk_waiting"), not_started: t("trk_not_in"), ended: t("trk_out") })[s.status as "waiting_consent" | "not_started" | "ended"] ?? "";

  const markers = useMemo<MapMarker[]>(
    () =>
      (live.data ?? [])
        .filter((p) => p.lat != null && p.lng != null)
        .map((p) => ({ lat: p.lat!, lng: p.lng!, label: initials(p.name), color: COLOR[p.status] ?? "#94a3b8", title: p.name, onClick: () => setPicked(p.employeeId) })),
    [live.data],
  );
  const dayRoute = useMemo<[number, number][]>(() => (day.data?.route ?? []).map((p) => [p.lat, p.lng]), [day.data]);
  const dayMarkers = useMemo<MapMarker[]>(
    () => [
      ...(day.data?.punches ?? []).map((p) => ({ lat: p.lat, lng: p.lng, label: p.type === "in" ? "▶" : "■", color: p.type === "in" ? "#1f9d66" : "#dc2626", title: time(p.at) })),
      ...(day.data?.stops ?? []).map((s, i) => ({ lat: s.lat, lng: s.lng, label: String(i + 1), color: "#b45309", title: s.place ?? undefined })),
    ],
    [day.data],
  );

  async function exportMonth() {
    const res = await action.run("export", () => api.download("/tracking/export", { month }, `field-staff-${month}.xlsx`));
    if (res.ok) {
      saveBlob(res.value.blob, res.value.filename);
      toast(fill(t("trk_downloaded"), { name: res.value.filename }));
    }
  }

  const person = live.data?.find((p) => p.employeeId === picked);
  return (
    <div className="space-y-5">
      <PageHeader title={t("nav_field")} subtitle={t("trk_subtitle")} />
      {live.errorText && <Alert onRetry={live.reload}>{live.errorText}</Alert>}
      {action.error && <Alert>{action.error}</Alert>}
      {!live.data ? (
        live.loading && <Loading />
      ) : live.data.length === 0 ? (
        <Card>
          <EmptyState>
            <p className="font-semibold text-slate-700">{t("trk_none_title")}</p>
            <p className="mt-1">{t("trk_none")}</p>
          </EmptyState>
        </Card>
      ) : (
        <div className="grid gap-5 lg:grid-cols-5">
          <div className="space-y-4 lg:col-span-3">
            {picked && day.data ? (
              <Card title={`${person?.name ?? day.data.name} · ${formatDate(date)}`}>
                <TrackMap route={dayRoute} markers={dayMarkers} height={420} />
                <div className="mt-3 flex flex-wrap items-end gap-4">
                  <div>
                    <div className="text-sm text-slate-500">{t("trk_travelled")}</div>
                    <div className="text-2xl font-semibold" data-testid="day-km">
                      {km(day.data.distanceM)} km
                    </div>
                  </div>
                  <div>
                    <div className="text-sm text-slate-500">{t("trk_stops")}</div>
                    <div className="text-2xl font-semibold">{day.data.stops.length}</div>
                  </div>
                  <Field label={t("trk_day")} className="ml-auto w-44">
                    {(id) => <Input id={id} type="date" value={date} max={todayStr()} onChange={(e) => e.target.value && setDate(e.target.value)} />}
                  </Field>
                  <Button variant="ghost" onClick={() => setPicked(null)}>
                    ✕
                  </Button>
                </div>
                {day.data.stops.length === 0 && day.data.route.length === 0 ? (
                  <p className="mt-3 text-sm text-slate-500">{t("trk_no_route")}</p>
                ) : (
                  <ol className="mt-3 divide-y divide-slate-100 rounded-lg ring-1 ring-slate-200">
                    {day.data.stops.map((s, i) => (
                      <li key={i} className="flex items-center gap-3 px-3 py-2" data-stop={i}>
                        <span className="grid h-6 w-6 place-items-center rounded-full bg-amber-700 text-xs font-bold text-white">{i + 1}</span>
                        <div className="flex-1">
                          <div className="font-medium">{s.place ?? fill(t("trk_stop_n"), { n: i + 1 })}</div>
                          <div className="text-sm text-slate-500">
                            {time(s.from)} – {time(s.to)} · {fill(t("trk_minutes"), { n: s.minutes })}
                          </div>
                        </div>
                      </li>
                    ))}
                  </ol>
                )}
              </Card>
            ) : (
              <Card>
                <TrackMap markers={markers} height={420} />
              </Card>
            )}
            {picked && day.loading && <Loading />}
          </div>
          <div className="space-y-4 lg:col-span-2">
            <Card title={t("trk_people")}>
              <ul className="divide-y divide-slate-100">
                {live.data.map((p) => (
                  <li key={p.employeeId}>
                    <button
                      type="button"
                      onClick={() => setPicked(p.employeeId)}
                      className={`flex w-full items-center gap-3 px-1 py-2 text-left ${picked === p.employeeId ? "bg-mint-50" : ""}`}
                      data-live={p.employeeId}
                    >
                      <span className="grid h-9 w-9 shrink-0 place-items-center rounded-full text-sm font-bold text-white" style={{ background: COLOR[p.status] ?? "#94a3b8" }}>
                        {initials(p.name)}
                      </span>
                      <span className="flex-1">
                        <span className="block font-medium text-slate-900">{p.name}</span>
                        <span className="block text-sm text-slate-500">
                          {[p.status !== "waiting_consent" ? ago(p.lastPingAt) : "", status(p), p.near ? fill(t("trk_near"), { place: p.near }) : "", p.distanceM ? `${km(p.distanceM)} km` : ""]
                            .filter(Boolean)
                            .join(" · ")}
                        </span>
                      </span>
                    </button>
                  </li>
                ))}
              </ul>
            </Card>
            <Card title={t("trk_export")}>
              <div className="flex items-end gap-3">
                <Field label={t("month")} className="w-44">
                  {(id) => <Input id={id} type="month" value={month} onChange={(e) => e.target.value && setMonth(e.target.value)} />}
                </Field>
                <Button variant="secondary" loading={action.busy === "export"} onClick={exportMonth}>
                  {t("trk_excel")}
                </Button>
              </div>
              <p className="mt-2 text-xs text-slate-500">{t("trk_export_hint")}</p>
            </Card>
          </div>
        </div>
      )}
    </div>
  );
}
