import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/providers.dart';
import '../../../core/api/services/payroll_api.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/slide_to_confirm.dart';
import '../../../core/widgets/step_bar.dart';
import '../../../core/widgets/success_screen.dart';
import '../providers/owner_providers.dart';
import 'money_dialogs.dart';
import 'payslip_receipt.dart';

/// "Salary day": review only the flagged staff, then one slide approves and
/// sends every payslip; the next slide marks the month as paid.
class SalaryDayView extends ConsumerStatefulWidget {
  const SalaryDayView({super.key, required this.month});
  final String month;

  @override
  ConsumerState<SalaryDayView> createState() => _SalaryDayViewState();
}

class _SalaryDayViewState extends ConsumerState<SalaryDayView> {
  /// Run returned by the last action (has payslips), keyed by month.
  final Map<String, PayrollRun> _detail = {};
  final Set<String> _detailRequested = {};

  /// Flagged staff the owner marked "looks right", as `runId:employeeId`.
  final Set<String> _ok = {};
  bool _othersOpen = false;
  bool _busy = false;

  PayrollApi get _api => ref.read(payrollApiProvider);

  Future<PayrollRun?> _act(Future<PayrollRun> Function() action) async {
    setState(() => _busy = true);
    try {
      final run = await action();
      if (!mounted) return run;
      setState(() => _detail[widget.month] = run);
      ref.invalidate(payrollRunsProvider(widget.month));
      return run;
    } catch (e) {
      if (mounted) showError(context, e);
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadDetail(PayrollRun run) async {
    if (!_detailRequested.add('${run.id}:${run.status}')) return;
    try {
      final full = await _api.get(run.id);
      if (mounted) setState(() => _detail[widget.month] = full);
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  Future<void> _approveAndSend(PayrollRun r) async {
    final s = context.s;
    final approved = await _act(() => _api.approve(r.id));
    if (approved == null || !mounted) return;
    var queued = 0;
    String? note;
    setState(() => _busy = true);
    try {
      queued = await _api.sendPayslips(r.id);
    } catch (e) {
      if (mounted) note = errorMessage(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    final bi = s.salaryApprovedBi;
    await showSuccessScreen(
      context,
      title: bi.text,
      subtitle: [?bi.hint, s.payslipsSentTo(queued)].join(' · '),
      rows: [(s.navStaff, '${approved.employees}'), (s.totalNet, Money.format(approved.netPaise))],
      note: note,
    );
  }

  Future<void> _markPaid(PayrollRun r) async {
    final s = context.s;
    final paid = await _act(() => _api.markPaid(r.id));
    if (paid == null || !mounted) return;
    final bi = s.salaryPaidBi;
    await showSuccessScreen(
      context,
      title: bi.text,
      subtitle: bi.hint,
      rows: [(s.navStaff, '${paid.employees}'), (s.totalNet, Money.format(paid.netPaise))],
    );
  }

  Future<void> _sendAgain(PayrollRun r) async {
    setState(() => _busy = true);
    try {
      final n = await _api.sendPayslips(r.id);
      if (mounted) showSnack(context, context.s.payslipsQueued(n));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(PayrollRun r, Payslip p) => openPayslipDetail(
    context,
    p,
    ownerView: true,
    stamp: payslipStamp(context.s, p, run: r),
    anomalies: r.anomaliesFor(p.employeeId),
    onEdit: r.isDraft
        ? () async {
            final nav = Navigator.of(context);
            final added = await showAddAdjustmentSheet(
              context,
              ref,
              month: widget.month,
              employee: Employee(id: p.employeeId, name: p.employeeName, phone: ''),
            );
            if (!added || !mounted) return;
            nav.pop();
            await _act(() => _api.prepare(widget.month));
          }
        : null,
  );

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final runs = ref.watch(payrollRunsProvider(widget.month));
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
          final r = run;
          WidgetsBinding.instance.addPostFrameCallback((_) => _loadDetail(r));
        }
        final r = run;
        return Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  _detail.remove(widget.month);
                  _detailRequested.clear();
                  ref.invalidate(payrollRunsProvider(widget.month));
                  await ref.read(payrollRunsProvider(widget.month).future);
                },
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 24),
                  children: r == null ? _empty(s) : _run(s, r),
                ),
              ),
            ),
            if (r != null && !r.isPaid)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                  child: SlideToConfirm(
                    key: const Key('salarySlider'),
                    label: r.isDraft ? s.slideApproveSend : s.slideMarkPaid,
                    busy: _busy,
                    enabled: r.isDraft || r.isApproved,
                    onConfirmed: () => r.isDraft ? _approveAndSend(r) : _markPaid(r),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  List<Widget> _empty(S s) => [
    EmptyView(message: s.noRunYet, icon: Icons.calculate_outlined),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: FilledButton.icon(
        key: const Key('prepareSalary'),
        onPressed: _busy ? null : () => _act(() => _api.prepare(widget.month)),
        icon: const Icon(Icons.calculate_rounded),
        label: Text(s.prepareSalary),
      ),
    ),
  ];

  List<Widget> _run(S s, PayrollRun r) {
    final slips = r.payslips;
    final flagged = <Payslip>[];
    final fine = <Payslip>[];
    for (final p in slips ?? const <Payslip>[]) {
      final needsLook = r.anomaliesFor(p.employeeId).isNotEmpty && !_ok.contains('${r.id}:${p.employeeId}');
      (needsLook ? flagged : fine).add(p);
    }
    final reviewed = slips != null && flagged.isEmpty;
    final step = r.isPaid
        ? 3
        : r.isApproved
        ? 2
        : (reviewed ? 1 : 0);
    final advance = (slips ?? const <Payslip>[])
        .expand((p) => p.lines)
        .where((l) => l.code == 'advance')
        .fold<int>(0, (sum, l) => sum + l.amountPaise.abs());
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: StepBar(steps: [s.stepReview, s.stepSend, s.stepPaid], current: step),
      ),
      _CashHero(run: r, advancePaise: advance),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (r.revision > 1)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(s.revisionLabel(r.revision), style: const TextStyle(color: AppColors.muted)),
              ),
            if (r.isDraft)
              TextButton.icon(
                onPressed: _busy ? null : () => _act(() => _api.prepare(widget.month)),
                icon: const Icon(Icons.refresh_rounded),
                label: Text(s.recalculate),
              )
            else
              TextButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        if (await confirmDialog(context, title: s.revise, message: s.reviseConfirm)) {
                          await _act(() => _api.revise(r.id));
                        }
                      },
                icon: const Icon(Icons.edit_note_rounded),
                label: Text(s.revise),
              ),
          ],
        ),
      ),
      if (_busy) const LinearProgressIndicator(minHeight: 2),
      if (r.isPaid)
        Container(
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.mintLight, borderRadius: AppTheme.radius),
          child: Row(
            children: [
              const Icon(Icons.verified_rounded, color: AppColors.mint),
              const SizedBox(width: 8),
              Expanded(
                child: Text(s.paidBanner, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              TextButton(onPressed: _busy ? null : () => _sendAgain(r), child: Text(s.sendAgain)),
            ],
          ),
        ),
      if (slips == null)
        const LoadingView(rows: 3)
      else ...[
        for (final p in flagged)
          _FlagCard(
            payslip: p,
            anomalies: r.anomaliesFor(p.employeeId),
            onOk: () => setState(() => _ok.add('${r.id}:${p.employeeId}')),
            onChange: () => _open(r, p),
          ),
        if (fine.isNotEmpty) ...[
          InkWell(
            key: const Key('othersFine'),
            onTap: () => setState(() => _othersOpen = !_othersOpen),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
              child: Row(
                children: [
                  const Icon(Icons.check_rounded, color: AppColors.mint, size: 20),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      (flagged.isEmpty && fine.length == slips.length
                              ? s.allFine(fine.length)
                              : s.othersFine(fine.length))
                          .joined,
                      style: const TextStyle(color: AppColors.mint, fontWeight: FontWeight.w700, fontSize: 14.5),
                    ),
                  ),
                  Icon(_othersOpen ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: AppColors.mint),
                ],
              ),
            ),
          ),
          if (_othersOpen)
            Card(
              child: Column(
                children: [for (final p in fine) PayslipTile(payslip: p, onTap: () => _open(r, p))],
              ),
            ),
        ],
      ],
    ];
  }
}

