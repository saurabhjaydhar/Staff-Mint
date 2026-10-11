"use client";

import Link from "next/link";
import { useEffect, useId, useRef, type ButtonHTMLAttributes, type InputHTMLAttributes, type ReactNode } from "react";
import type { Tone } from "@/lib/format";

export const cx = (...c: (string | false | null | undefined)[]) => c.filter(Boolean).join(" ");

type Variant = "primary" | "secondary" | "ghost" | "danger";
const VARIANTS: Record<Variant, string> = {
  primary: "bg-mint-600 text-white hover:bg-mint-700 active:bg-mint-800 disabled:bg-mint-300",
  secondary: "bg-white text-slate-800 ring-1 ring-slate-300 hover:bg-slate-50 active:bg-slate-100 disabled:text-slate-400",
  ghost: "text-slate-700 hover:bg-slate-100 active:bg-slate-200 disabled:text-slate-400",
  danger: "bg-red-600 text-white hover:bg-red-700 active:bg-red-800 disabled:bg-red-300",
};

export function Button({
  variant = "primary",
  size = "md",
  loading,
  className,
  children,
  type,
  disabled,
  ...rest
}: ButtonHTMLAttributes<HTMLButtonElement> & { variant?: Variant; size?: "sm" | "md" | "lg"; loading?: boolean }) {
  return (
    <button
      type={type ?? "button"}
      disabled={disabled || loading}
      className={cx(
        "inline-flex items-center justify-center gap-2 rounded-xl font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-mint-500 disabled:cursor-not-allowed",
        size === "sm" ? "h-9 px-3 text-sm" : size === "lg" ? "h-12 px-5 text-base" : "h-11 px-4 text-sm",
        VARIANTS[variant],
        className,
      )}
      {...rest}
    >
      {loading && <Spinner className="h-4 w-4" />}
      {children}
    </button>
  );
}

export function Spinner({ className }: { className?: string }) {
  return <span aria-hidden className={cx("inline-block animate-spin rounded-full border-2 border-current border-r-transparent", className ?? "h-5 w-5")} />;
}

const TONES: Record<Tone, string> = {
  mint: "bg-mint-50 text-mint-800 ring-mint-200",
  amber: "bg-amber-50 text-amber-800 ring-amber-200",
  red: "bg-red-50 text-red-700 ring-red-200",
  slate: "bg-slate-100 text-slate-700 ring-slate-200",
  sky: "bg-sky-50 text-sky-800 ring-sky-200",
  violet: "bg-violet-50 text-violet-800 ring-violet-200",
};

export function Badge({ tone = "slate", children }: { tone?: Tone; children: ReactNode }) {
  return <span className={cx("inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium ring-1 whitespace-nowrap", TONES[tone])}>{children}</span>;
}

export function Card({ title, action, children, className, padded = true }: { title?: ReactNode; action?: ReactNode; children: ReactNode; className?: string; padded?: boolean }) {
  return (
    <section className={cx("rounded-2xl bg-white ring-1 ring-slate-200", className)}>
      {(title || action) && (
        <header className="flex items-center justify-between gap-3 border-b border-slate-100 px-4 py-3">
          <h2 className="text-sm font-semibold text-slate-800">{title}</h2>
          {action}
        </header>
      )}
      <div className={padded ? "p-4" : undefined}>{children}</div>
    </section>
  );
}

/** Screen title row; sticky on phones so the title and actions stay in reach. */
export function PageHeader({ title, subtitle, back, actions }: { title: ReactNode; subtitle?: ReactNode; back?: string; actions?: ReactNode }) {
  return (
    <div className="sticky top-0 z-20 -mx-4 mb-4 flex items-center gap-2 bg-slate-50/95 px-4 py-3 backdrop-blur md:static md:mx-0 md:bg-transparent md:px-0 md:backdrop-blur-none">
      {back && (
        <Link href={back} aria-label="Back" className="-ml-2 grid h-10 w-10 place-items-center rounded-full text-xl text-slate-600 hover:bg-slate-200">
          ‹
        </Link>
      )}
      <div className="min-w-0 flex-1">
        <h1 className="truncate text-lg font-semibold text-slate-900 md:text-2xl">{title}</h1>
        {subtitle && <p className="truncate text-sm text-slate-500">{subtitle}</p>}
      </div>
      {actions}
    </div>
  );
}

export function Alert({ tone = "red", children, onRetry }: { tone?: "red" | "amber" | "mint" | "sky"; children: ReactNode; onRetry?: () => void }) {
  const styles = { red: "bg-red-50 text-red-800 ring-red-200", amber: "bg-amber-50 text-amber-900 ring-amber-200", mint: "bg-mint-50 text-mint-900 ring-mint-200", sky: "bg-sky-50 text-sky-900 ring-sky-200" }[tone];
  return (
    <div role={tone === "red" ? "alert" : "status"} className={cx("flex items-start justify-between gap-3 rounded-xl px-3 py-2.5 text-sm ring-1", styles)}>
      <div className="min-w-0">{children}</div>
      {onRetry && (
        <button type="button" onClick={onRetry} className="shrink-0 font-medium underline">
          Retry
        </button>
      )}
    </div>
  );
}

export function Empty({ children }: { children: ReactNode }) {
  return <p className="px-4 py-10 text-center text-sm text-slate-500">{children}</p>;
}

