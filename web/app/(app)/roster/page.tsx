"use client";

import Link from "next/link";
import { useMemo, useState } from "react";
import { useI18n, useToast } from "@/components/providers";
import { Alert, Badge, Button, Card, Checkbox, EmptyState, Loading, Modal, PageHeader } from "@/components/ui";
import { useAction, useAsync } from "@/hooks/useAsync";
import { api, isApiError } from "@/lib/api";
import { fill } from "@/lib/i18n";
import { todayStr } from "@/lib/format";
import type { RosterCell, RosterWeek, Shift } from "@/lib/types";

/** Each shift keeps one colour (by start time, as the server sorts them); days off are grey. */
const PALETTE = [
  "bg-mint-50 text-mint-800 ring-mint-200",
  "bg-indigo-50 text-indigo-700 ring-indigo-200",
  "bg-amber-50 text-amber-800 ring-amber-200",
  "bg-orange-50 text-orange-700 ring-orange-200",
];
const OFF = "bg-slate-100 text-slate-500 ring-slate-200";

const addDays = (date: string, n: number) => {
  const d = new Date(`${date}T00:00:00`);
  d.setDate(d.getDate() + n);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
};
const mondayOf = (date: string) => addDays(date, -((new Date(`${date}T00:00:00`).getDay() + 6) % 7));
const hours = (s: Shift) => `${s.start}–${s.end}`;

