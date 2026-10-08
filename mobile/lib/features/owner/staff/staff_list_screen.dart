import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/models/models.dart';
import '../../../core/router/routes.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/phone.dart';
import '../../../core/widgets/common.dart';
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
    return Scaffold(
      appBar: AppBar(
        title: Text(s.staffTitle),
        actions: [
          IconButton(
            tooltip: s.addStaff,
            icon: const Icon(Icons.person_add_alt_1_rounded),
            onPressed: () => context.push(Routes.ownerStaffAdd),
          ),
        ],
      ),
      body: Column(
        children: [
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
            title: Text(s.showInactive),
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
                  for (final e in emps)
                    Card(
                      child: ListTile(
                        leading: InitialsAvatar(e.name),
                        title: Text(e.name, style: TextStyle(color: e.isActive ? null : Colors.grey)),
                        subtitle: Text(
                          [
                            if (e.designation != null && e.designation!.isNotEmpty) e.designation!,
                            Phones.display(e.phone),
                          ].join(' · '),
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (e.ratePaise > 0)
                              Text(Money.format(e.ratePaise), style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text(
                              e.isActive ? (e.isDaily ? s.wageDaily : s.wageMonthly) : s.inactive,
                              style: const TextStyle(fontSize: 12, color: Colors.black54),
                            ),
                          ],
                        ),
                        onTap: () => context.push(Routes.ownerStaffProfile(e.id)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