export function Skeleton({ className }: { className?: string }) {
  return <div className={cx("animate-pulse rounded-lg bg-slate-200/70", className)} />;
}

export function ListSkeleton({ rows = 5 }: { rows?: number }) {
  return (
    <div className="divide-y divide-slate-100" aria-busy>
      {Array.from({ length: rows }, (_, i) => (
        <div key={i} className="flex items-center gap-3 p-4">
          <Skeleton className="h-10 w-10 rounded-xl" />
          <div className="flex-1 space-y-2">
            <Skeleton className="h-4 w-1/2" />
            <Skeleton className="h-3 w-1/3" />
          </div>
        </div>
      ))}
    </div>
  );
}

export function Field({ label, hint, error, children }: { label: string; hint?: string; error?: string | null; children: (id: string) => ReactNode }) {
  const id = useId();
  return (
    <div className="space-y-1.5">
      <label htmlFor={id} className="block text-sm font-medium text-slate-700">
        {label}
      </label>
      {children(id)}
      {error ? <p className="text-xs text-red-600">{error}</p> : hint ? <p className="text-xs text-slate-500">{hint}</p> : null}
    </div>
  );
}

export function Input({ className, ...rest }: InputHTMLAttributes<HTMLInputElement>) {
  return (
    <input
      className={cx(
        "h-11 w-full rounded-xl border border-slate-300 bg-white px-3 text-base outline-none transition-colors placeholder:text-slate-400 focus:border-mint-500 focus:ring-2 focus:ring-mint-100 md:text-sm",
        className,
      )}
      {...rest}
    />
  );
}

/** Horizontally scrolling filter chips (one row on phones). */
export function Chips<T extends string>({ value, options, onChange }: { value: T; options: { value: T; label: string; count?: number }[]; onChange: (v: T) => void }) {
  return (
    <div className="-mx-4 flex gap-2 overflow-x-auto px-4 pb-1 [scrollbar-width:none] md:mx-0 md:flex-wrap md:px-0" role="tablist">
      {options.map((o) => (
        <button
          key={o.value}
          type="button"
          role="tab"
          aria-selected={o.value === value}
          onClick={() => onChange(o.value)}
          className={cx(
            "h-9 shrink-0 rounded-full px-3.5 text-sm font-medium ring-1 transition-colors",
            o.value === value ? "bg-slate-900 text-white ring-slate-900" : "bg-white text-slate-700 ring-slate-200 hover:bg-slate-50",
          )}
        >
          {o.label}
          {o.count !== undefined && <span className={cx("ml-1.5 tabular-nums", o.value === value ? "text-slate-300" : "text-slate-400")}>{o.count}</span>}
        </button>
      ))}
    </div>
  );
}

/** Bottom sheet on phones, centred dialog on bigger screens. Esc and the backdrop close it. */
export function Sheet({ open, title, onClose, children, footer }: { open: boolean; title: string; onClose: () => void; children: ReactNode; footer?: ReactNode }) {
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    document.addEventListener("keydown", onKey);
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    ref.current?.focus();
    return () => {
      document.removeEventListener("keydown", onKey);
      document.body.style.overflow = prev;
    };
  }, [open, onClose]);
  if (!open) return null;
  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-slate-900/40 md:items-center md:p-6" onClick={onClose}>
      <div
        ref={ref}
        tabIndex={-1}
        role="dialog"
        aria-modal
        aria-label={title}
        onClick={(e) => e.stopPropagation()}
        className="safe-bottom flex max-h-[90dvh] w-full flex-col rounded-t-3xl bg-white outline-none md:max-w-lg md:rounded-2xl"
      >
        <div className="mx-auto mt-2 h-1.5 w-10 rounded-full bg-slate-200 md:hidden" aria-hidden />
        <header className="flex items-center justify-between gap-3 px-5 pt-3 pb-2">
          <h2 className="text-base font-semibold">{title}</h2>
          <button type="button" onClick={onClose} aria-label="Close" className="grid h-9 w-9 place-items-center rounded-full text-xl text-slate-500 hover:bg-slate-100">
            ×
          </button>
        </header>
        <div className="flex-1 overflow-y-auto px-5 pb-4">{children}</div>
        {footer && <footer className="flex gap-2 border-t border-slate-100 px-5 py-3">{footer}</footer>}
      </div>
    </div>
  );
}

/** Label + value rows for detail screens. */
export function Rows({ rows }: { rows: [ReactNode, ReactNode][] }) {
  return (
    <dl className="divide-y divide-slate-100">
      {rows.map(([k, v], i) => (
        <div key={i} className="flex items-baseline justify-between gap-4 py-2.5 text-sm">
          <dt className="text-slate-500">{k}</dt>
          <dd className="min-w-0 text-right font-medium text-slate-900">{v}</dd>
        </div>
      ))}
    </dl>
  );
}

export function LoadMore({ shown, total, loading, onMore }: { shown: number; total: number; loading: boolean; onMore: () => void }) {
  if (shown >= total) return total > 0 ? <p className="py-4 text-center text-xs text-slate-400">All {total} shown</p> : null;
  return (
    <div className="p-3 text-center">
      <Button variant="secondary" loading={loading} onClick={onMore} className="w-full md:w-auto">
        Show more ({total - shown} left)
      </Button>
    </div>
  );
}
