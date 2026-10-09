import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/providers.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/pickers.dart';

/// Download attendance / salary / advances / late reports as PDF or Excel.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  DateTime _month = Dates.firstOfMonth(DateTime.now());
  String? _loading;

  Future<void> _open(String kind, String format) async {
    setState(() => _loading = '$kind-$format');
    try {
      final url = await ref
          .read(reportsApiProvider)
          .reportUrl(kind: kind, month: Dates.toApiMonth(_month), format: format);
      if (mounted) await openUrl(context, url);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final reports = [
      ('attendance', s.reportAttendance, Icons.fact_check_rounded),
      ('salary', s.reportSalary, Icons.currency_rupee_rounded),
      ('advances', s.reportAdvances, Icons.payments_rounded),
      ('late', s.reportLate, Icons.timer_off_rounded),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(s.reports)),
      body: ListView(
        children: [
          MonthSwitcher(month: _month, onChanged: (m) => setState(() => _month = m)),
          for (final (kind, label, icon) in reports)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(color: AppColors.mintLight, borderRadius: BorderRadius.circular(12)),
                      child: Icon(icon, color: AppColors.mintDark),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(label, style: Theme.of(context).textTheme.titleMedium)),
                    for (final (fmt, fmtLabel) in [('pdf', s.downloadPdf), ('xlsx', s.downloadExcel)])
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(minimumSize: const Size(64, 48)),
                          onPressed: _loading != null ? null : () => _open(kind, fmt),
                          child: _loading == '$kind-$fmt'
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : Text(fmtLabel),
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
