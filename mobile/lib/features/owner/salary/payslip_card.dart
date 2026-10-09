import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/providers.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';

/// Expandable payslip with every line and its plain-language explanation.
/// Shared by owner (payroll preview) and employee (my salary).
class PayslipCard extends ConsumerWidget {
  const PayslipCard({
    super.key,
    required this.payslip,
    this.anomalies = const [],
    this.allowExplain = false,
    this.title,
    this.initiallyExpanded = false,
  });

  final Payslip payslip;
  final List<PayrollAnomaly> anomalies;
  final bool allowExplain;
  final String? title;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final p = payslip;
    final hasAnomaly = anomalies.isNotEmpty;
    return Card(
      shape: hasAnomaly
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: AppColors.late, width: 2),
            )
          : null,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        leading: hasAnomaly
            ? const Icon(Icons.warning_amber_rounded, color: AppColors.late)
            : InitialsAvatar(p.employeeName, radius: 18),
        title: Text(title ?? p.employeeName, style: Theme.of(context).textTheme.titleMedium),
        // Daily-wage staff have no divisor (the API sends 1); show only the day count.
        subtitle: Text(p.wageType == 'daily' ? s.payableDaysOnly(p.payableDays) : s.payableDays(p.payableDays, p.divisor)),
        trailing: Text(Money.format(p.netPaise), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final a in anomalies)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '⚠ ${a.message}',
                style: const TextStyle(color: AppColors.halfDay, fontWeight: FontWeight.w600),
              ),
            ),
          Text(
            s.daysSummary(p.summary.present, p.summary.halfDay, p.summary.absent, p.summary.paidLeave),
            style: const TextStyle(color: Colors.black54),
          ),
          const Divider(height: 20),
          for (final l in p.lines) _LineRow(line: l),
          const Divider(height: 20),
          _TotalRow(label: s.gross, value: Money.format(p.grossPaise)),
          _TotalRow(label: s.deductions, value: '-${Money.format(p.deductionsPaise)}'),
          _TotalRow(label: s.net, value: Money.format(p.netPaise), bold: true),
          if (p.isPersisted) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              alignment: WrapAlignment.end,
              children: [
                if (allowExplain)
                  TextButton.icon(
                    icon: const Icon(Icons.help_outline_rounded),
                    label: Text(s.whySalary),
                    onPressed: () => showPayslipExplanation(context, ref, p.id),
                  ),
                if (p.status != 'draft')
                  TextButton.icon(
                    icon: const Icon(Icons.picture_as_pdf_rounded),
                    label: Text(s.openPdf),
                    onPressed: () => openPayslipPdf(context, ref, p),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.line});
  final PayslipLine line;

  @override
  Widget build(BuildContext context) {
    final color = line.isDeduction ? AppColors.absent : Colors.black87;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(line.label, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              Text(
                '${line.isDeduction ? '-' : ''}${Money.format(line.amountPaise.abs())}',
                style: TextStyle(fontWeight: FontWeight.w700, color: color),
              ),
            ],
          ),
          if (line.explanation.isNotEmpty)
            Text(line.explanation, style: const TextStyle(color: Colors.black54, fontSize: 14)),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.label, required this.value, this.bold = false});
  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500, fontSize: bold ? 18 : 16);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}

/// `GET /payslips/:id` returns a fresh short-lived signed `pdfUrl`.
Future<void> openPayslipPdf(BuildContext context, WidgetRef ref, Payslip p) async {
  try {
    final fresh = await ref.read(payrollApiProvider).payslip(p.id);
    final url = fresh.pdfUrl ?? p.pdfUrl;
    if (!context.mounted) return;
    if (url == null) {
      showSnack(context, context.s.couldNotOpen, error: true);
      return;
    }
    await openUrl(context, url);
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

Future<void> showPayslipExplanation(BuildContext context, WidgetRef ref, String payslipId) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => FutureBuilder<PayslipExplanation>(
      future: ref.read(payrollApiProvider).explain(payslipId),
      builder: (ctx, snap) {
        final s = ctx.s;
        if (snap.hasError) return SizedBox(height: 240, child: ErrorView(error: snap.error!));
        if (!snap.hasData) return const SizedBox(height: 240, child: LoadingView());
        final e = snap.data!;
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text(s.whySalary, style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 12),
            Text(e.text, style: Theme.of(ctx).textTheme.bodyLarge),
            const SizedBox(height: 12),
            for (final l in e.lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('•  ', style: TextStyle(fontSize: 18)),
                    Expanded(child: Text(l, style: Theme.of(ctx).textTheme.bodyLarge)),
                  ],
                ),
              ),
          ],
        );
      },
    ),
  );
}
