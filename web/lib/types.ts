// Shared types mirroring docs/API.md (StaffMint API v1).
// Money is always integer paise. Dates are YYYY-MM-DD, months YYYY-MM, instants ISO-8601.

export type Role = "owner" | "manager" | "employee" | "ca";
export type Lang = "en" | "hi";

export interface User {
  id: string;
  phone: string;
  name: string;
  role: Role;
  companyId: string | null;
  employeeId: string | null;
  language: Lang;
  email?: string | null;
}

/** `GET /me/profile` (web shows the owner / manager / CA parts). */
export interface Profile {
  user: { id: string; name: string; phone: string; email: string | null; role: Role; language: Lang; photoUrl: string | null; memberSince: string | null; lastLoginAt: string | null };
  company: { id: string; name: string; businessType: string; planName: string | null } | null;
  work: unknown | null;
  bank: { holderName: string; accountLast4: string | null; ifsc: string | null; upiId: string | null } | null;
  emergencyContact: { name: string; phone: string | null; relation: string | null } | null;
  completeness: { percent: number; missing: string[] };
}

export type PlanFeature =
  | "attendance"
  | "leave"
  | "digest"
  | "payroll"
  | "advances"
  | "payslips"
  | "assistant"
  | "branches"
  | "reports"
  | "roster"
  | "roster_repeat"
  | "whatsapp_payslips"
  | "ca_access"
  | "priority_support";

export interface Plan {
  code: string;
  name: string;
  priceMonthlyPaise: number;
  priceYearlyPaise: number;
  currency: string;
  staffLimit: number;
  extraStaffPricePaise: number;
  trialDays: number;
  features: (PlanFeature | string)[];
}

export interface GeoPoint {
  lat: number;
  lng: number;
  address?: string;
}

export type MonthDivisor = "days_in_month" | "30" | "26";

export interface CompanySettings {
  graceMinutes: number;
  halfDayHours: number;
  monthDivisor: MonthDivisor;
  missingCheckoutPolicy: "half_day" | "present" | "flag";
  weekOffsPaid: boolean;
  holidaysPaid: boolean;
  sickLeavePaid: boolean;
  outsideGeofencePolicy: "block" | "request_approval";
  phoneLockPolicy: "off" | "recommended" | "required";
  faceMatchPolicy: "off" | "review";
  /** Staff check in on their phone, or the owner/manager marks it. Each staff member can differ. */
  attendanceMarking?: "self" | "owner";
  /** Staff the owner marks are counted present at night unless marked otherwise. */
  presentByDefault?: boolean;
  language: Lang;
  digestTime: string;
  roundToRupee: boolean;
  selfieRequired: boolean;
  maxDeviceTimeDriftMin: number;
  selfieRetentionDays: number;
  whatsappAlerts: boolean;
  /** Ex-staff can see their own payslips for 12 months. */
  exStaffPayslips?: boolean;
}

export type SubscriptionStatus = "trialing" | "active" | "past_due" | "cancelled" | "free";

export interface Subscription {
  status: SubscriptionStatus;
  planCode: string;
  currentPeriodEnd: string | null;
}

export interface Company {
  id: string;
  name: string;
  businessType: string;
  country: string;
  currency: string;
  timezone: string;
  location: GeoPoint;
  settings: CompanySettings;
  plan: Plan;
  subscription: Subscription;
  /** Free trial countdown, or "trial ended" for 30 days after. */
  trial?: Trial | null;
}

export interface Trial {
  planCode: string;
  planName: string;
  endsAt: string;
  daysLeft: number;
  active: boolean;
  ended: boolean;
  /** Paid features that stop when the trial ends. */
  paidFeatures: string[];
}

export interface Branch {
  id: string;
  name: string;
  location: GeoPoint;
  radiusM: number;
  shiftId: string | null;
}

