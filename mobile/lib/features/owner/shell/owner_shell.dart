import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/router/routes.dart';

/// Owner/manager bottom navigation + floating Mint button on every tab.
class OwnerShell extends StatelessWidget {
  const OwnerShell({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Scaffold(
      body: navigationShell,
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('mintFab'),
        heroTag: 'mintFab',
        onPressed: () => context.push(Routes.assistant),
        icon: const Icon(Icons.auto_awesome_rounded),
        label: Text(s.mint, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (i) => navigationShell.goBranch(i, initialLocation: i == navigationShell.currentIndex),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home_rounded),
            label: s.navHome,
          ),
          NavigationDestination(
            icon: const Icon(Icons.people_outline),
            selectedIcon: const Icon(Icons.people_rounded),
            label: s.navStaff,
          ),
          NavigationDestination(
            icon: const Icon(Icons.fact_check_outlined),
            selectedIcon: const Icon(Icons.fact_check_rounded),
            label: s.navAttendance,
          ),
          NavigationDestination(
            icon: const Icon(Icons.currency_rupee_rounded),
            selectedIcon: const Icon(Icons.currency_rupee_rounded),
            label: s.navSalary,
          ),
          NavigationDestination(
            icon: const Icon(Icons.more_horiz_rounded),
            selectedIcon: const Icon(Icons.more_horiz_rounded),
            label: s.navMore,
          ),
        ],
      ),
    );
  }
}
