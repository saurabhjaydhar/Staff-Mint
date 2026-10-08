"use client";

import { useEffect, useMemo, useState, type FormEvent } from "react";
import { useI18n, useToast } from "@/components/providers";
import { Alert, Badge, Button, Card, Checkbox, Field, Input, PageHeader, Segmented, Select, Stat, Table, Td, Textarea, Th, cx } from "@/components/ui";
import { useAction } from "@/hooks/useAsync";
import { api } from "@/lib/api";
import { saveText } from "@/lib/download";
import { formatDateTime, previousMonth } from "@/lib/format";
import {
  buildFixes,
  cellInputValue,
  displayColumns,
  draftKey,
  duplicateMappings,
  fieldLabel,
  flaggedRows,
  initialSkips,
  isPaiseField,
  issuesFor,
  mappingOptions,
  mappingPatch,
  moneyInputError,
  otherIssues,
  sampleTemplateCsv,
  secondsLeft,
  toggleSkip,
  undoDeadline,
  unresolvedCount,
  type FixDrafts,
} from "@/lib/importHelpers";
import type { ImportCommitResult, ImportKind, ImportPatch, ImportSession, ImportSource } from "@/lib/types";

const SOURCES: { value: ImportSource; label: string }[] = [
  { value: "auto", label: "Detect automatically" },
  { value: "salarybox", label: "SalaryBox export" },
  { value: "pagarbook", label: "PagarBook export" },
  { value: "generic", label: "My own Excel / other" },
];

export default function ImportPage() {
  const { t } = useI18n();
  const [session, setSession] = useState<ImportSession | null>(null);
  const [skips, setSkips] = useState<number[]>([]);
  const [result, setResult] = useState<{ commit: ImportCommitResult; committedAt: number } | null>(null);

  function startReview(s: ImportSession) {
    setSession(s);
    setSkips(initialSkips(s));
    setResult(null);
  }
  function reset() {
    setSession(null);
    setSkips([]);
    setResult(null);
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title={t("import_title")}
        subtitle="Upload your staff list or last month's attendance from Excel, SalaryBox or PagarBook. We map the columns and only show rows that need a look."
        actions={session && <Button variant="secondary" size="sm" onClick={reset}>↺ Start over</Button>}
      />
      <Steps current={result ? 3 : session ? 2 : 1} />
      {!session && <UploadForm onUploaded={startReview} />}
      {session && !result && (
        <Review
          session={session}
          skips={skips}
          onSession={setSession}
          onSkips={setSkips}
          onCommitted={(commit, committedAt) => setResult({ commit, committedAt })}
        />
      )}
      {session && result && <Done session={session} result={result.commit} committedAt={result.committedAt} onAnother={reset} />}
    </div>
  );
}

function Steps({ current }: { current: number }) {
  const steps = ["Upload", "Review flagged rows", "Done"];
  return (
    <ol className="flex flex-wrap items-center gap-2 text-sm">
      {steps.map((s, i) => (
        <li key={s} className="flex items-center gap-2">
          <span
            className={cx(
              "grid h-6 w-6 place-items-center rounded-full text-xs font-semibold",
              i + 1 < current ? "bg-mint-500 text-white" : i + 1 === current ? "bg-mint-100 text-mint-800 ring-2 ring-mint-500" : "bg-slate-200 text-slate-500",
            )}
          >
            {i + 1 < current ? "✓" : i + 1}
          </span>
          <span className={i + 1 === current ? "font-medium text-slate-900" : "text-slate-500"}>{s}</span>
          {i < steps.length - 1 && <span className="mx-1 text-slate-300">—</span>}
        </li>
      ))}
    </ol>
  );
}

