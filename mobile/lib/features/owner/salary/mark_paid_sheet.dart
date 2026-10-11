import 'package:flutter/material.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';

/// "Have you paid everyone?" — how (cash / UPI / bank / mixed) and on which day.
/// Returns null when cancelled. StaffMint only records it; it doesn't move money.
Future<({String method, String paidOn})?> askHowPaid(BuildContext context, {required int staffCount}) {
  return showModalBottomSheet<({String method, String paidOn})>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _MarkPaidSheet(staffCount: staffCount),
  );
}

class _MarkPaidSheet extends StatefulWidget {
  const _MarkPaidSheet({required this.staffCount});
  final int staffCount;

  @override
  State<_MarkPaidSheet> createState() => _MarkPaidSheetState();
}

class _MarkPaidSheetState extends State<_MarkPaidSheet> {
  String _method = 'cash';
  DateTime _day = Dates.today();

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.paidQuestion, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(s.paidNoMoneyNote, style: const TextStyle(color: AppColors.muted, fontSize: 13.5, height: 1.35)),
          const SizedBox(height: 16),
          Text(s.howDidYouPay, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in const ['cash', 'upi', 'bank', 'mixed'])
                ChoiceChip(
                  key: Key('payMethod_$m'),
                  label: Text(s.paymentMethodLabel(m)),
                  selected: _method == m,
                  onSelected: (_) => setState(() => _method = m),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(s.paidOnLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            key: const Key('paidOnPick'),
            icon: const Icon(Icons.calendar_today_rounded, size: 18),
            label: Text(Dates.pretty(_day, s.languageCode)),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _day,
                firstDate: Dates.today().subtract(const Duration(days: 120)),
                lastDate: Dates.today(),
              );
              if (picked != null) setState(() => _day = picked);
            },
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const Key('confirmPaid'),
              onPressed: () => Navigator.pop(context, (method: _method, paidOn: Dates.toApiDate(_day))),
              child: Text(s.yesAllPaid(widget.staffCount)),
            ),
          ),
        ],
      ),
    );
  }
}