class _CashHero extends StatelessWidget {
  const _CashHero({required this.run, required this.advancePaise});
  final PayrollRun run;
  final int advancePaise;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final style = TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13);
    return Container(
      key: const Key('cashHero'),
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.cashNeeded.joined, style: style),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              Money.format(run.netPaise),
              style: const TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.w800, height: 1.05),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              Text(s.employeesCount(run.employees), style: style),
              Text(s.earnedAmount(Money.format(run.grossPaise)), style: style),
              if (advancePaise > 0) Text(s.advanceRecovered(Money.format(advancePaise)), style: style),
            ],
          ),
        ],
      ),
    );
  }
}

class _FlagCard extends StatelessWidget {
  const _FlagCard({required this.payslip, required this.anomalies, required this.onOk, required this.onChange});
  final Payslip payslip;
  final List<PayrollAnomaly> anomalies;
  final VoidCallback onOk;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Container(
      key: Key('flag_${payslip.employeeId}'),
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppTheme.radius,
        border: Border.all(color: AppColors.amberBorder, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.warning_amber_rounded, color: AppColors.amber, size: 20),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${payslip.employeeName}: ${anomalies.first.message}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
              Text(Money.format(payslip.netPaise), style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [...anomalies.skip(1).map((a) => a.message), s.isThatRight].join(' · '),
            style: const TextStyle(fontSize: 13.5, color: AppColors.muted, height: 1.35),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: Key('flagOk_${payslip.employeeId}'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: onOk,
                icon: const Icon(Icons.check_rounded, size: 18),
                label: Text(s.looksRight),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: onChange,
                icon: const Icon(Icons.edit_rounded, size: 18),
                label: Text(s.change),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