export interface Shift {
  id: string;
  name: string;
  start: string;
  end: string;
  graceMinutes: number | null;
  weeklyOff: number[];
  /** Alternating offs: weekday → weeks of the month it is off ({ "6": [1, 3] } = 1st and 3rd Saturday). */
  weeklyOffWeeks?: Record<string, number[]>;
  isDefault?: boolean;
}

export interface RosterCell {
  date: string;
  kind: "shift" | "off";
  shiftId: string | null;
  /** From the person's usual shift and weekly off, not the roster. */
  usual: boolean;
  /** Changed, not sent to staff yet. */
  changed: boolean;
  leave: string | null;
  employed: boolean;
}

export interface RosterWeek {
  weekStart: string;
  days: { date: string; holiday: string | null }[];
  shifts: Shift[];
  staff: { id: string; name: string; designation: string | null; cells: RosterCell[] }[];
  notSent: number;
  problems: { type: "leave_working" | "no_day_off"; employeeId: string; name: string; date: string }[];
  repeat: { mode: "same" | "rotate"; startWeek: string; autoSend: boolean; staff: number } | null;
  repeatAllowed: boolean;
}

export type WageType = "monthly" | "daily";

export interface Employee {
  id: string;
  name: string;
  phone: string;
  branchId: string | null;
  shiftId: string | null;
  wageType: WageType;
  ratePaise: number;
  designation?: string;
  joiningDate?: string;
  status: "active" | "inactive";
  consent: { location: boolean; at?: string };
  hasDevice: boolean;
  /** Has opened StaffMint for this business; when the app invite was last sent. */
  linked?: boolean;
  invitedAt?: string | null;
  language: Lang;
  /** 'manager' marks attendance and approves leave; can't see salary or billing. */
  appRole?: "employee" | "manager";
}

export interface EmployeeInput {
  name: string;
  phone: string;
  wageType?: WageType;
  ratePaise?: number;
  branchId?: string;
  shiftId?: string;
  designation?: string;
  joiningDate?: string;
}

export type PunchFlag =
  | "late_sync"
  | "device_time_drift"
  | "mock_location"
  | "low_accuracy"
  | "outside_geofence"
  | "phone_lock_failed"
  | "no_phone_lock"
  | "face_mismatch"
  | "face_unsure"
  | "face_no_face"
  | "face_many_faces"
  | "face_check_failed";

export interface Punch {
  id: string;
  type: "in" | "out";
  clientTime: string;
  serverTime: string;
  geo: { lat: number; lng: number; accuracyM: number } | null;
  distanceM: number | null;
  insideGeofence: boolean | null;
  selfieUrl: string | null;
  mockLocation: boolean;
  /** Phone screen-lock result; null when the company does not ask for it. */
  lockCheck: "passed" | "failed" | "unavailable" | null;
  /** Selfie vs approved face photo; null when face check did not run. */
  face: { result: "match" | "unsure" | "mismatch" | "no_face" | "many_faces" | "error"; similarity: number | null } | null;
  deviceId: string;
  source: "app" | "offline_sync" | "owner" | "assistant" | "import";
  flags: (PunchFlag | string)[];
  approval: "not_required" | "pending" | "approved" | "rejected";
}

export type AttendanceStatus =
  | "present"
  | "absent"
  | "half_day"
  | "leave"
  | "holiday"
  | "week_off";

export type LeaveType = "paid" | "sick" | "unpaid";

export interface Attendance {
  id: string;
  employeeId: string;
  date: string;
  status: AttendanceStatus | null;
  leaveType?: LeaveType;
  punches: Punch[];
  lateMinutes: number;
  earlyOutMinutes: number;
  workedMinutes: number;
  overridden: boolean;
  overrideReason?: string;
  flags: string[];
}

export type DisplayStatus =
  | "present"
  | "late"
  | "checked_in"
  | "absent"
  | "half_day"
  | "leave"
  | "holiday"
  | "week_off"
  | "not_marked";

export interface DayRow {
  employee: { id: string; name: string; phone: string; designation?: string };
  record: Attendance | null;
  displayStatus: DisplayStatus;
}

