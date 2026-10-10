/** Seed values for dynamic config (PRD §16 rule 6, §20). Live values are in the DB and editable without an app release. */

export const DEFAULT_PLANS = [
  {
    code: 'free',
    name: 'Free',
    priceMonthlyPaise: 0,
    priceYearlyPaise: 0,
    staffLimit: 5,
    extraStaffPricePaise: 0,
    maxStaffHardCap: 5,
    trialDays: 0,
    features: ['attendance', 'leave', 'digest'],
    sort: 0,
  },
  {
    code: 'starter',
    name: 'Starter',
    priceMonthlyPaise: 49900,
    priceYearlyPaise: 499000,
    staffLimit: 15,
    extraStaffPricePaise: 0,
    maxStaffHardCap: 15,
    trialDays: 14,
    features: ['attendance', 'leave', 'digest', 'payroll', 'advances', 'payslips', 'assistant', 'reports'],
    sort: 1,
  },
  {
    code: 'growth',
    name: 'Growth',
    priceMonthlyPaise: 99900,
    priceYearlyPaise: 999000,
    staffLimit: 30,
    extraStaffPricePaise: 0,
    maxStaffHardCap: 30,
    trialDays: 14,
    features: ['attendance', 'leave', 'digest', 'payroll', 'advances', 'payslips', 'assistant', 'reports', 'branches', 'whatsapp_payslips', 'whatsapp_assistant', 'face_match'],
    sort: 2,
  },
  {
    code: 'pro',
    name: 'Pro',
    priceMonthlyPaise: 179900,
    priceYearlyPaise: 1799000,
    staffLimit: 50,
    extraStaffPricePaise: 3000,
    maxStaffHardCap: 500,
    trialDays: 14,
    features: [
      'attendance',
      'leave',
      'digest',
      'payroll',
      'advances',
      'payslips',
      'assistant',
      'reports',
      'branches',
      'whatsapp_payslips',
      'whatsapp_assistant',
      'priority_support',
      'ca_access',
      'face_match',
    ],
    sort: 3,
  },
];

export const DEFAULT_CONFIG: Record<string, unknown> = {
  'signup.trialPlan': 'starter',
  'billing.priceLockMonths': 24,
  'billing.exportWindowDays': 30,
  'leave.types': ['paid', 'sick', 'unpaid'],
  'assistant.pendingTtlMinutes': 15,
  'attendance.offlineLateSyncHours': 12,
  /** Sent in staff invites. Replace with the real Play Store link at launch. */
  'app.downloadUrl': 'https://play.google.com/store/apps/details?id=app.staffmint',
  /** Days an owner can restore a business they closed. */
  'accounts.restoreDays': 30,
};

/** India national + major holidays template (editable per company). Dates for 2026–2027. */
export const HOLIDAY_TEMPLATES: Record<string, Record<number, { date: string; name: string }[]>> = {
  IN: {
    2026: [
      { date: '2026-01-26', name: 'Republic Day' },
      { date: '2026-03-04', name: 'Holi' },
      { date: '2026-03-21', name: 'Eid ul-Fitr' },
      { date: '2026-08-15', name: 'Independence Day' },
      { date: '2026-08-28', name: 'Raksha Bandhan' },
      { date: '2026-10-02', name: 'Gandhi Jayanti' },
      { date: '2026-10-20', name: 'Dussehra' },
      { date: '2026-11-08', name: 'Diwali' },
      { date: '2026-11-09', name: 'Govardhan Puja' },
      { date: '2026-12-25', name: 'Christmas' },
    ],
    2027: [
      { date: '2027-01-26', name: 'Republic Day' },
      { date: '2027-03-22', name: 'Holi' },
      { date: '2027-03-10', name: 'Eid ul-Fitr' },
      { date: '2027-08-15', name: 'Independence Day' },
      { date: '2027-10-02', name: 'Gandhi Jayanti' },
      { date: '2027-10-09', name: 'Dussehra' },
      { date: '2027-10-29', name: 'Diwali' },
      { date: '2027-12-25', name: 'Christmas' },
    ],
  },
};
