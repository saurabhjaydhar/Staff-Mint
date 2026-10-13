"use client";

import { useState, type FormEvent } from "react";
import { useI18n, useToast } from "@/components/providers";
import { Alert, Badge, Button, Checkbox, Field, Input, Loading, Modal, Select } from "@/components/ui";
import { useAction, useAsync } from "@/hooks/useAsync";
import { api } from "@/lib/api";
import { fill, type DictKey } from "@/lib/i18n";
import { formatDate } from "@/lib/format";
import type { DocumentKind, Employee, OpenedDoc, OwnerVerification, StaffDoc, StaffDocs, VerifyCheck, VerifyKind } from "@/lib/types";

const DOC_KINDS: DocumentKind[] = ["aadhaar", "pan", "dl", "voter", "passport", "bank_proof", "address", "police", "experience", "other"];
const EXPIRING = new Set<DocumentKind>(["dl", "passport", "police"]);
const VERIFY_KINDS: VerifyKind[] = ["aadhaar", "pan", "bank"];
const MIMES = ["image/jpeg", "image/png", "application/pdf"];

/** Owner: one person's documents check (results) and their documents (upload, open, remove). */
export function DocumentsModal({ employee, onClose, onChanged }: { employee: Employee | null; onClose: () => void; onChanged: () => void }) {
  const { t } = useI18n();
  return (
    <Modal open={!!employee} onClose={onClose} title={employee ? fill(t("docs_title"), { name: employee.name }) : ""} wide>
      {employee && (
        <div className="space-y-5">
          <CheckPanel employee={employee} onChanged={onChanged} />
          <DocsPanel employee={employee} />
        </div>
      )}
    </Modal>
  );
}

// ---------------------------------------------------------------- documents check

