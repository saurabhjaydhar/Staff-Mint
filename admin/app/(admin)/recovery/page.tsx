"use client";

import { useState } from "react";
import { useAuth, useToast } from "@/components/providers";
import { Alert, Badge, Button, Card, Chips, Empty, Field, Input, ListSkeleton, PageHeader, Sheet } from "@/components/ui";
import { api, errorText, qs } from "@/lib/api";
import { invalidate } from "@/lib/cache";
import { ago, date, phone, type Tone } from "@/lib/format";
import { useApi } from "@/lib/useApi";

interface Recovery {
  id: string;
  oldPhone: string;
  businessName: string;
  status: "submitted" | "hold" | "completed" | "rejected" | "stopped";
  holdUntil: string | null;
  note: string | null;
  gstin: string | null;
  paymentTxnId: string | null;
  selfieVideoUrl: string | null;
  createdAt: string;
}

const LABEL: Record<Recovery["status"], [string, Tone]> = {
  submitted: ["To review", "amber"],
  hold: ["On 7-day hold", "sky"],
  completed: ["Moved", "mint"],
  rejected: ["Rejected", "slate"],
  stopped: ["Stopped by owner", "slate"],
};

export default function RecoveryPage() {
  const [status, setStatus] = useState("submitted");
  const path = `/admin/recovery-requests${qs({ status })}`;
  const { data, error, reload } = useApi<Recovery[]>(path);
  const { canEdit } = useAuth();
  const toast = useToast();
  const [rejecting, setRejecting] = useState<Recovery | null>(null);
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState<string | null>(null);

  async function act(id: string, fn: () => Promise<unknown>, done: string) {
    setBusy(id);
    try {
      await fn();
      invalidate("/admin/recovery-requests", "/admin/stats");
      await reload();
      setRejecting(null);
      toast(done);
    } catch (e) {
      toast(errorText(e), "red");
    } finally {
      setBusy(null);
    }
  }

  return (
    <div className="space-y-3">
      <PageHeader title="Number recovery" subtitle="People who lost their number and want their account moved" back="/more" />
      <Chips
        value={status}
        onChange={setStatus}
        options={[
          { value: "submitted", label: "To review" },
          { value: "hold", label: "On hold" },
          { value: "completed", label: "Moved" },
          { value: "rejected", label: "Rejected" },
          { value: "", label: "All" },
        ]}
      />
      {error && <Alert onRetry={() => void reload()}>{error}</Alert>}
      {!data ? (
        <Card padded={false}>
          <ListSkeleton rows={3} />
        </Card>
      ) : data.length === 0 ? (
        <Card padded={false}>
          <Empty>Nothing here.</Empty>
        </Card>
      ) : (
        data.map((r) => {
          const proofs = [r.gstin && `GSTIN ${r.gstin}`, r.paymentTxnId && `Payment ${r.paymentTxnId}`, r.selfieVideoUrl && "Selfie video"].filter(Boolean);
          return (
            <Card key={r.id}>
              <div className="flex items-start justify-between gap-3">
                <div className="min-w-0">
                  <p className="font-semibold">{r.businessName}</p>
                  <p className="text-sm text-slate-500">Old number {phone(r.oldPhone)} · {ago(r.createdAt)}</p>
                </div>
                <Badge tone={LABEL[r.status][1]}>{LABEL[r.status][0]}</Badge>
              </div>
              <p className="mt-3 text-sm text-slate-700">
                Proofs ({proofs.length} of 3): {proofs.join(" · ") || "none"}
              </p>
              {r.selfieVideoUrl && (
                <a href={r.selfieVideoUrl} target="_blank" rel="noreferrer" className="mt-1 inline-block text-sm font-medium text-mint-700 underline">
                  Watch selfie video
                </a>
              )}
              {r.holdUntil && <p className="mt-1 text-sm text-slate-500">Moves on {date(r.holdUntil)} unless the old owner stops it.</p>}
              {r.note && <p className="mt-1 text-sm text-slate-500">Note: {r.note}</p>}
              {canEdit && r.status === "submitted" && (
                <div className="mt-4 grid grid-cols-2 gap-2 sm:flex">
                  <Button loading={busy === r.id} onClick={() => void act(r.id, () => api.post(`/admin/recovery-requests/${r.id}/approve`), "Approved: 7-day hold started")}>
                    Approve
                  </Button>
                  <Button
                    variant="secondary"
                    disabled={busy !== null}
                    onClick={() => {
                      setNote("");
                      setRejecting(r);
                    }}
                  >
                    Reject
                  </Button>
                </div>
              )}
            </Card>
          );
        })
      )}
      <Sheet
        open={!!rejecting}
        title="Reject recovery"
        onClose={() => setRejecting(null)}
        footer={
          <>
            <Button variant="ghost" className="flex-1" onClick={() => setRejecting(null)}>
              Cancel
            </Button>
            <Button variant="danger" className="flex-1" loading={busy === rejecting?.id} onClick={() => rejecting && void act(rejecting.id, () => api.post(`/admin/recovery-requests/${rejecting.id}/reject`, { note: note.trim() || undefined }), "Rejected")}>
              Reject
            </Button>
          </>
        }
      >
        <Field label="Reason (sent to the person)" hint="For example: the GSTIN doesn't match this business.">
          {(id) => <Input id={id} value={note} maxLength={500} onChange={(e) => setNote(e.target.value)} />}
        </Field>
      </Sheet>
    </div>
  );
}
