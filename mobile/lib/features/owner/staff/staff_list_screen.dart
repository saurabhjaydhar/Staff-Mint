import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/models/models.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/phone.dart';
import '../../../core/widgets/bilingual.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/status_pill.dart';
import '../../auth/auth_controller.dart';
import '../providers/owner_providers.dart';

class StaffListScreen extends ConsumerStatefulWidget {
  const StaffListScreen({super.key});

  @override
  ConsumerState<StaffListScreen> createState() => _StaffListScreenState();
}

class _StaffListScreenState extends ConsumerState<StaffListScreen> {
  String _search = '';
  bool _showInactive = false;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  EmployeeQuery get _query => (search: _search, status: _showInactive ? 'all' : 'active');

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final list = ref.watch(employeesProvider(_query));
    final today = ref.watch(dayAttendanceProvider(Dates.toApiDate(DateTime.now()))).value ?? const <DayRow>[];
    final todayStatus = {for (final r in today) r.employee.id: r.displayStatus};
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            ScreenHeader(
              subtitle: ref.watch(authControllerProvider.select((v) => v.company?.name)) ?? s.appName,
              title: s.staffTitle,
              actions: [
                IconButton.filled(
                  key: const Key('addStaff'),
                  tooltip: s.addStaff,
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  onPressed: () => context.push(Routes.ownerStaffAdd),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: s.searchStaff),
                onChanged: (v) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 350), () => setState(() => _search = v.trim()));
                },
              ),
            ),
            SwitchListTile(
              dense: true,
              value: _showInactive,
              title: Text(s.showInactive, style: const TextStyle(color: AppColors.muted)),
              onChanged: (v) => setState(() => _showInactive = v),
            ),
            Expanded(
              child: AsyncBody<List<Employee>>(
                value: list,
                onRetry: () => ref.invalidate(employeesProvider(_query)),
                data: (emps) => RefreshableList(
                  onRefresh: () => ref.refresh(employeesProvider(_query).future),
                  children: [
                    if (emps.isEmpty)
                      EmptyView(
                        message: s.noStaffYet,
                        icon: Icons.people_outline,
                        action: FilledButton.icon(
                          onPressed: () => context.push(Routes.ownerStaffAdd),
                          icon: const Icon(Icons.person_add_alt_1_rounded),
                          label: Text(s.addStaff),
                        ),
                      ),
                    if (emps.isNotEmpty)
                      Card(
                        child: Column(
                          children: [
                            for (var i = 0; i < emps.length; i++) ...[
                              if (i > 0) const Divider(indent: 72),
                              _StaffTile(employee: emps[i], status: todayStatus[emps[i].id]),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StaffTile extends StatelessWidget {
  const _StaffTile({required this.employee, required this.status});
  final Employee employee;
  final String? status;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final e = employee;
    return ListTile(
      leading: InitialsAvatar(e.name),
      title: Text(e.name, style: TextStyle(color: e.isActive ? null : AppColors.muted)),
      subtitle: Text(
        [
          if (e.designation != null && e.designation!.isNotEmpty) e.designation!,
          if (e.ratePaise > 0) e.isDaily ? s.perDay(Money.format(e.ratePaise)) : s.perMonth(Money.format(e.ratePaise)),
          if (!e.isActive) s.inactive,
        ].join(' · ').ifEmpty(Phones.display(e.phone)),
      ),
      trailing: e.isActive && status != null ? StatusPill(status: status) : const Icon(Icons.chevron_right_rounded),
      onTap: () => context.push(Routes.ownerStaffProfile(e.id)),
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
