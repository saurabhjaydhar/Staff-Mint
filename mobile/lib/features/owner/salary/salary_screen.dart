import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/providers.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/pickers.dart';
import '../providers/owner_providers.dart';
import 'advances_view.dart';
import 'money_dialogs.dart';
import 'payslip_card.dart';

/// Month → preview (anomalies) → approve → send payslips → mark paid;
/// plus advances and bonus/deduction tabs.
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
        appBar: AppBar(
          title: Text(s.salaryTitle),
          bottom: TabBar(
            tabs: [
              Tab(text: s.payslips),
              Tab(text: s.advances),
              Tab(text: s.bonusDeduction),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            Column(
              children: [
                MonthSwitcher(month: _month, onChanged: (m) => setState(() => _month = m)),
                Expanded(child: _PayrollTab(month: _monthKey)),
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
    );
  }
}

class _PayrollTab extends ConsumerStatefulWidget {
  const _PayrollTab({required this.month});
  final String month;

  @override
  ConsumerState<_PayrollTab> createState() => _PayrollTabState();
}

class _PayrollTabState extends ConsumerState<_PayrollTab> {
  /// Run returned by the last action (has payslips), keyed by month.
  final Map<String, PayrollRun> _detail = {};
  final Set<String> _detailRequested = {};
  bool _busy = false;

  Future<void> _act(Future<PayrollRun> Function() action, {String? success}) async {
    setState(() => _busy = true);
    try {
      final run = await action();
      if (!mounted) return;
      setState(() => _detail[widget.month] = run);
      ref.invalidate(payrollRunsProvider(widget.month));
      if (success != null) showSnack(context, success);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadDetail(PayrollRun run) async {
    if (_detail[widget.month]?.id == run.id && _detail[widget.month]?.payslips != null) return;
    if (!_detailRequested.add('${run.id}:${run.status}')) return;
    try {
      final full = await ref.read(payrollApiProvider).get(run.id);
      if (mounted) setState(() => _detail[widget.month] = full);
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final runs = ref.watch(payrollRunsProvider(widget.month));
    final api = ref.read(payrollApiProvider);
    return AsyncBody<List<PayrollRun>>(
      value: runs,
      onRetry: () => ref.invalidate(payrollRunsProvider(widget.month)),
      data: (list) {
        final current = list.where((r) => r.status != 'superseded').toList()
          ..sort((a, b) => b.revision.compareTo(a.revision));
        var run = current.firstOrNull;
        final detail = _detail[widget.month];
        if (detail != null && (run == null || detail.id == run.id || detail.revision >= run.revision)) {
          run = detail;
        }
        if (run != null && run.payslips == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _loadDetail(run!));
        }
        final r = run;
        return RefreshableList(
          onRefresh: () async {
            _detail.remove(widget.month);
            _detailRequested.clear();
            ref.invalidate(payrollRunsProvider(widget.month));
            await ref.read(payrollRunsProvider(widget.month).future);
          },
          children: [
            if (r == null) ...[
              EmptyView(message: s.noRunYet, icon: Icons.calculate_outlined),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: FilledButton.icon(
                  onPressed: _busy ? null : () => _act(() => api.prepare(widget.month)),
                  icon: const Icon(Icons.calculate_rounded),
                  label: Text(s.prepareSalary),
                ),
              ),
            ] else ...[
              _RunSummary(run: r),
              if (r.anomalies.isNotEmpty) _Anomalies(run: r),
              _RunActions(
                run: r,
                busy: _busy,
                onRecalculate: () => _act(() => api.prepare(widget.month)),
                onApprove: () async {
                  if (await confirmDialog(context, title: s.approveSalary, message: s.approveSalaryConfirm)) {
                    await _act(() => api.approve(r.id), success: s.approved);
                  }
                },
                onSend: () async {
                  setState(() => _busy = true);
                  try {
                    final n = await api.sendPayslips(r.id);
                    if (context.mounted) showSnack(context, s.payslipsQueued(n));
                  } catch (e) {
                    if (context.mounted) showError(context, e);
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
                onMarkPaid: () async {
                  if (await confirmDialog(context, title: s.markPaid, message: s.markPaidConfirm)) {
                    await _act(() => api.markPaid(r.id), success: s.saved);
                  }
                },
                onRevise: () async {
                  if (await confirmDialog(context, title: s.revise, message: s.reviseConfirm)) {
                    await _act(() => api.revise(r.id));
                  }
                },
              ),
              if (r.payslips == null && !_detailRequested.contains('${r.id}:${r.status}'))
                const LoadingView()
              else if (r.payslips == null)
                const SizedBox.shrink()
              else
                for (final p in r.payslips!)
                  PayslipCard(payslip: p, anomalies: r.anomaliesFor(p.employeeId), allowExplain: true),
            ],
          ],
        );
      },
    );
  }
}

class _RunSummary extends StatelessWidget {
  const _RunSummary({required this.run});
  final PayrollRun run;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final color = run.isPaid
        ? AppColors.mint
        : run.isApproved
        ? AppColors.holiday
        : AppColors.late;
    return Card(
      color: AppColors.mintLight,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    s.runStatus(run.status),
                    style: TextStyle(fontWeight: FontWeight.w700, color: Color.lerp(color, Colors.black, 0.3)),
                  ),
                ),
                const Spacer(),
                if (run.revision > 1) Text(s.revisionLabel(run.revision)),
              ],
            ),
            const SizedBox(height: 12),
            Text(s.totalNet, style: Theme.of(context).textTheme.bodyMedium),
            Text(Money.format(run.netPaise), style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                Text('${s.gross}: ${Money.format(run.grossPaise)}'),
                Text('${s.deductions}: ${Money.format(run.deductionsPaise)}'),
                Text(s.employeesCount(run.employees)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Anomalies extends StatelessWidget {
  const _Anomalies({required this.run});
  final PayrollRun run;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Card(
      color: const Color(0xFFFFF7E6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: AppColors.late),
                const SizedBox(width: 8),
                Text('${s.anomalies} (${run.anomalies.length})', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            for (final a in run.anomalies)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text('• ${a.employeeName}: ${a.message}'),
              ),
          ],
        ),
      ),
    );
  }
}

class _RunActions extends StatelessWidget {
  const _RunActions({
    required this.run,
    required this.busy,
    required this.onRecalculate,
    required this.onApprove,
    required this.onSend,
    required this.onMarkPaid,
    required this.onRevise,
  });
  final PayrollRun run;
  final bool busy;
  final VoidCallback onRecalculate;
  final VoidCallback onApprove;
  final VoidCallback onSend;
  final VoidCallback onMarkPaid;
  final VoidCallback onRevise;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final children = <Widget>[];
    if (run.isDraft) {
      children.addAll([
        Expanded(
          child: OutlinedButton(onPressed: busy ? null : onRecalculate, child: Text(s.recalculate)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton(onPressed: busy ? null : onApprove, child: Text(s.approve)),
        ),
      ]);
    } else if (run.isApproved) {
      children.addAll([
        Expanded(
          child: OutlinedButton.icon(
            onPressed: busy ? null : onSend,
            icon: const Icon(Icons.send_rounded),
            label: Text(s.sendPayslips),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton(onPressed: busy ? null : onMarkPaid, child: Text(s.markPaid)),
        ),
      ]);
    } else if (run.isPaid) {
      children.add(
        Expanded(
          child: OutlinedButton.icon(
            onPressed: busy ? null : onSend,
            icon: const Icon(Icons.send_rounded),
            label: Text(s.sendPayslips),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        children: [
          if (busy) const LinearProgressIndicator(),
          if (children.isNotEmpty) Row(children: children),
          if (!run.isDraft)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: busy ? null : onRevise,
                icon: const Icon(Icons.edit_note_rounded),
                label: Text(s.revise),
              ),
            ),
        ],
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
              : Column(
                  children: [
                    for (final a in items)
                      Card(
                        child: ListTile(
                          leading: Icon(
                            a.isBonus ? Icons.add_circle_rounded : Icons.remove_circle_rounded,
                            color: a.isBonus ? AppColors.mint : AppColors.absent,
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
                                (a.isBonus ? '+' : '-') + Money.format(a.amountPaise),
                                style: const TextStyle(fontWeight: FontWeight.w700),
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
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