// ---------------- Step 1: upload ----------------
function UploadForm({ onUploaded }: { onUploaded: (s: ImportSession) => void }) {
  const { t } = useI18n();
  const [mode, setMode] = useState<"file" | "paste">("file");
  const [kind, setKind] = useState<ImportKind>("staff");
  const [month, setMonth] = useState(() => previousMonth());
  const [source, setSource] = useState<ImportSource>("auto");
  const [file, setFile] = useState<File | null>(null);
  const [text, setText] = useState("");
  const action = useAction();

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (mode === "file" && !file) return action.setError("Choose an Excel or CSV file first.");
    if (mode === "paste" && !text.trim()) return action.setError("Paste your staff list first.");
    const res = await action.run("upload", () => {
      if (mode === "file" && file) {
        const fd = new FormData();
        fd.append("file", file);
        fd.append("kind", kind);
        fd.append("source", source);
        if (kind === "attendance") fd.append("month", month);
        return api.post<ImportSession>("/imports", fd);
      }
      return api.post<ImportSession>("/imports", {
        text,
        kind,
        source,
        ...(kind === "attendance" ? { month } : {}),
      });
    });
    if (res.ok) onUploaded(res.value);
  }

  return (
    <Card>
      <form onSubmit={submit} className="space-y-5">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <Segmented
            value={mode}
            onChange={setMode}
            options={[
              { value: "file", label: t("import_upload") },
              { value: "paste", label: t("import_paste") },
            ]}
          />
          <Button variant="ghost" size="sm" onClick={() => saveText(sampleTemplateCsv(kind, month), `staffmint-${kind}-template.csv`)}>
            ⇩ {t("import_sample")}
          </Button>
        </div>

        <div className="grid gap-4 md:grid-cols-3">
          <Field label={t("import_kind")}>
            {(id) => (
              <Select id={id} value={kind} onChange={(e) => setKind(e.target.value as ImportKind)}>
                <option value="staff">{t("import_kind_staff")}</option>
                <option value="attendance">{t("import_kind_attendance")}</option>
              </Select>
            )}
          </Field>
          {kind === "attendance" && (
            <Field label={t("month")} hint="Which month is this attendance grid for?">
              {(id) => <Input id={id} type="month" value={month} onChange={(e) => setMonth(e.target.value)} required />}
            </Field>
          )}
          <Field label={t("import_source")}>
            {(id) => (
              <Select id={id} value={source} onChange={(e) => setSource(e.target.value as ImportSource)}>
                {SOURCES.map((s) => (
                  <option key={s.value} value={s.value}>
                    {s.label}
                  </option>
                ))}
              </Select>
            )}
          </Field>
        </div>

        {mode === "file" ? (
          <label
            className={cx(
              "flex cursor-pointer flex-col items-center justify-center gap-2 rounded-xl border-2 border-dashed px-4 py-10 text-center transition-colors",
              file ? "border-mint-400 bg-mint-50" : "border-slate-300 hover:border-mint-400 hover:bg-mint-50/50",
            )}
            onDragOver={(e) => e.preventDefault()}
            onDrop={(e) => {
              e.preventDefault();
              const f = e.dataTransfer.files?.[0];
              if (f) setFile(f);
            }}
          >
            <span className="text-3xl" aria-hidden>
              ⇪
            </span>
            {file ? (
              <span className="text-sm">
                <span className="font-medium">{file.name}</span> · {(file.size / 1024).toFixed(1)} KB
              </span>
            ) : (
              <span className="text-sm text-slate-600">Drop an .xlsx / .xls / .csv file here, or click to choose</span>
            )}
            <input
              type="file"
              className="sr-only"
              accept=".xlsx,.xls,.csv,text/csv,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet,application/vnd.ms-excel"
              onChange={(e) => setFile(e.target.files?.[0] ?? null)}
            />
          </label>
        ) : (
          <Field label="Paste rows (one person per line)" hint="e.g. “Ramesh 9876543210 15000” — any order, commas or tabs are fine.">
            {(id) => (
              <Textarea
                id={id}
                rows={8}
                value={text}
                onChange={(e) => setText(e.target.value)}
                placeholder={"Ramesh Kumar, 9876543210, 15000\nSunita Devi, 9876501234, 600/day"}
                className="font-mono"
              />
            )}
          </Field>
        )}

        {action.error && <Alert>{action.error}</Alert>}
        <div className="flex justify-end">
          <Button type="submit" loading={action.busy === "upload"}>
            {t("import_start")} →
          </Button>
        </div>
      </form>
    </Card>
  );
}

