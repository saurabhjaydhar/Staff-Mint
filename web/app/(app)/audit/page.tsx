"use client";

import { Fragment, useState } from "react";
import { ExportButton } from "@/components/AppShell";
import { useI18n } from "@/components/providers";
import { Alert, Badge, Button, Card, EmptyState, Field, Loading, PageHeader, Select, Table, Td, Th, cx, type Tone } from "@/components/ui";
import { useAsync } from "@/hooks/useAsync";
import { api, errorMessage } from "@/lib/api";
import { diffObjects, showValue } from "@/lib/diff";
import { formatDateTime } from "@/lib/format";
import type { AuditChannel, AuditLog } from "@/lib/types";

const PAGE = 50;
const ENTITIES = ["", "employee", "attendance", "leave", "advance", "adjustment", "payroll_run", "payslip", "company", "import", "holiday", "shift", "branch", "subscription"];
const CHANNEL_TONE: Record<AuditChannel, Tone> = { app: "mint", web: "sky", assistant: "violet", whatsapp: "mint", system: "slate", import: "amber" };

export default function AuditPage() {
  const { t } = useI18n();
  const [entity, setEntity] = useState("");
  const [extra, setExtra] = useState<{ key: string; logs: AuditLog[]; done: boolean }>({ key: "", logs: [], done: false });
  const [loadingMore, setLoadingMore] = useState(false);
  const [moreError, setMoreError] = useState<string | null>(null);
  const [open, setOpen] = useState<Record<string, boolean>>({});
  const first = useAsync(() => api.get<AuditLog[]>("/audit-logs", { entity: entity || undefined, limit: PAGE }), `audit:${entity}`);

  const key = `audit:${entity}`;
  const more = extra.key === key ? extra : { key, logs: [], done: false };
  const logs = [...(first.data ?? []), ...more.logs];
  const done = more.done || (first.data !== undefined && first.data.length < PAGE);

  async function loadMore() {
    const last = logs[logs.length - 1];
    if (!last) return;
    setLoadingMore(true);
    setMoreError(null);
    try {
      // `before` is treated as a cursor: the timestamp of the oldest loaded entry.
      const page = await api.get<AuditLog[]>("/audit-logs", { entity: entity || undefined, limit: PAGE, before: last.at });
      const seen = new Set(logs.map((l) => l.id));
      setExtra({ key, logs: [...more.logs, ...page.filter((l) => !seen.has(l.id))], done: page.length < PAGE });
    } catch (e) {
      setMoreError(errorMessage(e));
    } finally {
      setLoadingMore(false);
    }
  }

  return (
    <div className="space-y-5">
      <PageHeader title={t("nav_audit")} subtitle="Every change — who did it, from where, and what changed." actions={<ExportButton />} />
      <Card padded={false}>
        <div className="flex flex-wrap items-end gap-3 border-b border-slate-100 p-4">
          <Field label="Entity" className="w-52">
            {(id) => (
              <Select id={id} value={entity} onChange={(e) => setEntity(e.target.value)}>
                {ENTITIES.map((e) => (
                  <option key={e} value={e}>
                    {e ? e.replace(/_/g, " ") : "All"}
                  </option>
                ))}
              </Select>
            )}
          </Field>
        </div>
        {first.errorText && <Alert className="m-4" onRetry={first.reload}>{first.errorText}</Alert>}
        {!first.data && first.loading ? (
          <Loading />
        ) : logs.length === 0 ? (
          <EmptyState>{t("none")}</EmptyState>
        ) : (
          <Table>
            <thead>
              <tr>
                <Th className="w-8" />
                <Th>When</Th>
                <Th>Who</Th>
                <Th>Channel</Th>
                <Th>Action</Th>
                <Th>Entity</Th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {logs.map((l) => {
                const isOpen = !!open[l.id];
                return (
                  <Fragment key={l.id}>
                    <tr className={cx("cursor-pointer hover:bg-slate-50", isOpen && "bg-slate-50")} onClick={() => setOpen((o) => ({ ...o, [l.id]: !o[l.id] }))}>
                      <Td className="text-slate-400">{isOpen ? "▾" : "▸"}</Td>
                      <Td className="whitespace-nowrap text-xs">{formatDateTime(l.at)}</Td>
                      <Td>{l.actorName || "System"}</Td>
                      <Td>
                        <Badge tone={CHANNEL_TONE[l.channel] ?? "slate"}>{l.channel}</Badge>
                      </Td>
                      <Td className="font-medium">{l.action}</Td>
                      <Td className="text-xs text-slate-600">
                        {l.entity} <span className="text-slate-400">#{l.entityId?.slice(-6)}</span>
                      </Td>
                    </tr>
                    {isOpen && (
                      <tr>
                        <td colSpan={6} className="bg-slate-50 px-6 pb-4">
                          <AuditDiff log={l} />
                        </td>
                      </tr>
                    )}
                  </Fragment>
                );
              })}
            </tbody>
          </Table>
        )}
        {moreError && <Alert className="m-4">{moreError}</Alert>}
        {logs.length > 0 && !done && (
          <div className="flex justify-center border-t border-slate-100 p-3">
            <Button variant="secondary" size="sm" onClick={loadMore} loading={loadingMore}>
              Load older entries
            </Button>
          </div>
        )}
      </Card>
    </div>
  );
}

function AuditDiff({ log }: { log: AuditLog }) {
  const [raw, setRaw] = useState(false);
  const entries = diffObjects(log.before, log.after);
  return (
    <div className="space-y-2 pt-2">
      <div className="flex justify-end">
        <button type="button" className="text-xs text-mint-700 underline" onClick={() => setRaw((r) => !r)}>
          {raw ? "Show changes" : "Show raw JSON"}
        </button>
      </div>
      {raw ? (
        <div className="grid gap-3 md:grid-cols-2">
          <div>
            <div className="mb-1 text-xs font-semibold uppercase text-slate-500">Before</div>
            <pre className="max-h-80 overflow-auto rounded-lg bg-white p-3 text-xs ring-1 ring-slate-200">{JSON.stringify(log.before, null, 2) ?? "null"}</pre>
          </div>
          <div>
            <div className="mb-1 text-xs font-semibold uppercase text-slate-500">After</div>
            <pre className="max-h-80 overflow-auto rounded-lg bg-white p-3 text-xs ring-1 ring-slate-200">{JSON.stringify(log.after, null, 2) ?? "null"}</pre>
          </div>
        </div>
      ) : entries.length === 0 ? (
        <p className="text-sm text-slate-500">No field changes recorded.</p>
      ) : (
        <table className="w-full overflow-hidden rounded-lg bg-white text-xs ring-1 ring-slate-200">
          <thead>
            <tr className="bg-slate-100 text-left text-slate-600">
              <th className="px-3 py-1.5 font-semibold">Field</th>
              <th className="px-3 py-1.5 font-semibold">Before</th>
              <th className="px-3 py-1.5 font-semibold">After</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-100 font-mono">
            {entries.map((e) => (
              <tr key={e.path}>
                <td className="px-3 py-1.5 text-slate-700">{e.path}</td>
                <td className={cx("px-3 py-1.5 break-all", e.kind !== "added" && "bg-red-50 text-red-800")}>
                  {e.kind === "added" ? <span className="text-slate-400">—</span> : showValue(e.before)}
                </td>
                <td className={cx("px-3 py-1.5 break-all", e.kind !== "removed" && "bg-mint-50 text-mint-900")}>
                  {e.kind === "removed" ? <span className="text-slate-400">—</span> : showValue(e.after)}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}
