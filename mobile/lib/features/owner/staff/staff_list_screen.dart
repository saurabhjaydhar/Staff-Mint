import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/providers.dart';
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
  bool _showLeft = false;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  EmployeeQuery get _query => (search: _search, status: 'all');

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final list = ref.watch(employeesProvider(_query));
    final all = list.value ?? const <Employee>[];
    final today = ref.watch(dayAttendanceProvider(Dates.toApiDate(DateTime.now()))).value ?? const <DayRow>[];
    final todayStatus = {for (final r in today) r.employee.id: r.displayStatus};
    final isOwner = ref.watch(authControllerProvider.select((v) => v.isOwner));
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            ScreenHeader(
              subtitle: list.hasValue
                  ? s.staffCountLine(
                      list.requireValue.where((e) => e.isActive).length,
                      list.requireValue.where((e) => e.isActive && e.isManager).length,
                    )
                  : (ref.watch(authControllerProvider.select((v) => v.company?.name)) ?? s.appName),
              title: s.staffTitle,
              actions: [
                FilledButton.icon(
                  key: const Key('addStaff'),
                  style: FilledButton.styleFrom(minimumSize: const Size(48, 44)),
                  icon: const Icon(Icons.add_rounded),
                  label: Text(s.add),
                  onPressed: () => context.push(Routes.ownerStaffAdd),
                ),
                const SizedBox(width: 8),
              ],
            ),
            Card(
              margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: ListTile(
                key: const Key('rosterTile'),
                leading: const Icon(Icons.calendar_view_week_rounded, color: AppColors.mintDark),
                title: Text(s.rosterTitle, style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text(s.rosterCardHint),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(Routes.ownerRoster),
              ),
            ),
            if (isOwner)
              Card(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: ListTile(
                  key: const Key('teamAccessTile'),
                  leading: const Icon(Icons.key_rounded, color: AppColors.mintDark),
                  title: Text(s.teamAccess, style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(s.teamAccessHint),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(Routes.ownerTeam),
                ),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Row(
                children: [
                  for (final (left, label) in [
                    (false, s.workingN(all.where((e) => e.isActive).length)),
                    (true, s.leftN(all.where((e) => !e.isActive).length)),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        key: Key(left ? 'filterLeft' : 'filterWorking'),
                        label: Text(label),
                        selected: _showLeft == left,
                        onSelected: (_) => setState(() => _showLeft = left),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: AsyncBody<List<Employee>>(
                value: list,
                onRetry: () => ref.invalidate(employeesProvider(_query)),
                data: (everyone) {
                  final emps = everyone.where((e) => e.isActive != _showLeft).toList();
                  return RefreshableList(
                    onRefresh: () => ref.refresh(employeesProvider(_query).future),
                    children: [
                      if (emps.isEmpty && _showLeft)
                        EmptyView(message: s.noneLeft, icon: Icons.people_outline)
                      else if (emps.isEmpty)
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
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StaffTile extends ConsumerWidget {
  const _StaffTile({required this.employee, required this.status});
  final Employee employee;
  final String? status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final e = employee;
    final notJoined = e.isActive && !e.linked;
    return ListTile(
      key: Key('staffTile_${e.id}'),
      leading: InitialsAvatar(e.name),
      title: Row(
        children: [
          Flexible(
            child: Text(
              e.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: e.isActive ? null : AppColors.muted),
            ),
          ),
          if (e.isManager) ...[
            const SizedBox(width: 6),
            Container(
              key: Key('managerBadge_${e.id}'),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: AppColors.indigoLight, borderRadius: BorderRadius.circular(6)),
              child: Text(
                s.managerBadge,
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: AppColors.indigo),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        notJoined
            ? s.invitedNotJoined
            : [
                if (e.designation != null && e.designation!.isNotEmpty) e.designation!,
                if (e.ratePaise > 0)
                  e.isDaily ? s.perDay(Money.format(e.ratePaise)) : s.perMonth(Money.format(e.ratePaise)),
                if (!e.isActive) s.inactive,
              ].join(' · ').ifEmpty(Phones.display(e.phone)),
      ),
      trailing: notJoined
          ? TextButton(
              key: Key('remind_${e.id}'),
              onPressed: () =>
                  runGuarded(context, () => ref.read(accountsApiProvider).invite(e.id), success: s.inviteSent),
              child: Text(s.remind),
            )
          : e.isActive && status != null
          ? StatusPill(status: status)
          : const Icon(Icons.chevron_right_rounded),
      onTap: () => context.push(Routes.ownerStaffProfile(e.id)),
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