export interface MonthGrid {
  month: string;
  days: string[];
  rows: {
    employee: { id: string; name: string; phone?: string; designation?: string };
    days: Record<string, DisplayStatus | null>;
    totals: Record<string, number>;
  }[];
}

export interface Leave {
  id: string;
  employeeId: string;
  employeeName: string;
  type: LeaveType;
  from: string;
  to: string;
  days: number;
  halfDay: boolean;
  reason?: string;
  status: "pending" | "approved" | "rejected" | "cancelled";
  decidedAt?: string;
  note?: string;
}

export interface LeaveBalance {
  employeeId: string;
  year: number;
  paid: number;
  sick: number;
  usedPaid: number;
  usedSick: number;
}

export interface Advance {
  id: string;
  employeeId: string;
  employeeName: string;
  amountPaise: number;
  date: string;
  mode: "installments" | "full_next";
  installments: number;
  installmentPaise: number;
  repaidPaise: number;
  balancePaise: number;
  status: "active" | "closed";
  skipMonths: string[];
  note?: string;
}

export interface Adjustment {
  id: string;
  employeeId: string;
  employeeName: string;
  month: string;
  type: "bonus" | "deduction";
  amountPaise: number;
  note?: string;
}

export interface PayslipLine {
  code: string;
  kind: "earning" | "deduction" | "employer";
  label: string;
  amountPaise: number;
  explanation: string;
}

export interface Payslip {
  id: string;
  runId: string;
  employeeId: string;
  employeeName: string;
  month: string;
  revision: number;
  wageType: WageType;
  ratePaise: number;
  payableDays: number;
  daysInMonth: number;
  divisor: number;
  summary: {
    present: number;
    halfDay: number;
    absent: number;
    paidLeave: number;
    unpaidLeave: number;
    holidays: number;
    weekOffs: number;
    unmarked: number;
  };
  lines: PayslipLine[];
  grossPaise: number;
  deductionsPaise: number;
  netPaise: number;
  status: "draft" | "final" | "sent";
  pdfUrl: string | null;
  sentAt?: string;
  /** PF / ESI the owner pays on top of salary (empty for most small shops). */
  employerContributions?: PayslipLine[];
  paidOn?: string | null;
  paymentMethod?: PaymentMethod | null;
}

export type PaymentMethod = "cash" | "upi" | "bank" | "mixed";

/** The shop's PF / ESI / Professional Tax settings. */
export interface StatutorySettings {
  pfEnabled: boolean;
  pfNumber: string | null;
  basicPercent: number;
  pfRatePercent: number;
  pfWageCeilingPaise: number;
  pfCapAtCeiling: boolean;
  esiEnabled: boolean;
  esiNumber: string | null;
  esiEmployeePercent: number;
  esiEmployerPercent: number;
  esiWageLimitPaise: number;
  ptEnabled: boolean;
  ptState: string | null;
  ptMonthlyPaise: number;
  ptMinGrossPaise: number;
}

/** What a staff member's salary slip shows besides name and phone. PAN is masked. */
export interface EmployeeStatutory {
  employeeCode: string | null;
  uan: string | null;
  esicNumber: string | null;
  panMasked: string | null;
  pfExempt: boolean;
  esiExempt: boolean;
}

export interface PayrollAnomaly {
  employeeId: string;
  employeeName: string;
  code: string;
  message: string;
}

export interface PayrollRun {
  id: string;
  month: string;
  revision: number;
  status: "draft" | "approved" | "paid" | "superseded";
  engineVersion: string;
  totals: { grossPaise: number; deductionsPaise: number; netPaise: number; employees: number };
  anomalies: PayrollAnomaly[];
  approvedAt?: string;
  paidAt?: string;
  paidOn?: string | null;
  paymentMethod?: PaymentMethod | null;
  payslips?: Payslip[];
}

export interface CompareRow {
  employeeName: string;
  ours: number | null;
  theirs: number | null;
  diffPaise: number | null;
  reasons: string[];
}