function CheckPanel({ employee, onChanged }: { employee: Employee; onChanged: () => void }) {
  const { t } = useI18n();
  const toast = useToast();
  const action = useAction();
  const data = useAsync(() => api.get<OwnerVerification>(`/verification/employees/${employee.id}`), `verify:${employee.id}`);
  const [kinds, setKinds] = useState<VerifyKind[]>(VERIFY_KINDS);
  const [accepting, setAccepting] = useState<VerifyCheck | null>(null);
  const [reason, setReason] = useState("");
  const v = data.data;

  async function run(key: string, fn: () => Promise<OwnerVerification>, done?: string) {
    const res = await action.run(key, fn);
    if (!res.ok) return;
    data.setData(res.value);
    onChanged();
    if (done) toast(done);
  }

  if (!v) return data.errorText ? <Alert onRetry={data.reload}>{data.errorText}</Alert> : <Loading />;
  const left = Math.max(0, v.quota.limit - v.quota.used);
  const r = v.request;

  return (
    <section data-testid="vcheck">
      <div className="flex items-center gap-2">
        <h3 className="font-semibold text-slate-900">{t("vcheck_title")}</h3>
        {v.badge === "verified" && <Badge tone="mint">{t("doc_verified")}</Badge>}
        {v.badge === "needs_attention" && <Badge tone="amber">{t("doc_needs_look")}</Badge>}
      </div>
      {action.error && <Alert>{action.error}</Alert>}
      {!r || r.status === "cancelled" ? (
        <div className="mt-2 space-y-2">
          <p className="text-sm text-slate-600">{t("vcheck_none")}</p>
          <div className="flex flex-wrap gap-4">
            {VERIFY_KINDS.map((k) => (
              <Checkbox
                key={k}
                label={t(`vk_${k}` as DictKey)}
                checked={kinds.includes(k)}
                onChange={(e) => setKinds((ks) => (e.target.checked ? [...ks, k] : ks.filter((x) => x !== k)))}
              />
            ))}
          </div>
          <p className="text-sm text-slate-600">
            {v.quota.limit === 0
              ? t("vcheck_no_plan")
              : left > 0
                ? fill(t("vcheck_left"), { left, limit: v.quota.limit })
                : fill(t("vcheck_used"), {
                    limit: v.quota.limit,
                    price: Math.round(v.quota.extraPricePaise / 100),
                  })}
          </p>
          <Button
            disabled={!kinds.length || left === 0}
            loading={action.busy === "ask"}
            onClick={() => run("ask", () => api.post<OwnerVerification>(`/verification/employees/${employee.id}`, { kinds }), t("vcheck_sent"))}
          >
            {fill(t("vcheck_send"), { name: employee.name })}
          </Button>
        </div>
      ) : (
        <div className="mt-2 space-y-2">
          {r.status === "asked" && <p className="text-sm text-slate-600">{fill(t("vcheck_asked"), { name: employee.name })}</p>}
          {r.status === "in_progress" && <p className="text-sm text-slate-600">{fill(t("vcheck_in_progress"), { name: employee.name })}</p>}
          <ul className="divide-y divide-slate-100 rounded-lg ring-1 ring-slate-200">
            {v.checks.map((c) => (
              <li key={c.id} className="flex flex-wrap items-center gap-2 px-3 py-2" data-check={c.kind}>
                <div className="min-w-0 flex-1">
                  <div className="font-medium text-slate-900">{t(`vk_${c.kind}` as DictKey)}</div>
                  <div className="text-sm text-slate-600">{checkLine(c, t)}</div>
                </div>
                {c.status === "mismatch" && !c.override && (
                  <Button size="sm" variant="secondary" onClick={() => (setAccepting(c), setReason(t("vcheck_accept_default")))}>
                    {t("vcheck_accept")}
                  </Button>
                )}
                {(c.status === "mismatch" || c.status === "not_found") && !c.override && (
                  <Button
                    size="sm"
                    variant="ghost"
                    loading={action.busy === `again:${c.id}`}
                    onClick={() => run(`again:${c.id}`, () => api.post<OwnerVerification>(`/verification/checks/${c.id}/ask-again`), t("vcheck_asked_again"))}
                  >
                    {t("vcheck_ask_again")}
                  </Button>
                )}
              </li>
            ))}
          </ul>
          {accepting && (
            <form
              className="flex flex-wrap items-end gap-2 rounded-lg bg-slate-50 p-3"
              onSubmit={(e) => {
                e.preventDefault();
                const c = accepting;
                setAccepting(null);
                void run(`accept:${c.id}`, () => api.post<OwnerVerification>(`/verification/checks/${c.id}/accept`, { reason: reason.trim() }));
              }}
            >
              <Field label={t("vcheck_accept_reason")} className="min-w-64 flex-1">
                {(id) => <Input id={id} value={reason} maxLength={200} onChange={(e) => setReason(e.target.value)} />}
              </Field>
              <Button type="submit" disabled={!reason.trim()}>
                {t("vcheck_accept")}
              </Button>
            </form>
          )}
          {(r.status === "asked" || r.status === "in_progress") && (
            <Button
              size="sm"
              variant="ghost"
              loading={action.busy === "cancel"}
              onClick={() => run("cancel", () => api.delete<OwnerVerification>(`/verification/employees/${employee.id}`))}
            >
              {t("vcheck_cancel")}
            </Button>
          )}
        </div>
      )}
    </section>
  );
}

function checkLine(c: VerifyCheck, t: (k: DictKey) => string) {
  const parts: string[] = [];
  if (c.status === "mismatch" && c.override) parts.push(fill(t("vs_accepted"), { reason: c.override.reason }));
  else parts.push(t(`vs_${c.status}` as DictKey));
  if (c.nameOnRecord && c.status !== "verified") parts.push(fill(t("v_on_record"), { name: c.nameOnRecord }));
  if (c.last4) parts.push(fill(t("v_ending"), { last4: c.last4 }));
  if (c.details?.dob) parts.push(fill(t("v_born"), { date: formatDate(c.details.dob) }));
  return parts.join(" · ");
}

// ---------------------------------------------------------------- documents

