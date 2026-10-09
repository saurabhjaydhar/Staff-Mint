import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/widgets/app_bottom_bar.dart';
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
      bottomNavigationBar: AppBottomBar(
        currentIndex: navigationShell.currentIndex,
        onTap: (i) => navigationShell.goBranch(i, initialLocation: i == navigationShell.currentIndex),
        items: [
          NavItem(icon: Icons.touch_app_outlined, activeIcon: Icons.touch_app_rounded, label: s.navHomeBi),
          NavItem(
            icon: Icons.calendar_month_outlined,
            activeIcon: Icons.calendar_month_rounded,
            label: s.navAttendanceBi,
          ),
          NavItem(icon: Icons.beach_access_outlined, activeIcon: Icons.beach_access_rounded, label: s.navLeaveBi),
          NavItem(icon: Icons.currency_rupee_rounded, activeIcon: Icons.currency_rupee_rounded, label: s.navSalaryBi),
          NavItem(icon: Icons.person_outline, activeIcon: Icons.person_rounded, label: s.navProfileBi),
        ],
      ),
    );
  }
}