export interface CompareResult {
  rows: CompareRow[];
  matched: number;
  // The contract does not pin the shape; accept a count or a list of names.
  unmatched: number | (string | { name?: string; employeeName?: string })[];
}

export type AuditChannel = "app" | "web" | "assistant" | "whatsapp" | "system" | "import";

export interface AuditLog {
  id: string;
  actorId: string;
  actorName: string;
  channel: AuditChannel;
  action: string;
  entity: string;
  entityId: string;
  before: unknown;
  after: unknown;
  at: string;
  /** One plain sentence for people, e.g. "Raju: 1 Oct set to Absent". */
  text?: string | null;
  category?: string;
  changes?: { label: string; from?: string | null; to?: string | null }[];
}

export interface Holiday {
  id: string;
  date: string;
  name: string;
}

// ---- Auth ----
export interface OtpRequestResult {
  requestId: string;
  expiresInSec: number;
  devCode?: string;
}

export interface Tokens {
  accessToken: string;
  refreshToken: string;
}

/** One business this number can open (owner here, staff there, CA elsewhere). */
export interface Membership {
  id: string;
  companyId: string;
  companyName: string;
  businessType: string | null;
  role: Role;
  lastUsedAt: string | null;
  /** Staff account bound to another phone. */
  lockedToOtherPhone?: boolean;
  /** Pinned to the top of the chooser. */
  pinned?: boolean;
}

/** "Your access to X ended on …" until dismissed. */
export interface EndedNotice {
  id: string;
  companyName: string;
  endedAt: string | null;
  endedReason: "removed" | "closed" | "phone_changed" | "import_rollback" | null;
}

/** A business this person closed that can still be restored. */
export interface ClosedBusiness {
  companyId: string;
  companyName: string;
  businessType: string | null;
  closedAt: string | null;
  restoreUntil: string | null;
}

export interface AccountChange {
  kind: "ended" | "role_changed";
  reason: string | null;
  companyName: string;
  role: Role | null;
  activeMembershipId: string | null;
}

export interface DeviceRequestItem {
  id: string;
  employeeId: string | null;
  employeeName: string | null;
  deviceName: string | null;
  createdAt: string;
}

export interface Accountant {
  id: string;
  name: string;
  phone: string;
  addedAt: string;
}

export interface OtpVerifyResult extends Tokens {
  user: User;
  needsCompanySetup: boolean;
  activeMembershipId: string | null;
  memberships: Membership[];
  /** More than one account: ask which one to open. */
  needsAccountChoice: boolean;
  /** Set instead of a session when the app must first ask "Is this you?". */
  identityCheck?: IdentityCheck;
}

/** Login paused: "Is this you, R*** K***?" (the number may have been recycled). */
export interface IdentityCheck {
  token: string;
  maskedName: string;
}

export interface OwnerItem {
  id: string;
  userId: string;
  name: string;
  phone: string;
  isMain: boolean;
  canManageBilling: boolean;
  isYou: boolean;
}

export interface TransferOffer {
  id: string;
  companyId: string;
  companyName: string | null;
  fromName: string | null;
  kind: "transfer" | "recovery";
  toPhoneMasked: string;
  keepAs: "co_owner" | "leave";
  status: string;
  expiresAt: string;
}

export interface RecoveryHold {
  id: string;
  oldPhoneMasked: string;
  businessName: string;
  status: "submitted" | "hold" | "completed" | "rejected" | "stopped";
  holdUntil: string | null;
  note: string | null;
}

/** `POST /auth/switch` */
export type SwitchResult = OtpVerifyResult;

export interface MeResult {
  user: User;
  company: Company | null;
  employee: Employee | null;
  activeMembershipId?: string | null;
  memberships?: Membership[];
  blockedAccounts?: Membership[];
  endedNotices?: EndedNotice[];
  closedBusinesses?: ClosedBusiness[];
  pendingTransfers?: TransferOffer[];
  recoveryHolds?: RecoveryHold[];
}