// ---------------- Step 2: review ----------------
function Review({
  session,
  skips,
  onSession,
  onSkips,
  onCommitted,
}: {
  session: ImportSession;
  skips: number[];
  onSession: (s: ImportSession) => void;
  onSkips: (s: number[]) => void;
  onCommitted: (r: ImportCommitResult, committedAt: number) => void;
}) {
  const { t, lang } = useI18n();
  const toast = useToast();
  const [drafts, setDrafts] = useState<FixDrafts>({});
  const [overwrite, setOverwrite] = useState(false);
  const action = useAction();

  const flagged = useMemo(() => flaggedRows(session), [session]);
  const columns = useMemo(() => displayColumns(session), [session]);
  const options = useMemo(() => mappingOptions(session), [session]);
  const dupes = useMemo(() => duplicateMappings(session.mapping), [session.mapping]);
  const pendingFixes = useMemo(() => buildFixes(session, drafts), [session, drafts]);
  const unresolved = unresolvedCount(session, skips);

  async function patch(key: string, body: ImportPatch) {
    const res = await action.run(key, () => api.patch<ImportSession>(`/imports/${session.id}`, body));
    if (res.ok) onSession(res.value);
    return res.ok;
  }

  async function changeMapping(header: string, field: string) {
    await patch(`map:${header}`, mappingPatch(header, field || null));
  }

  async function applyFixes() {
    if (pendingFixes.length === 0) return;
    const ok = await patch("fixes", { fixes: pendingFixes, skipRows: skips });
    if (ok) {
      setDrafts({});
      toast(`${pendingFixes.length} fix${pendingFixes.length === 1 ? "" : "es"} applied`);
    }
  }

  async function skipRow(index: number) {
    const next = toggleSkip(skips, index);
    const ok = await patch(`skip:${index}`, { skipRows: next });
    if (ok) onSkips(next);
  }

  async function commit() {
    const committedAt = Date.now();
    const res = await action.run("commit", () =>
      api.post<ImportCommitResult>(`/imports/${session.id}/commit`, { overwriteExisting: overwrite }),
    );
    if (res.ok) onCommitted(res.value, committedAt);
  }

  return (
    <div className="space-y-6">
      <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
        <Stat label={t("import_total_rows")} value={session.totalRows} />
        <Stat label={t("import_flagged_rows")} value={session.flaggedCount} tone={session.flaggedCount ? "amber" : "mint"} />
        <Stat label="Skipped" value={skips.length} />
        <Stat
          label="Detected"
          value={<span className="text-base capitalize">{session.kind}</span>}
          hint={`Source: ${session.source}`}
        />
      </div>

      {action.error && <Alert>{action.error}</Alert>}

      <Card title={t("import_mapping")} padded={false}>
        <p className="px-4 pt-3 text-sm text-slate-500">
          Changing a column applies to all rows. Choose “Ignore” for columns you don&apos;t need.
        </p>
        {dupes.length > 0 && (
          <Alert tone="amber" className="mx-4 mt-3">
            More than one column is mapped to: {dupes.map((d) => fieldLabel(d, lang)).join(", ")}
          </Alert>
        )}
        <Table className="mt-2">
          <thead>
            <tr>
              <Th>Column in your file</Th>
              <Th>StaffMint field</Th>
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-100">
            {session.headers.map((h) => {
              const value = session.mapping[h] ?? "";
              return (
                <tr key={h}>
                  <Td className="font-medium">{h || <span className="text-slate-400">(blank header)</span>}</Td>
                  <Td>
                    <div className="flex items-center gap-2">
                      <Select
                        aria-label={`Field for ${h}`}
                        value={value}
                        disabled={!!action.busy}
                        onChange={(e) => void changeMapping(h, e.target.value)}
                        warn={!!value && dupes.includes(value)}
                        className={cx("max-w-xs", !value && "text-slate-400")}
                      >
                        <option value="">— Ignore —</option>
                        {options.map((f) => (
                          <option key={f} value={f}>
                            {fieldLabel(f, lang)}
                          </option>
                        ))}
                      </Select>
                      {action.busy === `map:${h}` && <span className="text-xs text-slate-500">Updating…</span>}
                    </div>
                  </Td>
                </tr>
              );
            })}
          </tbody>
        </Table>
      </Card>

      <Card
        title={
          <span className="flex items-center gap-2">
            {t("import_flagged")} <Badge tone={flagged.length ? "amber" : "mint"}>{flagged.length}</Badge>
          </span>
        }
        actions={
          flagged.length > 0 && (
            <Button size="sm" onClick={applyFixes} disabled={pendingFixes.length === 0} loading={action.busy === "fixes"}>
              {t("import_apply_fixes")}
              {pendingFixes.length > 0 && ` (${pendingFixes.length})`}
            </Button>
          )
        }
        padded={false}
      >
        {flagged.length === 0 ? (
          <div className="p-6 text-center text-sm text-mint-800">✓ {t("import_no_flags")}</div>
        ) : (
          <Table>
            <thead>
              <tr>
                <Th>Row</Th>
                {columns.map((c) => (
                  <Th key={c}>{fieldLabel(c, lang)}</Th>
                ))}
                <Th className="text-right">{t("actions")}</Th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {flagged.map((row) => {
                const skipped = skips.includes(row.index);
                const extra = otherIssues(row, columns);
                return (
                  <tr key={row.index} className={cx(skipped && "bg-slate-50 opacity-60")}>
                    <Td className="align-top text-xs text-slate-500">#{row.index + 1}</Td>
                    {columns.map((field) => {
                      const key = draftKey(row.index, field);
                      const issues = issuesFor(row, field);
                      const value = drafts[key] ?? cellInputValue(field, row.values[field]);
                      const localError = drafts[key] !== undefined ? moneyInputError(field, drafts[key]) : null;
                      return (
                        <Td key={field} className="min-w-36 align-top">
                          <Input
                            aria-label={`${fieldLabel(field)} for row ${row.index + 1}`}
                            value={value}
                            disabled={skipped}
                            invalid={!!localError || (issues.length > 0 && drafts[key] === undefined)}
                            inputMode={isPaiseField(field) ? "decimal" : undefined}
                            placeholder={isPaiseField(field) ? "₹" : undefined}
                            onChange={(e) => setDrafts((d) => ({ ...d, [key]: e.target.value }))}
                            onKeyDown={(e) => e.key === "Enter" && void applyFixes()}
                            className="h-8 py-1"
                          />
                          {localError && <div className="mt-1 text-xs text-amber-700">{localError}</div>}
                          {issues.map((m) => (
                            <div key={m} className="mt-1 text-xs text-red-600">
                              {m}
                            </div>
                          ))}
                        </Td>
                      );
                    })}
                    <Td className="align-top text-right">
                      <Button size="sm" variant="ghost" loading={action.busy === `skip:${row.index}`} onClick={() => void skipRow(row.index)}>
                        {skipped ? t("import_unskip") : t("import_skip")}
                      </Button>
                      {extra.map((m) => (
                        <div key={m} className="mt-1 text-left text-xs text-red-600">
                          {m}
                        </div>
                      ))}
                    </Td>
                  </tr>
                );
              })}
            </tbody>
          </Table>
        )}
      </Card>

      <Card>
        <div className="flex flex-wrap items-center justify-between gap-4">
          <div className="space-y-2">
            <Checkbox label={t("import_overwrite")} checked={overwrite} onChange={(e) => setOverwrite(e.target.checked)} />
            <p className="text-xs text-slate-500">
              Staff are matched by phone number. Without this, existing staff are left unchanged.
            </p>
            {unresolved > 0 && (
              <p className="text-xs text-amber-700">
                {unresolved} flagged row{unresolved === 1 ? "" : "s"} still {unresolved === 1 ? "has" : "have"} issues — fix or skip{" "}
                {unresolved === 1 ? "it" : "them"} for a clean import.
              </p>
            )}
            {pendingFixes.length > 0 && <p className="text-xs text-amber-700">Apply your edits before importing.</p>}
          </div>
          <Button onClick={commit} loading={action.busy === "commit"} disabled={pendingFixes.length > 0 || !!action.busy}>
            ✓ {t("import_commit")} ({session.totalRows - skips.length} rows)
          </Button>
        </div>
      </Card>
    </div>
  );
}

