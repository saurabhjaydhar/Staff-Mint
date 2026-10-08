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
