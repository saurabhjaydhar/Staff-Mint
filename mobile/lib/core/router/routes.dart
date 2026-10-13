/// All route paths in one place.
class Routes {
  Routes._();

  static const splash = '/splash';
  static const login = '/login';
  static const otp = '/login/otp';
  static const setup = '/setup';
  static const setupStaff = '/setup/staff';

  /// Account chooser (after login with several businesses, or from Profile).
  static const accounts = '/accounts';

  /// Create another business from any account, staff included.
  static const accountsNew = '/accounts/new';

  /// Lost the old number: bring the account to this one (email or support).
  static const accountsRecover = '/accounts/recover';

  /// Own payslips from businesses this person left (12 months).
  static const accountsPayslips = '/accounts/payslips';

  // Owner / manager shell. `ownerHome` is the Today tab.
  static const ownerHome = '/owner/home';
  static const ownerStaff = '/owner/staff';
  static const ownerStaffAdd = '/owner/staff/add';
  static const ownerTeam = '/owner/staff/team';
  static const ownerRoster = '/owner/staff/roster';
  static String ownerStaffProfile(String id) => '/owner/staff/$id';
  static const ownerSalary = '/owner/salary';
  static const ownerMore = '/owner/more';
  static const ownerLeaves = '/owner/more/leaves';
  static const ownerReports = '/owner/more/reports';
  static const ownerSettings = '/owner/more/settings';
  static const ownerShifts = '/owner/more/settings/shifts';
  static const ownerBranches = '/owner/more/settings/branches';
  static const ownerHolidays = '/owner/more/settings/holidays';
  static const ownerAccountants = '/owner/more/settings/accountants';
  static const ownerOwners = '/owner/more/settings/owners';
  static const ownerStatutory = '/owner/more/settings/statutory';
  static const ownerBilling = '/owner/more/billing';
  static const ownerTimings = '/owner/more/timings';
  static const ownerAttendanceRules = '/owner/more/rules/attendance';
  static const ownerSalaryRules = '/owner/more/rules/salary';
  static const ownerSafety = '/owner/more/rules/safety';
  static const ownerAudit = '/owner/more/audit';
  static const ownerHelp = '/owner/more/help';
  static const ownerProfile = '/owner/more/profile';

  // Employee shell.
  static const employeeConsent = '/employee/consent';
  static const employeeHome = '/employee/home';
  static const employeeVerify = '/employee/home/verify';
  static const employeeAttendance = '/employee/attendance';
  static const employeeLeave = '/employee/leave';
  static const employeeSalary = '/employee/salary';
  static const employeeProfile = '/employee/profile';
  static const employeeFace = '/employee/profile/face';
  static const employeeDocuments = '/employee/profile/documents';
}
