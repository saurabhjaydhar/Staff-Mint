import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/providers.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../providers/owner_providers.dart';

/// Advances list (all staff, or one employee when [employeeId] is set).
/// Rendered as a column so it can live inside other scroll views.
class AdvancesList extends ConsumerWidget {
  const AdvancesList({super.key, this.employeeId, this.compact = false});
  final String? employeeId;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final list = ref.watch(advancesProvider(employeeId));
    return list.when(
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(advancesProvider(employeeId))),
      data: (items) {
        if (items.isEmpty) {
          return compact ? const SizedBox.shrink() : EmptyView(message: s.noAdvances, icon: Icons.payments_outlined);
        }
        return Column(
          children: [for (final a in items) _AdvanceTile(advance: a, showName: employeeId == null)],
        );
      },
    );
  }
}

class _AdvanceTile extends ConsumerWidget {
  const _AdvanceTile({required this.advance, required this.showName});
  final Advance advance;
  final bool showName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final a = advance;
    final month = Dates.toApiMonth(DateTime.now());
    final skippedThisMonth = a.skipMonths.contains(month);
    final progress = a.amountPaise == 0 ? 0.0 : (a.repaidPaise / a.amountPaise).clamp(0.0, 1.0);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    showName ? a.employeeName : Dates.prettyApiDate(a.date, s.languageCode),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(Money.format(a.amountPaise), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              [
                if (showName) Dates.prettyApiDate(a.date, s.languageCode),
                a.mode == 'installments'
                    ? s.installmentInfo(Money.format(a.installmentPaise), a.installments)
                    : s.modeFullNext,
                a.isActive ? s.activeLabel : s.closedLabel,
              ].join(' · '),
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: progress, minHeight: 6, borderRadius: BorderRadius.circular(3)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(child: Text(s.repaidOf(Money.format(a.repaidPaise), Money.format(a.amountPaise)))),
                Text(
                  '${s.balance}: ${Money.format(a.balancePaise)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: a.balancePaise > 0 ? AppColors.halfDay : AppColors.mint,
                  ),
                ),
              ],
            ),
            if (a.note != null && a.note!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                a.note!,
                style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.black54),
              ),
            ],
            if (a.isActive)
              Align(
                alignment: Alignment.centerRight,
                child: skippedThisMonth
                    ? Padding(padding: const EdgeInsets.only(top: 8), child: Text(s.skipped))
                    : TextButton(
                        onPressed: () async {
                          if (await runGuarded(
                            context,
                            () => ref.read(moneyApiProvider).skipMonth(a.id, month),
                            success: s.skipped,
                          )) {
                            invalidateMoney(ref);
                          }
                        },
                        child: Text(s.skipNextMonth),
                      ),
              ),
          ],
        ),
      ),
    );
  }
}