export interface CompanySetupInput {
  name: string;
  businessType: string;
  location: GeoPoint;
  openingTime: string;
  closingTime?: string;
  weeklyOff: number[];
  country?: string;
  timezone?: string;
  currency?: string;
}

export interface CompanySetupResult extends Tokens {
  company: Company;
  activeMembershipId?: string;
  memberships?: Membership[];
}

// ---- Dashboard ----
export interface DashboardToday {
  date: string;
  counts: {
    total: number;
    present: number;
    late: number;
    absent: number;
    onLeave: number;
    notMarked: number;
    checkedIn: number;
    /** Week off / holiday today. */
    off?: number;
  };
  needsAction: {
    /** `balance`: paid/sick leaves left before and after approving. */
    leaveRequests: (Leave & { balance?: { left: number; after: number } | null })[];
    punchApprovals: { attendanceId: string; employeeName: string; punch: Punch }[];
    flags: { employeeName: string; date: string; flags: string[] }[];
    deviceRequests?: DeviceRequestItem[];
  };
  plan: { staffCount: number; staffLimit: number };
  /** Owners only: the "Let's get your shop running" checklist. */
  setup?: {
    steps: { business: boolean; staffAdded: boolean; staffJoined: boolean; salarySet: boolean; teamAdded: boolean };
    done: number;
    total: number;
    staff: number;
    joined: number;
    notJoined: number;
  } | null;
}

// ---- Imports ----
export type ImportKind = "staff" | "attendance";
export type ImportSource = "auto" | "salarybox" | "pagarbook" | "generic";

export type ImportField =
  | "name"
  | "phone"
  | "ratePaise"
  | "wageType"
  | "designation"
  | "joiningDate"
  | "branch"
  | "advanceBalancePaise"
  | "paidLeaveBalance"
  | "sickLeaveBalance"
  | "lastSalaryPaise";

export interface ImportRow {
  index: number;
  values: Record<string, unknown>;
  issues: { field: string; message: string }[];
  /** Not in the contract; honoured if the backend sends it. */
  skipped?: boolean;
}

export interface ImportSession {
  id: string;
  kind: ImportKind;
  source: ImportSource;
  status: "review" | "committed" | "rolled_back";
  headers: string[];
  mapping: Record<string, string | null>;
  rows: ImportRow[];
  flaggedCount: number;
  totalRows: number;
  undoUntil?: string;
  rollbackUntil?: string;
  /** Not in the contract; honoured if the backend sends it. */
  skipRows?: number[];
}

export interface ImportPatch {
  mapping?: Record<string, string | null>;
  fixes?: { row: number; field: string; value: unknown }[];
  skipRows?: number[];
}

export interface ImportCommitResult {
  created: number;
  updated: number;
  skipped: number;
  undoUntil: string;
  rollbackUntil: string;
}

// ---- Billing ----
export interface SubscriptionInfo {
  subscription: Subscription;
  plan: Plan;
  staffCount: number;
  trial?: Trial | null;
  /** Paid together with another business (one bill); its plan is managed there. */
  billedTo?: { companyId: string; name: string } | null;
}

export interface BillingBusiness {
  companyId: string;
  name: string;
  staffCount: number;
}

/** One bill for several businesses of the same main owner. */
export interface BillingGroup {
  payer: BillingBusiness;
  isPayer: boolean;
  members: BillingBusiness[];
  candidates: BillingBusiness[];
  totalStaff: number;
  extraBusinessPricePaise: number;
}

/** An accountant's client, with last month's payroll state. */
export interface CaClient {
  membershipId: string;
  companyId: string;
  companyName: string;
  businessType: string | null;
  pinned: boolean;
  staffCount: number;
  month: string;
  payrollStatus: "not_started" | "draft" | "approved" | "paid";
  netPaise: number | null;
}

export interface SubscribeResult {
  provider: string;
  subscriptionId: string;
  checkoutUrl: string;
  keyId?: string;
}

export type ReportType = "attendance" | "salary" | "advances" | "late";
export type ReportFormat = "pdf" | "xlsx";
