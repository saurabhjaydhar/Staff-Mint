import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/providers.dart';
import '../../core/models/models.dart';

final myMonthProvider = FutureProvider.autoDispose.family<MonthGrid, String>(
  (ref, month) => ref.watch(attendanceApiProvider).month(month),
);

final myLeavesProvider = FutureProvider.autoDispose<List<Leave>>((ref) => ref.watch(leaveApiProvider).list());

final myLeaveBalancesProvider = FutureProvider.autoDispose<List<LeaveBalance>>(
  (ref) => ref.watch(leaveApiProvider).balances(year: DateTime.now().year),
);

final mySalaryProvider = FutureProvider.autoDispose<SalaryOverview>((ref) => ref.watch(meApiProvider).salary());

/// This week's roster as the owner sent it (by any date in the week).
final myRosterProvider = FutureProvider.autoDispose.family<MyRosterWeek, String>(
  (ref, date) => ref.watch(rosterApiProvider).mine(date),
);

/// Swaps this person asked for or was asked (recent and open ones).
final mySwapsProvider = FutureProvider.autoDispose<List<RosterSwap>>((ref) => ref.watch(rosterApiProvider).swaps());
