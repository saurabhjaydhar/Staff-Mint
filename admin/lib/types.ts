// Shapes returned by the StaffMint admin API (/api/v1/admin…).

export type AdminRole = "admin" | "viewer";
export type BusinessStatus = "trial" | "paid" | "past_due" | "free" | "closed" | "billed_with";

export interface Admin {
  id: string | null;
  email: string;
  name: string;
  role: AdminRole;
  active: boolean;
  lastLoginAt?: string | null;
  createdAt?: string;
}

export interface Stats {
  businesses: { total: number; trial: number; paid: number; pastDue: number; free: number; billedWith: number; closed: number };
  owners: number;
  staff: number;
  signups: { week: number; month: number; perDay: { date: string; count: number }[] };
  mrrPaise: number;
  paidPlans: Record<string, number>;
  trialsEndingSoon: number;
  pendingRecoveries: number;
  failedMessages: number;
}

export interface Page<T> {
  total: number;
  page: number;
  limit: number;
  rows: T[];
}

export interface BusinessRow {
  id: string;
  name: string;
  businessType: string;
  status: BusinessStatus;
  planCode: string;
  trialEndsAt: string | null;
  paidUntil: string | null;
  staffCount: number;
  owner: { name: string; phone: string } | null;
  createdAt: string;
}

export interface Trial {
  planCode: string;
  planName: string;
  endsAt: string;
  daysLeft: number;
  active: boolean;
  ended: boolean;
}

export interface AdminActionRow {
  id: string;
  actor: string;
  action: string;
  companyId: string | null;
  target: string | null;
  details: Record<string, unknown>;
  createdAt: string;
}

export interface BusinessDetail {
  id: string;
  name: string;
  businessType: string;
  timezone: string;
  address: string | null;
  createdAt: string;
  closedAt: string | null;
  status: BusinessStatus;
  plan: { code: string; name: string; staffLimit: number };
  trial: Trial | null;
  billedTo: { id: string; name: string } | null;
  onThisBill: { id: string; name: string }[];
  staff: { active: number; total: number };
  branches: number;
  people: { role: string; name: string; phone: string; main: boolean }[];
  subscriptions: {
    id: string;
    provider: string;
    planCode: string;
    status: string;
    interval: string;
    trialEndsAt: string | null;
    currentPeriodEnd: string | null;
    pricePaise: number | null;
    createdAt: string;
  }[];
  failedMessages: { id: string; channel: string; template: string | null; to: string | null; error: string | null; createdAt: string }[];
  actions: AdminActionRow[];
}

export interface Plan {
  code: string;
  name: string;
  priceMonthlyPaise: number;
  priceYearlyPaise: number;
  staffLimit: number;
  extraStaffPricePaise?: number;
  maxStaffHardCap?: number;
  trialDays: number;
  features: string[];
  sort?: number;
  active?: boolean;
  country?: string;
  currency?: string;
}

export interface ConfigRow {
  key: string;
  value: unknown;
  defaultValue: unknown;
  changed: boolean;
  businessOverrides: number;
}

export interface Flag {
  key: string;
  enabled: boolean;
  plans: string[];
  companyIds: string[];
  description?: string;
}

export interface MessageRow {
  id: string;
  companyId: string;
  companyName: string;
  channel: string;
  template: string | null;
  title: string | null;
  to: string | null;
  status: string;
  provider: string | null;
  error: string | null;
  createdAt: string;
}

export interface RecoveryRequest {
  id: string;
  status: string;
  [k: string]: unknown;
}
