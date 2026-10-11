"use client";

import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { Suspense } from "react";
import Link from "next/link";
import { Alert, Badge, Card, Chips, Empty, ListSkeleton, LoadMore, PageHeader } from "@/components/ui";
import { qs } from "@/lib/api";
import { ago, phone, type Tone } from "@/lib/format";
import type { MessageRow } from "@/lib/types";
import { usePaged } from "@/lib/usePaged";

const STATUS_TONE: Record<string, Tone> = { failed: "red", queued: "amber", sent: "sky", delivered: "mint", read: "mint" };
const CHANNEL_LABEL: Record<string, string> = { whatsapp: "WhatsApp", push: "Push", sms: "SMS", email: "Email" };

function Messages() {
  const params = useSearchParams();
  const router = useRouter();
  const pathname = usePathname();
  const status = params.get("status") ?? "";
  const channel = params.get("channel") ?? "";
  const set = (next: { status?: string; channel?: string }) => router.replace(`${pathname}${qs({ status, channel, ...next })}`, { scroll: false });
  const { rows, total, error, loadingMore, more, reload } = usePaged<MessageRow>(`/admin/messages${qs({ status, channel })}`, 30);

  return (
    <div className="space-y-3">
      <PageHeader title="Messages" subtitle="WhatsApp, push, SMS and email sent by StaffMint" />
      <Chips
        value={status}
        onChange={(v) => set({ status: v })}
        options={[
          { value: "", label: "All" },
          { value: "failed", label: "Failed" },
          { value: "queued", label: "Waiting" },
          { value: "sent", label: "Sent" },
        ]}
      />
      <Chips
        value={channel}
        onChange={(v) => set({ channel: v })}
        options={[
          { value: "", label: "Every channel" },
          { value: "whatsapp", label: "WhatsApp" },
          { value: "push", label: "Push" },
          { value: "sms", label: "SMS" },
          { value: "email", label: "Email" },
        ]}
      />
      {error && <Alert onRetry={() => void reload()}>{error}</Alert>}
      <Card padded={false}>
        {!rows ? (
          <ListSkeleton />
        ) : rows.length === 0 ? (
          <Empty>{status === "failed" ? "No failed messages. 🎉" : "No messages."}</Empty>
        ) : (
          <>
            <ul className="divide-y divide-slate-100">
              {rows.map((m) => (
                <li key={m.id} className="px-4 py-3 text-sm">
                  <div className="flex items-center gap-2">
                    <span className="min-w-0 flex-1 truncate font-medium">{m.template ?? m.title ?? CHANNEL_LABEL[m.channel]}</span>
                    <Badge tone={STATUS_TONE[m.status] ?? "slate"}>{m.status}</Badge>
                  </div>
                  <p className="mt-0.5 truncate text-xs text-slate-500">
                    {CHANNEL_LABEL[m.channel] ?? m.channel}
                    {m.to ? ` to ${phone(m.to)}` : ""} ·{" "}
                    <Link href={`/businesses/${m.companyId}`} className="underline">
                      {m.companyName || "business"}
                    </Link>{" "}
                    · {ago(m.createdAt)}
                  </p>
                  {m.error && <p className="mt-1 text-xs break-words text-red-600">{m.error}</p>}
                </li>
              ))}
            </ul>
            <LoadMore shown={rows.length} total={total} loading={loadingMore} onMore={() => void more()} />
          </>
        )}
      </Card>
    </div>
  );
}

export default function MessagesPage() {
  return (
    <Suspense>
      <Messages />
    </Suspense>
  );
}