function DocsPanel({ employee }: { employee: Employee }) {
  const { t } = useI18n();
  const toast = useToast();
  const action = useAction();
  const data = useAsync(() => api.get<StaffDocs>(`/verification/employees/${employee.id}/documents`), `docs:${employee.id}`);
  const [adding, setAdding] = useState(false);
  const [opened, setOpened] = useState<{ id: string; doc: OpenedDoc } | null>(null);

  async function open(d: StaffDoc) {
    const res = await action.run(`open:${d.id}`, () => api.post<OpenedDoc>(`/verification/documents/${d.id}/open`));
    if (res.ok) setOpened({ id: d.id, doc: res.value });
  }

  async function remove(d: StaffDoc) {
    if (!window.confirm(fill(t("docs_remove_q"), { name: docName(d, t) }))) return;
    const res = await action.run(`remove:${d.id}`, () => api.delete(`/verification/documents/${d.id}`));
    if (res.ok) {
      toast(t("docs_removed"));
      if (opened?.id === d.id) setOpened(null);
      data.reload();
    }
  }

  const docs = data.data;
  return (
    <section data-testid="docs">
      <div className="flex items-center justify-between gap-2">
        <h3 className="font-semibold text-slate-900">{t("docs_list")}</h3>
        {!adding && (
          <Button size="sm" variant="secondary" onClick={() => setAdding(true)}>
            + {t("docs_add")}
          </Button>
        )}
      </div>
      {data.errorText && <Alert onRetry={data.reload}>{data.errorText}</Alert>}
      {action.error && <Alert>{action.error}</Alert>}
      {!docs ? (
        data.loading && <Loading />
      ) : (
        <>
          {adding && (
            <AddDocForm
              employee={employee}
              agreementOnFile={docs.agreementOnFile}
              onCancel={() => setAdding(false)}
              onSaved={() => {
                setAdding(false);
                toast(t("docs_saved"));
                data.reload();
              }}
            />
          )}
          {docs.documents.length === 0 && !adding && <p className="mt-2 text-sm text-slate-500">{t("docs_none")}</p>}
          <ul className="mt-2 divide-y divide-slate-100 rounded-lg ring-1 ring-slate-200 empty:hidden">
            {docs.documents.map((d) => (
              <li key={d.id} className="px-3 py-2" data-doc={d.kind}>
                <div className="flex flex-wrap items-center gap-2">
                  <div className="min-w-0 flex-1">
                    <div className="font-medium text-slate-900">{docName(d, t)}</div>
                    <div className="text-sm text-slate-600">
                      {[
                        d.numberLast4 && fill(t("v_ending"), { last4: d.numberLast4 }),
                        fill(t("docs_pages"), { n: d.files.length }),
                        t(d.addedBy === "owner" ? "docs_by_you" : "docs_by_staff"),
                      ]
                        .filter(Boolean)
                        .join(" · ")}
                      {d.expiresOn && (
                        <span className={d.expiry === "expired" ? "ml-2 font-semibold text-red-600" : d.expiry === "soon" ? "ml-2 font-semibold text-amber-700" : "ml-2"}>
                          {fill(t(d.expiry === "expired" ? "docs_expired" : d.expiry === "soon" ? "docs_expires" : "docs_valid"), { date: formatDate(d.expiresOn) })}
                        </span>
                      )}
                    </div>
                  </div>
                  <Button size="sm" variant="ghost" loading={action.busy === `open:${d.id}`} onClick={() => open(d)}>
                    {t("docs_open")}
                  </Button>
                  <Button size="sm" variant="ghost" className="text-red-600" loading={action.busy === `remove:${d.id}`} onClick={() => remove(d)}>
                    {t("docs_remove")}
                  </Button>
                </div>
                {opened?.id === d.id && <Preview doc={opened.doc} />}
              </li>
            ))}
          </ul>
          <p className="mt-2 text-xs text-slate-500">🔒 {t("docs_locked")}</p>
        </>
      )}
    </section>
  );
}

function Preview({ doc }: { doc: OpenedDoc }) {
  const { t } = useI18n();
  const items = [...doc.files.map((f, i) => ({ ...f, label: fill(t("docs_page"), { n: i + 1 }) })), ...(doc.slip ? [{ ...doc.slip, label: t("docs_slip_link") }] : [])];
  return (
    <div className="mt-2 flex flex-wrap gap-3" data-testid="doc-preview">
      {items.map((f) =>
        f.mime.startsWith("image/") ? (
          <a key={f.url} href={f.url} target="_blank" rel="noreferrer" className="block">
            {/* eslint-disable-next-line @next/next/no-img-element -- short-lived signed link, not optimisable */}
            <img src={f.url} alt={f.label} className="h-40 rounded-md object-contain ring-1 ring-slate-200" />
            <span className="text-xs text-slate-500">{f.label}</span>
          </a>
        ) : (
          <a key={f.url} href={f.url} target="_blank" rel="noreferrer" className="rounded-md px-3 py-2 text-sm font-medium text-mint-700 ring-1 ring-slate-200">
            PDF · {f.label}
          </a>
        ),
      )}
    </div>
  );
}

function docName(d: StaffDoc, t: (k: DictKey) => string) {
  return d.kind === "other" && d.label ? d.label : t(`dk_${d.kind}` as DictKey);
}

