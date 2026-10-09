/// All route paths in one place.
class Routes {
  Routes._();

  static const splash = '/splash';
  static const login = '/login';
  static const otp = '/login/otp';
  static const setup = '/setup';
  static const setupStaff = '/setup/staff';

  // Owner / manager shell. `ownerHome` is the Today tab.
  static const ownerHome = '/owner/home';
  static const ownerStaff = '/owner/staff';
  static const ownerStaffAdd = '/owner/staff/add';
  static String ownerStaffProfile(String id) => '/owner/staff/$id';
  static const ownerSalary = '/owner/salary';
  static const ownerMore = '/owner/more';
  static const ownerLeaves = '/owner/more/leaves';
  static const ownerReports = '/owner/more/reports';
  static const ownerSettings = '/owner/more/settings';
  static const ownerShifts = '/owner/more/settings/shifts';
  static const ownerBranches = '/owner/more/settings/branches';
  static const ownerHolidays = '/owner/more/settings/holidays';
  static const ownerBilling = '/owner/more/billing';
  static const ownerAudit = '/owner/more/audit';
  static const ownerHelp = '/owner/more/help';

  // Employee shell.
  static const employeeConsent = '/employee/consent';
  static const employeeHome = '/employee/home';
  static const employeeAttendance = '/employee/attendance';
  static const employeeLeave = '/employee/leave';
  static const employeeSalary = '/employee/salary';
  static const employeeProfile = '/employee/profile';
  static const employeeFace = '/employee/profile/face';
}