export default function RosterPage() {
  const { t, lang } = useI18n();
  const toast = useToast();
  const [weekStart, setWeekStart] = useState(() => mondayOf(todayStr()));
  const [sending, setSending] = useState(false);
  const [repeating, setRepeating] = useState(false);
  const week = useAsync(() => api.get<RosterWeek>("/roster", { week: weekStart }), `roster:${weekStart}`);
  const action = useAction();
  const locale = lang === "hi" ? "hi-IN" : "en-IN";
  const dayName = (d: string, style: "short" | "long" = "short") => new Date(`${d}T00:00:00`).toLocaleDateString(locale, { weekday: style });
  const dayMonth = (d: string) => new Date(`${d}T00:00:00`).toLocaleDateString(locale, { day: "numeric", month: "short" });
  const range = `${dayMonth(weekStart)} – ${dayMonth(addDays(weekStart, 6))}`;
  const isThisWeek = weekStart === mondayOf(todayStr());

  async function setCell(employeeId: string, date: string, value: string) {
    const kind = value === "off" || value === "usual" ? value : "shift";
    const res = await action.run(`cell:${employeeId}:${date}`, () =>
      api.put("/roster/cells", { cells: [{ employeeId, date, kind, shiftId: kind === "shift" ? value : null }] }),
    );
    if (res.ok) week.reload();
  }
  async function copyLastWeek() {
    const res = await action.run("copy", () => api.post<{ copied: number }>("/roster/copy-last-week", { week: weekStart }));
    if (res.ok) {
      toast(res.value.copied ? t("roster_copied") : t("roster_copied_none"));
      week.reload();
    }
  }

  const planError = isApiError(week.error) && week.error.code === "FEATURE_NOT_IN_PLAN";
  const w = week.data;
  return (
    <div className="space-y-5">
      <PageHeader
        title={t("nav_roster")}
        subtitle={isThisWeek ? fill(t("roster_this_week"), { range }) : range}
        actions={
          <div className="flex flex-wrap items-center gap-2">
            <Button variant="secondary" onClick={() => setWeekStart(addDays(weekStart, -7))} aria-label="Previous week">
              ‹
            </Button>
            <Button variant="secondary" onClick={() => setWeekStart(addDays(weekStart, 7))} aria-label="Next week">
              ›
            </Button>
            {w && (
              <>
                <Button variant="secondary" loading={action.busy === "copy"} onClick={copyLastWeek}>
                  {t("roster_copy")}
                </Button>
                <Button onClick={() => setSending(true)}>{t("roster_send")}</Button>
              </>
            )}
          </div>
        }
      />
      {action.error && <Alert>{action.error}</Alert>}
      {planError ? (
        <Card>
          <EmptyState>
            {t("roster_needs_plan")}{" "}
            <Link href="/billing" className="font-medium text-mint-700 underline">
              {t("trial_see_plans")}
            </Link>
          </EmptyState>
        </Card>
      ) : week.errorText ? (
        <Alert onRetry={week.reload}>{week.errorText}</Alert>
      ) : !w ? (
        <Loading />
      ) : (
        <>
          <div className="flex flex-wrap items-center gap-3">
            <Badge tone={w.notSent ? "amber" : "mint"}>{w.notSent === 1 ? t("roster_not_sent_one") : w.notSent ? fill(t("roster_not_sent"), { n: w.notSent }) : t("roster_all_sent")}</Badge>
            {w.shifts.length < 2 && <span className="text-sm text-slate-500">{t("roster_add_shifts")}</span>}
          </div>
          <RepeatLine week={w} onOpen={() => setRepeating(true)} />
          <Card padded={false}>
            <div className="overflow-x-auto">
              <table className="w-full min-w-[760px] text-sm">
                <thead>
                  <tr className="border-b border-slate-100 text-left">
                    <th className="w-48 px-4 py-2 font-medium text-slate-500">{t("roster_staff")}</th>
                    {w.days.map((d) => (
                      <th key={d.date} className="px-1 py-2 text-center font-medium">
                        <div className={d.holiday ? "text-orange-600" : "text-slate-700"}>{dayName(d.date)}</div>
                        <div className="text-xs font-normal text-slate-400">{d.holiday ?? new Date(`${d.date}T00:00:00`).getDate()}</div>
                      </th>
                    ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-50">
                  {w.staff
                    .filter((p) => p.cells.some((c) => c.employed))
                    .map((p) => (
                      <tr key={p.id}>
                        <td className="px-4 py-1.5">
                          <div className="font-medium">{p.name}</div>
                          {p.designation && <div className="text-xs text-slate-400">{p.designation}</div>}
                        </td>
                        {p.cells.map((c) => (
                          <td key={c.date} className="px-1 py-1.5">
                            <CellPicker
                              week={w}
                              cell={c}
                              label={`${p.name} · ${dayName(c.date, "long")}`}
                              busy={action.busy === `cell:${p.id}:${c.date}`}
                              onChange={(v) => setCell(p.id, c.date, v)}
                            />
                          </td>
                        ))}
                      </tr>
                    ))}
                </tbody>
              </table>
            </div>
            <div className="flex flex-wrap items-center gap-3 border-t border-slate-100 px-4 py-3 text-xs text-slate-500">
              {w.shifts.map((s, i) => (
                <span key={s.id} className={`rounded-md px-2 py-0.5 ring-1 ${PALETTE[i % PALETTE.length]}`}>
                  {s.name} {hours(s)}
                </span>
              ))}
              <span className={`rounded-md px-2 py-0.5 ring-1 ${OFF}`}>{t("roster_off")}</span>
              <span>{t("roster_hint")}</span>
            </div>
          </Card>
          <SendModal
            open={sending}
            week={w}
            dayName={(d) => dayName(d, "long")}
            onFix={async (employeeId, date) => {
              await setCell(employeeId, date, "off");
            }}
            onClose={() => setSending(false)}
            onSent={(n) => {
              setSending(false);
              toast(fill(t("roster_sent"), { n }));
              week.reload();
            }}
          />
          {repeating && (
          <RepeatModal
            open
            week={w}
            onClose={() => setRepeating(false)}
            onDone={(on) => {
              setRepeating(false);
              toast(on ? t("roster_repeat_on_done") : t("roster_repeat_off_done"));
              week.reload();
            }}
          />
          )}
        </>
      )}
    </div>
  );
}

/** One box of the grid: a shift picker coloured like the shift, with leave and "not sent yet" marked. */
function CellPicker({ week, cell, label, busy, onChange }: { week: RosterWeek; cell: RosterCell; label: string; busy: boolean; onChange: (v: string) => void }) {
  const { t } = useI18n();
  if (!cell.employed) return <div className="h-9 rounded-md bg-slate-50" />;
  const i = week.shifts.findIndex((s) => s.id === cell.shiftId);
  const colour = cell.kind === "off" || i < 0 ? OFF : PALETTE[i % PALETTE.length];
  const value = cell.kind === "off" ? "off" : (cell.shiftId ?? "off");
  return (
    <div className="relative">
      {cell.leave && <span className="absolute -top-1.5 left-1 z-10 rounded bg-red-100 px-1 text-[10px] font-semibold text-red-700">{t("roster_on_leave")}</span>}
      <select
        aria-label={label}
        disabled={busy}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        className={`h-9 w-full cursor-pointer appearance-none rounded-md px-1.5 text-center text-xs font-semibold ring-1 ${colour} ${cell.changed ? "outline-2 outline-offset-1 outline-amber-400" : ""}`}
      >
        {/* Just the name in the box; the hours are in the key under the grid. */}
        {week.shifts.map((s) => (
          <option key={s.id} value={s.id} title={hours(s)}>
            {s.name}
          </option>
        ))}
        <option value="off">{t("roster_off")}</option>
        {!cell.usual && <option value="usual">{t("roster_usual")}</option>}
      </select>
    </div>
  );
}

function RepeatLine({ week, onOpen }: { week: RosterWeek; onOpen: () => void }) {
  const { t } = useI18n();
  const r = week.repeat;
  const locked = !r && !week.repeatAllowed;
  return (
    <Card>
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <div className="font-semibold">{r ? (r.mode === "rotate" ? t("roster_repeat_swap_on") : t("roster_repeat_same_on")) : t("roster_repeat")}</div>
          <div className="text-sm text-slate-500">
            {r ? (r.autoSend ? t("roster_repeat_auto_on") : t("roster_repeat_auto_off")) : locked ? t("roster_repeat_needs_plan") : t("roster_repeat_off_hint")}
          </div>
        </div>
        {locked ? (
          <Link href="/billing" className="text-sm font-medium text-mint-700 underline">
            {t("trial_see_plans")}
          </Link>
        ) : (
          <Button variant="secondary" onClick={onOpen}>
            {r ? t("roster_change") : t("roster_set_up")}
          </Button>
        )}
      </div>
    </Card>
  );
}

function RepeatModal({ open, week, onClose, onDone }: { open: boolean; week: RosterWeek; onClose: () => void; onDone: (on: boolean) => void }) {
  const { t } = useI18n();
  const [mode, setMode] = useState<"off" | "same" | "rotate">(week.repeat?.mode ?? "same");
  const [autoSend, setAutoSend] = useState(week.repeat?.autoSend ?? false);
  const action = useAction();
  // Shifts used this week, in start-time order: the order people move through when shifts swap.
  const used = useMemo(() => {
    const ids = new Set(week.staff.flatMap((p) => p.cells.filter((c) => c.employed && c.kind === "shift" && c.shiftId).map((c) => c.shiftId!)));
    return week.shifts.filter((s) => ids.has(s.id));
  }, [week]);
  // "Morning → Evening → Morning": back to the start shows it keeps going round.
  const chain = [...used.map((s) => s.name), used[0]?.name].filter(Boolean).join(" → ");
  const options: { value: typeof mode; title: string; hint?: string; disabled?: boolean }[] = [
    { value: "off", title: t("roster_repeat_no") },
    { value: "same", title: t("roster_repeat_same"), hint: t("roster_repeat_same_hint"), disabled: !week.repeatAllowed },
    {
      value: "rotate",
      title: t("roster_repeat_swap"),
      hint: used.length < 2 ? t("roster_repeat_swap_needs") : fill(t("roster_repeat_swap_hint"), { chain }),
      disabled: !week.repeatAllowed || used.length < 2,
    },
  ];
  async function save() {
    const res = await action.run("save", () =>
      mode === "off" ? api.delete("/roster/repeat") : api.post("/roster/repeat", { week: week.weekStart, mode, autoSend }),
    );
    if (res.ok) onDone(mode !== "off");
  }
  return (
    <Modal
      open={open}
      onClose={onClose}
      title={t("roster_repeat_title")}
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>
            {t("cancel")}
          </Button>
          <Button loading={action.busy === "save"} onClick={save}>
            {t("save")}
          </Button>
        </>
      }
    >
      {action.error && <Alert className="mb-3">{action.error}</Alert>}
      <div className="space-y-2">
        {options.map((o) => (
          <label
            key={o.value}
            className={`flex cursor-pointer items-start gap-3 rounded-lg border p-3 ${mode === o.value ? "border-mint-500 bg-mint-50" : "border-slate-200"} ${o.disabled ? "cursor-not-allowed opacity-50" : ""}`}
          >
            <input type="radio" name="repeat" className="mt-1" checked={mode === o.value} disabled={o.disabled} onChange={() => setMode(o.value)} />
            <span>
              <span className="block font-medium">{o.title}</span>
              {o.hint && <span className="block text-sm text-slate-500">{o.hint}</span>}
            </span>
          </label>
        ))}
      </div>
      {mode !== "off" && <Checkbox className="mt-3" label={t("roster_repeat_auto")} checked={autoSend} onChange={(e) => setAutoSend(e.target.checked)} />}
    </Modal>
  );
}

function SendModal({
  open,
  week,
  dayName,
  onFix,
  onClose,
  onSent,
}: {
  open: boolean;
  week: RosterWeek;
  dayName: (d: string) => string;
  onFix: (employeeId: string, date: string) => Promise<void>;
  onClose: () => void;
  onSent: (n: number) => void;
}) {
  const { t } = useI18n();
  const action = useAction();
  const people = week.staff.filter((p) => p.cells.some((c) => c.changed)).length;
  async function send() {
    const res = await action.run("send", () => api.post<{ sentTo: number }>("/roster/send", { week: week.weekStart }));
    if (res.ok) onSent(res.value.sentTo);
  }
  return (
    <Modal
      open={open}
      onClose={onClose}
      title={t("roster_send_title")}
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>
            {t("cancel")}
          </Button>
          <Button disabled={!people} loading={action.busy === "send"} onClick={send}>
            {people ? fill(t("roster_send_n"), { n: people }) : t("roster_nothing")}
          </Button>
        </>
      }
    >
      {action.error && <Alert className="mb-3">{action.error}</Alert>}
      <p className="text-sm text-slate-600">{t("roster_send_body")}</p>
      {week.problems.length > 0 && (
        <div className="mt-4 space-y-2">
          <div className="text-sm font-semibold">{fill(t("roster_fix_first"), { n: week.problems.length })}</div>
          {week.problems.map((p) => (
            <div key={`${p.employeeId}:${p.date}:${p.type}`} className="flex items-center justify-between gap-3 rounded-lg bg-amber-50 px-3 py-2 text-sm">
              <span>
                {p.type === "leave_working"
                  ? fill(t("roster_problem_leave"), { name: p.name, day: dayName(p.date) })
                  : fill(t("roster_problem_no_off"), { name: p.name })}
              </span>
              <Button size="sm" variant="secondary" loading={action.busy === `fix:${p.employeeId}:${p.date}`} onClick={() => action.run(`fix:${p.employeeId}:${p.date}`, () => onFix(p.employeeId, p.date))}>
                {p.type === "leave_working" ? t("roster_make_off") : fill(t("roster_give_off"), { day: dayName(p.date) })}
              </Button>
            </div>
          ))}
        </div>
      )}
    </Modal>
  );
}