const readFile = (f: File) =>
  new Promise<{ data: string; mime: string }>((resolve, reject) => {
    const r = new FileReader();
    r.onload = () => resolve({ data: String(r.result), mime: f.type });
    r.onerror = () => reject(r.error);
    r.readAsDataURL(f);
  });

function AddDocForm({ employee, agreementOnFile, onCancel, onSaved }: { employee: Employee; agreementOnFile: boolean; onCancel: () => void; onSaved: () => void }) {
  const { t } = useI18n();
  const action = useAction();
  const [kind, setKind] = useState<DocumentKind>("aadhaar");
  const [label, setLabel] = useState("");
  const [number, setNumber] = useState("");
  const [expiresOn, setExpiresOn] = useState("");
  const [files, setFiles] = useState<File[]>([]);
  const [agreed, setAgreed] = useState(false);
  const [slip, setSlip] = useState<File | null>(null);
  const ok = files.length > 0 && (kind !== "other" || label.trim()) && agreed && (agreementOnFile || slip);

  async function submit(e: FormEvent) {
    e.preventDefault();
    const bad = [...files, ...(slip ? [slip] : [])].find((f) => !MIMES.includes(f.type) || f.size > 4 * 1024 * 1024);
    if (bad) return action.setError(`${bad.name}: JPG, PNG or PDF up to 4 MB`);
    if (files.reduce((n, f) => n + f.size, 0) > 7 * 1024 * 1024) return action.setError(t("docs_too_big"));
    const res = await action.run("save", async () =>
      api.post(`/verification/employees/${employee.id}/documents`, {
        kind,
        label: kind === "other" ? label.trim() : null,
        number: number.trim() || null,
        expiresOn: EXPIRING.has(kind) && expiresOn ? expiresOn : null,
        files: await Promise.all(files.map(readFile)),
        staffAgreed: agreed,
        slip: slip ? await readFile(slip) : null,
      }),
    );
    if (res.ok) onSaved();
  }

  return (
    <form onSubmit={submit} className="mt-2 grid gap-3 rounded-lg bg-slate-50 p-3 sm:grid-cols-2" data-testid="doc-form">
      {action.error && (
        <div className="sm:col-span-2">
          <Alert>{action.error}</Alert>
        </div>
      )}
      <Field label={t("docs_kind")}>
        {(id) => (
          <Select id={id} value={kind} onChange={(e) => setKind(e.target.value as DocumentKind)} name="kind">
            {DOC_KINDS.map((k) => (
              <option key={k} value={k}>
                {t(`dk_${k}` as DictKey)}
              </option>
            ))}
          </Select>
        )}
      </Field>
      {kind === "other" && <Field label={t("docs_label")}>{(id) => <Input id={id} value={label} maxLength={60} onChange={(e) => setLabel(e.target.value)} name="label" />}</Field>}
      <Field label={t(kind === "aadhaar" ? "docs_aadhaar_last4" : "docs_number")} hint={kind === "aadhaar" ? t("docs_masked") : undefined}>
        {(id) => <Input id={id} value={number} maxLength={kind === "aadhaar" ? 4 : 24} onChange={(e) => setNumber(e.target.value)} name="number" />}
      </Field>
      {EXPIRING.has(kind) && (
        <Field label={t("docs_valid_till")}>{(id) => <Input id={id} type="date" value={expiresOn} onChange={(e) => setExpiresOn(e.target.value)} name="expiresOn" />}</Field>
      )}
      <Field label={t("docs_files")} className="sm:col-span-2">
        {(id) => (
          <input id={id} type="file" multiple accept={MIMES.join(",")} name="files" onChange={(e) => setFiles(Array.from(e.target.files ?? []).slice(0, 3))} className="text-sm" />
        )}
      </Field>
      <div className="sm:col-span-2">
        <Checkbox label={fill(t("docs_agreed"), { name: employee.name })} checked={agreed} onChange={(e) => setAgreed(e.target.checked)} name="agreed" />
      </div>
      {!agreementOnFile && (
        <Field label={t("docs_slip")} className="sm:col-span-2">
          {(id) => <input id={id} type="file" accept="image/jpeg,image/png" name="slip" onChange={(e) => setSlip(e.target.files?.[0] ?? null)} className="text-sm" />}
        </Field>
      )}
      <div className="flex gap-2 sm:col-span-2">
        <Button type="submit" disabled={!ok} loading={action.busy === "save"}>
          {t("docs_add")}
        </Button>
        <Button type="button" variant="ghost" onClick={onCancel}>
          ✕
        </Button>
      </div>
    </form>
  );
}
