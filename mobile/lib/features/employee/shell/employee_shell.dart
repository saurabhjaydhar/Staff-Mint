import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/widgets/common.dart';
import '../punch/punch_providers.dart';

class EmployeeShell extends ConsumerWidget {
  const EmployeeShell({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    // Keeps the offline-sync controller alive while the employee is logged in.
    ref.listen(punchSyncProvider, (prev, next) {
      final report = next.lastReport;
      if (report == null || identical(report, prev?.lastReport)) return;
      if (report.synced > 0) showSnack(context, s.syncedCount(report.synced));
      for (final r in report.rejected) {
        showSnack(context, s.syncRejected(r.message), error: true);
      }
    });
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (i) => navigationShell.goBranch(i, initialLocation: i == navigationShell.currentIndex),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.touch_app_outlined),
            selectedIcon: const Icon(Icons.touch_app_rounded),
            label: s.navHome,
          ),
          NavigationDestination(
            icon: const Icon(Icons.calendar_month_outlined),
            selectedIcon: const Icon(Icons.calendar_month_rounded),
            label: s.navAttendance,
          ),
          NavigationDestination(
            icon: const Icon(Icons.beach_access_outlined),
            selectedIcon: const Icon(Icons.beach_access_rounded),
            label: s.navLeave,
          ),
          NavigationDestination(
            icon: const Icon(Icons.currency_rupee_rounded),
            selectedIcon: const Icon(Icons.currency_rupee_rounded),
            label: s.navSalary,
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            selectedIcon: const Icon(Icons.person_rounded),
            label: s.navProfile,
          ),
        ],
      ),
    );
  }
}