// ---------------- Step 3: done ----------------
function Done({
  session,
  result,
  committedAt,
  onAnother,
}: {
  session: ImportSession;
  result: ImportCommitResult;
  committedAt: number;
  onAnother: () => void;
}) {
  const { t } = useI18n();
  const toast = useToast();
  const action = useAction();
  const [now, setNow] = useState(committedAt);
  const [removed, setRemoved] = useState<number | null>(null);

  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), 500);
    return () => clearInterval(id);
  }, []);

  const undoLeft = Math.max(0, Math.ceil((undoDeadline(result.undoUntil, committedAt) - now) / 1000));
  const rollbackLeft = secondsLeft(result.rollbackUntil, now);
  const rolledBack = removed !== null;

  async function rollback(kind: "undo" | "rollback") {
    const res = await action.run(kind, () => api.post<{ removed: number }>(`/imports/${session.id}/rollback`));
    if (res.ok) {
      setRemoved(res.value?.removed ?? 0);
      toast(kind === "undo" ? "Import undone" : "Import rolled back");
    }
  }

  return (
    <Card>
      <div className="space-y-5">
        <div className="flex items-center gap-3">
          <span className={cx("grid h-10 w-10 place-items-center rounded-full text-xl text-white", rolledBack ? "bg-slate-400" : "bg-mint-500")}>
            {rolledBack ? "↺" : "✓"}
          </span>
          <div>
            <h2 className="text-lg font-semibold">{rolledBack ? "Import rolled back" : t("import_done")}</h2>
            {rolledBack && <p className="text-sm text-slate-600">{removed} record(s) removed. Nothing else was changed.</p>}
          </div>
        </div>
        <div className="grid grid-cols-3 gap-3">
          <Stat label="Created" value={result.created} tone="mint" />
          <Stat label="Updated" value={result.updated} tone="sky" />
          <Stat label="Skipped" value={result.skipped} />
        </div>
        {action.error && <Alert>{action.error}</Alert>}
        <div className="flex flex-wrap items-center gap-3">
          {!rolledBack && undoLeft > 0 && (
            <Button variant="danger" onClick={() => rollback("undo")} loading={action.busy === "undo"}>
              ↶ {t("import_undo")} ({undoLeft}s)
            </Button>
          )}
          {!rolledBack && undoLeft === 0 && rollbackLeft > 0 && (
            <Button variant="secondary" onClick={() => rollback("rollback")} loading={action.busy === "rollback"}>
              ↺ {t("import_rollback")}
            </Button>
          )}
          <Button variant={rolledBack || undoLeft === 0 ? "primary" : "secondary"} onClick={onAnother}>
            {t("import_another")}
          </Button>
        </div>
        {!rolledBack && rollbackLeft > 0 && (
          <p className="text-xs text-slate-500">
            You can roll back this whole import until {formatDateTime(result.rollbackUntil)}.
          </p>
        )}
      </div>
    </Card>
  );
}
