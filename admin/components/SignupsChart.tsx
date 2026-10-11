"use client";

import { useState } from "react";
import { dayMonth, niceTop } from "@/lib/format";
import { cx } from "./ui";

/**
 * New businesses per day (single series, columns). Each column is its own hover/focus target
 * with a tooltip; the peak is labelled; a table view carries every value.
 */
export function SignupsChart({ days }: { days: { date: string; count: number }[] }) {
  const [hover, setHover] = useState<number | null>(null);
  const max = Math.max(1, ...days.map((d) => d.count));
  const peak = days.reduce((best, d, i) => (d.count > days[best].count ? i : best), 0);
  const top = niceTop(max);
  const active = hover ?? null;

  return (
    <figure className="space-y-2">
      <div className="relative">
        {/* Recessive guides: baseline and the top value. */}
        <div className="pointer-events-none absolute inset-x-0 top-0 flex items-center gap-2 text-[11px] text-slate-400">
          <span className="tabular-nums">{top}</span>
          <span className="h-px flex-1 bg-slate-100" />
        </div>
        <div className="flex h-40 items-end gap-[2px] border-b border-slate-200 pt-5" onPointerLeave={() => setHover(null)}>
          {days.map((d, i) => {
            const h = d.count === 0 ? 0 : Math.max(4, (d.count / top) * 100);
            return (
              <button
                key={d.date}
                type="button"
                aria-label={`${dayMonth(d.date)}: ${d.count} new`}
                onPointerEnter={() => setHover(i)}
                onFocus={() => setHover(i)}
                onBlur={() => setHover(null)}
                onClick={() => setHover(i)}
                className="group relative flex h-full flex-1 items-end justify-center focus:outline-none"
              >
                <span
                  className={cx("block w-full max-w-6 rounded-t-[4px] transition-colors", active === i ? "bg-mint-700" : "bg-[#22965e]", d.count === 0 && "bg-transparent")}
                  style={{ height: `${h}%` }}
                />
                {i === peak && d.count > 0 && active === null && (
                  <span className="pointer-events-none absolute text-[11px] font-medium text-slate-700 tabular-nums" style={{ bottom: `calc(${h}% + 2px)` }}>
                    {d.count}
                  </span>
                )}
              </button>
            );
          })}
        </div>
        {active !== null && (
          <div
            role="status"
            className="pointer-events-none absolute -top-2 z-10 -translate-x-1/2 rounded-lg bg-slate-900 px-2.5 py-1.5 text-xs whitespace-nowrap text-white shadow"
            style={{ left: `${((active + 0.5) / days.length) * 100}%` }}
          >
            <span className="font-semibold tabular-nums">{days[active].count}</span> <span className="text-slate-300">new · {dayMonth(days[active].date)}</span>
          </div>
        )}
      </div>
      <figcaption className="flex justify-between text-[11px] text-slate-500">
        <span>{days[0] ? dayMonth(days[0].date) : ""}</span>
        <span>{days.at(-1) ? `Today, ${dayMonth(days.at(-1)!.date)}` : ""}</span>
      </figcaption>
      <details className="text-sm">
        <summary className="cursor-pointer text-xs text-slate-500 underline">See as table</summary>
        <table className="mt-2 w-full text-left text-xs">
          <thead className="text-slate-500">
            <tr>
              <th className="py-1 font-medium">Day</th>
              <th className="py-1 text-right font-medium">New businesses</th>
            </tr>
          </thead>
          <tbody className="tabular-nums">
            {[...days].reverse().map((d) => (
              <tr key={d.date} className="border-t border-slate-100">
                <td className="py-1">{dayMonth(d.date)}</td>
                <td className="py-1 text-right">{d.count}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </details>
    </figure>
  );
}
