import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/providers.dart';
import '../../../core/models/models.dart';

typedef EmployeeQuery = ({String search, String status});

final dashboardProvider = FutureProvider.autoDispose<Dashboard>(
  (ref) => ref.watch(companyApiProvider).dashboardToday(),
);

final employeesProvider = FutureProvider.autoDispose.family<List<Employee>, EmployeeQuery>(
  (ref, q) => ref.watch(employeesApiProvider).list(search: q.search, status: q.status),
);

/// Active staff, for pickers.
final activeEmployeesProvider = FutureProvider.autoDispose<List<Employee>>(
  (ref) => ref.watch(employeesApiProvider).list(status: 'active'),
);

final employeeDetailProvider = FutureProvider.autoDispose.family<Employee, String>(
  (ref, id) => ref.watch(employeesApiProvider).get(id),
);

final companyProvider = FutureProvider.autoDispose<Company>((ref) => ref.watch(companyApiProvider).get());

final rulesProvider = FutureProvider.autoDispose<List<RuleText>>((ref) => ref.watch(companyApiProvider).rules());

final shiftsProvider = FutureProvider.autoDispose<List<Shift>>((ref) => ref.watch(companyApiProvider).shifts());

final branchesProvider = FutureProvider.autoDispose<List<Branch>>((ref) => ref.watch(companyApiProvider).branches());

final holidaysProvider = FutureProvider.autoDispose.family<List<Holiday>, int>(
  (ref, year) => ref.watch(companyApiProvider).holidays(year: year),
);

final dayAttendanceProvider = FutureProvider.autoDispose.family<List<DayRow>, String>(
  (ref, date) => ref.watch(attendanceApiProvider).day(date),
);

final monthGridProvider = FutureProvider.autoDispose.family<MonthGrid, String>(
  (ref, month) => ref.watch(attendanceApiProvider).month(month),
);

/// One employee's month (staff profile strip).
final employeeMonthProvider = FutureProvider.autoDispose.family<MonthGrid, ({String month, String employeeId})>(
  (ref, q) => ref.watch(attendanceApiProvider).month(q.month, employeeId: q.employeeId),
);

final payrollRunsProvider = FutureProvider.autoDispose.family<List<PayrollRun>, String>(
  (ref, month) => ref.watch(payrollApiProvider).runs(month: month),
);

final advancesProvider = FutureProvider.autoDispose.family<List<Advance>, String?>(
  (ref, employeeId) => ref.watch(moneyApiProvider).advances(employeeId: employeeId),
);

final adjustmentsProvider = FutureProvider.autoDispose.family<List<Adjustment>, String>(
  (ref, month) => ref.watch(moneyApiProvider).adjustments(month: month),
);

final leavesProvider = FutureProvider.autoDispose.family<List<Leave>, String?>(
  (ref, status) => ref.watch(leaveApiProvider).list(status: status),
);

final billingProvider = FutureProvider.autoDispose<BillingInfo>((ref) => ref.watch(billingApiProvider).subscription());

final plansProvider = FutureProvider.autoDispose<List<Plan>>((ref) => ref.watch(billingApiProvider).plans());

final publicConfigProvider = FutureProvider.autoDispose<PublicConfig>(
  (ref) => ref.watch(companyApiProvider).publicConfig(),
);

/// Invalidate everything that depends on attendance / leave decisions.
void invalidateAttendance(WidgetRef ref) {
  ref.invalidate(dashboardProvider);
  ref.invalidate(dayAttendanceProvider);
  ref.invalidate(monthGridProvider);
  ref.invalidate(employeeMonthProvider);
  ref.invalidate(leavesProvider);
  // Salary drafts are recomputed on the server when opened; make the Salary tab ask again.
  ref.invalidate(payrollRunsProvider);
}

/// Invalidate money-related providers after advances / adjustments change.
void invalidateMoney(WidgetRef ref) {
  ref.invalidate(advancesProvider);
  ref.invalidate(adjustmentsProvider);
  ref.invalidate(employeeDetailProvider);
  ref.invalidate(payrollRunsProvider);
}
