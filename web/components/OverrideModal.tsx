"use client";

import { useState } from "react";
import { useAction } from "@/hooks/useAsync";
import { api } from "@/lib/api";
import { OVERRIDE_STATUSES } from "@/lib/attendance";
import { formatDate } from "@/lib/format";
import type { Attendance, AttendanceStatus, LeaveType } from "@/lib/types";
import { Alert, Button, Field, Input, Modal, Select } from "./ui";

export interface OverrideTarget {
  employeeId: string;
  employeeName: string;
  date: string;
  status: AttendanceStatus;
}

/** Owner/manager attendance override. A reason is mandatory (audited). */
export function OverrideModal({
  target,
  onClose,
  onSaved,
}: {
  target: OverrideTarget | null;
  onClose: () => void;
  onSaved: (a: Attendance) => void;
}) {
  return (
    <Modal open={!!target} onClose={onClose} title="Change attendance">
      {/* key resets the form for each new target */}
      {target && <OverrideForm key={`${target.employeeId}:${target.date}`} target={target} onClose={onClose} onSaved={onSaved} />}
    </Modal>
  );
}

function OverrideForm({ target, onClose, onSaved }: { target: OverrideTarget; onClose: () => void; onSaved: (a: Attendance) => void }) {
  const [status, setStatus] = useState<AttendanceStatus>(target.status);
  const [leaveType, setLeaveType] = useState<LeaveType>("paid");
  const [reason, setReason] = useState("");
  const action = useAction();

  async function save() {
    if (!reason.trim()) return action.setError("Please write a reason — it is saved in the audit log.");
    const res = await action.run("save", () =>
      api.post<Attendance>("/attendance/override", {
        employeeId: target.employeeId,
        date: target.date,
        status,
        ...(status === "leave" ? { leaveType } : {}),
        reason: reason.trim(),
      }),
    );
    if (res.ok) onSaved(res.value);
  }

  return (
    <div className="space-y-3">
      <p className="text-sm text-slate-600">
        <span className="font-medium text-slate-900">{target.employeeName}</span> · {formatDate(target.date)}
      </p>
      <Field label="Status">
        {(id) => (
          <Select id={id} value={status} onChange={(e) => setStatus(e.target.value as AttendanceStatus)}>
            {OVERRIDE_STATUSES.map((s) => (
              <option key={s.value} value={s.value}>
                {s.label}
              </option>
            ))}
          </Select>
        )}
      </Field>
      {status === "leave" && (
        <Field label="Leave type">
          {(id) => (
            <Select id={id} value={leaveType} onChange={(e) => setLeaveType(e.target.value as LeaveType)}>
              <option value="paid">Paid</option>
              <option value="sick">Sick</option>
              <option value="unpaid">Unpaid</option>
            </Select>
          )}
        </Field>
      )}
      <Field label="Reason (required)">
        {(id) => (
          <Input id={id} value={reason} onChange={(e) => setReason(e.target.value)} placeholder="Forgot to check in, was at shop" autoFocus />
        )}
      </Field>
      {action.error && <Alert>{action.error}</Alert>}
      <div className="flex justify-end gap-2 pt-2">
        <Button variant="secondary" onClick={onClose}>
          Cancel
        </Button>
        <Button onClick={save} loading={action.busy === "save"} disabled={!reason.trim()}>
          Save
        </Button>
      </div>
    </div>
  );
}
