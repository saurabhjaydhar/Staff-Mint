/** JSON serializers matching docs/API.md resource shapes. */
import { fromGeoPoint } from '../lib/geo.js';

const id = (v: any) => (v ? String(v) : null);

export const branchView = (b: any) => ({
  id: String(b._id),
  name: b.name,
  location: { ...(fromGeoPoint(b.geo) ?? { lat: null, lng: null }), address: b.address ?? null },
  radiusM: b.radiusM,
  shiftId: id(b.shiftId),
  isDefault: !!b.isDefault,
});

export const shiftView = (s: any) => ({ id: String(s._id), name: s.name, start: s.start, end: s.end, graceMinutes: s.graceMinutes ?? null, weeklyOff: s.weeklyOff ?? [], weeklyOffWeeks: s.weeklyOffWeeks ?? {}, minStaff: s.minStaff ?? 0, isDefault: !!s.isDefault });

export const employeeView = (e: any, extra: Record<string, unknown> = {}) => ({
  id: String(e._id),
  name: e.name,
  phone: e.phone,
  branchId: id(e.branchId),
  shiftId: id(e.shiftId),
  wageType: e.wageType,
  ratePaise: e.ratePaise,
  designation: e.designation ?? null,
  joiningDate: e.joiningDate ?? null,
  status: e.status,
  appRole: e.appRole ?? 'employee',
  /** null = follows the business setting. */
  attendanceMarking: e.attendanceMarking ?? null,
  consent: { location: !!e.consent?.location, at: e.consent?.at ?? null },
  face: { status: e.face?.status ?? 'none', enrolledAt: e.face?.enrolledAt ?? null, approvedAt: e.face?.approvedAt ?? null },
  /** Background verification badge: none / asked / in_progress / verified / needs_attention. */
  verification: e.verification?.status ?? 'none',
  hasDevice: !!extra.hasDevice,
  /** Has this number opened StaffMint for this business yet; when the app invite was last sent. */
  linked: !!e.userId,
  invitedAt: e.invitedAt ?? null,
  language: e.language ?? 'hi',
  ...Object.fromEntries(Object.entries(extra).filter(([k]) => k !== 'hasDevice')),
});

export const leaveView = (l: any, employeeName?: string) => ({
  id: String(l._id),
  employeeId: String(l.employeeId?._id ?? l.employeeId),
  employeeName: employeeName ?? l.employeeId?.name ?? null,
  type: l.type,
  from: l.from,
  to: l.to,
  days: l.days,
  halfDay: !!l.halfDay,
  reason: l.reason ?? null,
  status: l.status,
  decidedAt: l.decidedAt ?? null,
  note: l.note ?? null,
  createdAt: l.createdAt,
});

export const holidayView = (h: any) => ({ id: String(h._id), date: h.date, name: h.name });
