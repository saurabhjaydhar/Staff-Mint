import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/providers.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/bilingual.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/pickers.dart';
import '../providers/owner_providers.dart';
import 'advances_view.dart';
import 'money_dialogs.dart';
import 'salary_day_view.dart';

/// Salary tab: the guided "Salary day" for a month, plus advances and
/// bonus / deduction as secondary tabs.
class SalaryScreen extends ConsumerStatefulWidget {
  const SalaryScreen({super.key});

  @override
  ConsumerState<SalaryScreen> createState() => _SalaryScreenState();
}

class _SalaryScreenState extends ConsumerState<SalaryScreen> {
  // Salary is usually run for the month that just ended.
  DateTime _month = Dates.addMonths(Dates.firstOfMonth(DateTime.now()), -1);

  String get _monthKey => Dates.toApiMonth(_month);

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              ScreenHeader(subtitle: s.salaryDayBi.joined, title: Dates.monthTitle(_month, s.languageCode)),
              TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: s.salaryDayBi.text),
                  Tab(text: s.advances),
                  Tab(text: s.bonusDeduction),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    Column(
                      children: [
                        MonthSwitcher(month: _month, onChanged: (m) => setState(() => _month = m)),
                        Expanded(child: SalaryDayView(month: _monthKey)),
                      ],
                    ),
                    RefreshableList(
                      onRefresh: () => ref.refresh(advancesProvider(null).future),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: FilledButton.icon(
                            onPressed: () => showAddAdvanceSheet(context, ref),
                            icon: const Icon(Icons.add),
                            label: Text(s.addAdvance),
                          ),
                        ),
                        const AdvancesList(),
                      ],
                    ),
                    Column(
                      children: [
                        MonthSwitcher(month: _month, onChanged: (m) => setState(() => _month = m), allowFuture: true),
                        Expanded(child: _AdjustmentsTab(month: _monthKey)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdjustmentsTab extends ConsumerWidget {
  const _AdjustmentsTab({required this.month});
  final String month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final list = ref.watch(adjustmentsProvider(month));
    return RefreshableList(
      onRefresh: () => ref.refresh(adjustmentsProvider(month).future),
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: () => showAddAdjustmentSheet(context, ref, month: month),
            icon: const Icon(Icons.add),
            label: Text(s.addAdjustment),
          ),
        ),
        list.when(
          loading: () => const LoadingView(),
          error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(adjustmentsProvider(month))),
          data: (items) => items.isEmpty
              ? EmptyView(message: s.noAdjustments, icon: Icons.receipt_long_outlined)
              : Card(
                  child: Column(
                    children: [
                      for (final a in items)
                        ListTile(
                          leading: Icon(
                            a.isBonus ? Icons.add_circle_rounded : Icons.remove_circle_rounded,
                            color: a.isBonus ? AppColors.mint : AppColors.red,
                          ),
                          title: Text(a.employeeName),
                          subtitle: Text(
                            [
                              a.isBonus ? s.bonus : s.deduction,
                              if (a.note != null && a.note!.isNotEmpty) a.note!,
                            ].join(' · '),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${a.isBonus ? '+' : '−'} ${Money.format(a.amountPaise)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: a.isBonus ? AppColors.mint : AppColors.red,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded),
                                tooltip: s.delete,
                                onPressed: () async {
                                  if (!await confirmDialog(
                                    context,
                                    title: s.delete,
                                    message: s.areYouSure,
                                    destructive: true,
                                  )) {
                                    return;
                                  }
                                  if (!context.mounted) return;
                                  if (await runGuarded(
                                    context,
                                    () => ref.read(moneyApiProvider).deleteAdjustment(a.id),
                                  )) {
                                    invalidateMoney(ref);
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}
