"use client";

import { useState } from "react";
import { OverrideModal, type OverrideTarget } from "@/components/OverrideModal";
import { useI18n, useToast } from "@/components/providers";
import { Alert, Badge, Button, Card, EmptyState, Field, Input, Loading, PageHeader, Segmented, Table, Td, Th, cx } from "@/components/ui";
import { useAction, useAsync } from "@/hooks/useAsync";
import { api } from "@/lib/api";
import { STATUS_STYLES, overrideDefault, statusStyle } from "@/lib/attendance";
import { currentMonth, dayOfMonth, formatDate, formatMinutes, formatMonth, formatTime, todayStr, weekdayOf, WEEKDAYS_EN, WEEKDAYS_HI } from "@/lib/format";
import type { DayRow, DisplayStatus, MonthGrid } from "@/lib/types";

export default function AttendancePage() {
  const { t } = useI18n();
  const [view, setView] = useState<"month" | "day">("month");
  const [month, setMonth] = useState(() => currentMonth());
  const [date, setDate] = useState(() => todayStr());
  const [target, setTarget] = useState<OverrideTarget | null>(null);
  const [version, setVersion] = useState(0);
  const toast = useToast();

  return (
    <div className="space-y-5">
      <PageHeader
        title={t("nav_attendance")}
        subtitle="Click any cell to correct attendance. Every change needs a reason and is saved in the audit log."
        actions={
          <Segmented
            value={view}
            onChange={setView}
            options={[
              { value: "month", label: "Month grid" },
              { value: "day", label: "Day view" },
            ]}
          />
        }
      />
      {view === "month" ? (
        <MonthView
          month={month}
          onMonth={setMonth}
          version={version}
          onCell={setTarget}
          onOpenDay={(d) => {
            setDate(d);
            setView("day");
          }}
        />
      ) : (
        <DayView date={date} onDate={setDate} version={version} onOverride={setTarget} />
      )}
      <OverrideModal
        target={target}
        onClose={() => setTarget(null)}
        onSaved={() => {
          setTarget(null);
          setVersion((v) => v + 1);
          toast("Attendance updated");
        }}
      />
    </div>
  );
}

function Legend() {
  const shown: DisplayStatus[] = ["present", "late", "absent", "half_day", "leave", "week_off", "holiday", "not_marked"];
  return (
    <div className="flex flex-wrap gap-2 text-xs">
      {shown.map((s) => {
        const st = STATUS_STYLES[s];
        return (
          <span key={s} className="inline-flex items-center gap-1">
            <span className={cx("inline-grid h-5 min-w-6 place-items-center rounded px-1 font-semibold", st.className)}>{st.code}</span>
            {st.label}
          </span>
        );
      })}
    </div>
  );
}

function MonthView({
  month,
  onMonth,
  version,
  onCell,
  onOpenDay,
}: {
  month: string;
  onMonth: (m: string) => void;
  version: number;
  onCell: (t: OverrideTarget) => void;
  onOpenDay: (d: string) => void;
}) {
  const { t, lang } = useI18n();
  const grid = useAsync(() => api.get<MonthGrid>("/attendance/month", { month }), `month:${month}:${version}`);
  const weekdays = lang === "hi" ? WEEKDAYS_HI : WEEKDAYS_EN;
  const data = grid.data;
  const today = todayStr();

  const totalKeys = data ? [...new Set(data.rows.flatMap((r) => Object.keys(r.totals ?? {})))] : [];

  return (
    <Card padded={false}>
      <div className="flex flex-wrap items-end justify-between gap-3 border-b border-slate-100 p-4">
        <Field label={t("month")} className="w-48">
          {(id) => <Input id={id} type="month" value={month} onChange={(e) => e.target.value && onMonth(e.target.value)} />}
        </Field>
        <Legend />
      </div>
      {grid.errorText && <Alert className="m-4" onRetry={grid.reload}>{grid.errorText}</Alert>}
      {!data && grid.loading ? (
        <Loading />
      ) : !data || data.rows.length === 0 ? (
        <EmptyState>No attendance for {formatMonth(month)}.</EmptyState>
      ) : (
        <div className={cx("overflow-x-auto", grid.loading && "opacity-60")}>
          <table className="text-xs">
            <thead>
              <tr className="bg-slate-50">
                <th className="sticky left-0 z-10 min-w-44 bg-slate-50 px-3 py-2 text-left font-semibold text-slate-600">{t("employee")}</th>
                {data.days.map((d) => {
                  const wd = weekdayOf(d);
                  return (
                    <th key={d} className={cx("px-0.5 py-1 text-center font-medium", d === today ? "text-mint-700" : wd === 0 ? "text-red-500" : "text-slate-500")}>
                      <button type="button" className="rounded px-1 hover:bg-slate-200" title={`Open ${formatDate(d)}`} onClick={() => onOpenDay(d)}>
                        <div>{dayOfMonth(d)}</div>
                        <div className="text-[10px] font-normal">{weekdays[wd].slice(0, 2)}</div>
                      </button>
                    </th>
                  );
                })}
                {totalKeys.map((k) => (
                  <th key={k} className="px-2 py-1 text-center font-semibold capitalize text-slate-600">
                    {k.replace(/([A-Z])/g, " $1").replace(/_/g, " ")}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {data.rows.map((row) => (
                <tr key={row.employee.id} className="hover:bg-slate-50/60">
                  <td className="sticky left-0 z-10 bg-white px-3 py-1.5 font-medium text-slate-800">
                    {row.employee.name}
                    {row.employee.designation && <div className="text-[11px] font-normal text-slate-500">{row.employee.designation}</div>}
                  </td>
                  {data.days.map((d) => {
                    const s = row.days[d] ?? "not_marked";
                    const st = statusStyle(s);
                    const future = d > today;
                    return (
                      <td key={d} className="px-0.5 py-1 text-center">
                        <button
                          type="button"
                          disabled={future}
                          title={`${row.employee.name} · ${formatDate(d)} · ${st.label}`}
                          onClick={() => onCell({ employeeId: row.employee.id, employeeName: row.employee.name, date: d, status: overrideDefault(s) })}
                          className={cx(
                            "h-7 w-8 rounded text-[11px] font-semibold transition hover:ring-2 hover:ring-mint-400 disabled:cursor-default disabled:opacity-40 disabled:hover:ring-0",
                            st.className,
                          )}
                        >
                          {st.code}
                        </button>
                      </td>
                    );
                  })}
                  {totalKeys.map((k) => (
                    <td key={k} className="px-2 py-1 text-center font-medium text-slate-700">
                      {row.totals?.[k] ?? "—"}
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </Card>
  );
}

const DISPLAY_TONE: Record<DisplayStatus, "mint" | "amber" | "red" | "sky" | "violet" | "slate"> = {
  present: "mint",
  late: "amber",
  checked_in: "mint",
  absent: "red",
  half_day: "amber",
  leave: "sky",
  holiday: "violet",
  week_off: "slate",
  not_marked: "slate",
};

function DayView({
  date,
  onDate,
  version,
  onOverride,
}: {
  date: string;
  onDate: (d: string) => void;
  version: number;
  onOverride: (t: OverrideTarget) => void;
}) {
  const { t } = useI18n();
  const toast = useToast();
  const rows = useAsync(() => api.get<DayRow[]>("/attendance", { date }), `day:${date}:${version}`);
  const action = useAction();

  async function decide(attendanceId: string, punchId: string, approve: boolean) {
    const res = await action.run(`punch:${punchId}`, () => api.post(`/attendance/${attendanceId}/punches/${punchId}/decision`, { approve }));
    if (res.ok) {
      toast(approve ? "Punch approved" : "Punch rejected");
      rows.reload();
    }
  }

  return (
    <Card padded={false}>
      <div className="flex flex-wrap items-end gap-3 border-b border-slate-100 p-4">
        <Field label={t("date")} className="w-48">
          {(id) => <Input id={id} type="date" value={date} max={todayStr()} onChange={(e) => e.target.value && onDate(e.target.value)} />}
        </Field>
        <span className="pb-2 text-sm text-slate-500">{formatDate(date)}</span>
      </div>
      {rows.errorText && <Alert className="m-4" onRetry={rows.reload}>{rows.errorText}</Alert>}
      {action.error && <Alert className="m-4">{action.error}</Alert>}
      {!rows.data && rows.loading ? (
        <Loading />
      ) : !rows.data?.length ? (
        <EmptyState>No staff for this day.</EmptyState>
      ) : (
        <Table>
          <thead>
            <tr>
              <Th>{t("employee")}</Th>
              <Th>{t("status")}</Th>
              <Th>Punches</Th>
              <Th>Late</Th>
              <Th>Worked</Th>
              <Th>Notes</Th>
              <Th className="text-right">{t("actions")}</Th>
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-100">
            {rows.data.map((r) => {
              const rec = r.record;
              return (
                <tr key={r.employee.id}>
                  <Td>
                    <div className="font-medium">{r.employee.name}</div>
                    <div className="text-xs text-slate-500">{r.employee.designation || r.employee.phone}</div>
                  </Td>
                  <Td>
                    <Badge tone={DISPLAY_TONE[r.displayStatus] ?? "slate"}>{statusStyle(r.displayStatus).label}</Badge>
                    {rec?.leaveType && <span className="ml-1 text-xs text-slate-500">({rec.leaveType})</span>}
                  </Td>
                  <Td>
                    <div className="space-y-1">
                      {(rec?.punches ?? []).map((p) => (
                        <div key={p.id} className="flex flex-wrap items-center gap-1 text-xs">
                          <span className="font-medium uppercase">{p.type}</span> {formatTime(p.serverTime)}
                          {p.distanceM != null && <span className="text-slate-500">· {Math.round(p.distanceM)} m</span>}
                          {p.flags.map((f) => (
                            <Badge key={f} tone="amber">
                              {f.replace(/_/g, " ")}
                            </Badge>
                          ))}
                          {p.selfieUrl && (
                            <a className="text-mint-700 underline" href={p.selfieUrl} target="_blank" rel="noreferrer">
                              selfie
                            </a>
                          )}
                          {p.approval === "pending" && rec && (
                            <>
                              <Button size="sm" className="h-6 px-2 text-xs" loading={action.busy === `punch:${p.id}`} onClick={() => decide(rec.id, p.id, true)}>
                                {t("approve")}
                              </Button>
                              <Button size="sm" variant="secondary" className="h-6 px-2 text-xs" disabled={!!action.busy} onClick={() => decide(rec.id, p.id, false)}>
                                {t("reject")}
                              </Button>
                            </>
                          )}
                          {p.approval === "rejected" && <Badge tone="red">rejected</Badge>}
                        </div>
                      ))}
                      {!rec?.punches?.length && <span className="text-xs text-slate-400">—</span>}
                    </div>
                  </Td>
                  <Td className="text-xs">{rec?.lateMinutes ? formatMinutes(rec.lateMinutes) : "—"}</Td>
                  <Td className="text-xs">{rec?.workedMinutes ? formatMinutes(rec.workedMinutes) : "—"}</Td>
                  <Td className="max-w-48 text-xs text-slate-600">
                    {rec?.overridden && (
                      <div>
                        <Badge tone="violet">edited</Badge> {rec.overrideReason}
                      </div>
                    )}
                    {rec?.flags?.length ? <div>{rec.flags.join(", ").replace(/_/g, " ")}</div> : null}
                  </Td>
                  <Td className="text-right">
                    <Button
                      size="sm"
                      variant="secondary"
                      onClick={() =>
                        onOverride({ employeeId: r.employee.id, employeeName: r.employee.name, date, status: overrideDefault(r.displayStatus) })
                      }
                    >
                      Change
                    </Button>
                  </Td>
                </tr>
              );
            })}
          </tbody>
        </Table>
      )}
    </Card>
  );
}
