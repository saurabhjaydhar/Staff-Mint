import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/providers.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/dates.dart';
import '../../core/widgets/common.dart';

final pastPayslipsProvider = FutureProvider.autoDispose<List<PastPayslipGroup>>(
  (ref) => ref.watch(accountsApiProvider).pastPayslips(),
);

/// Own payslips from businesses this person no longer works at (12 months).
class PastPayslipsScreen extends ConsumerWidget {
  const PastPayslipsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final groups = ref.watch(pastPayslipsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(s.pastPayslipsBi.text)),
      body: groups.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(pastPayslipsProvider)),
        data: (list) => list.isEmpty
            ? Center(
                child: Text(s.noPayslips, style: const TextStyle(color: AppColors.muted)),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  for (final g in list) ...[
                    SectionHeader(g.companyName),
                    Card(
                      child: Column(
                        children: [
                          for (final p in g.payslips)
                            ListTile(
                              key: Key('pastPayslip-${p.id}'),
                              leading: const Icon(Icons.receipt_long_rounded, color: AppColors.mintDark),
                              title: Text(Dates.monthTitle(Dates.parseMonth(p.month), s.languageCode)),
                              subtitle: Text(s.money(p.netPaise)),
                              trailing: p.pdfUrl == null ? null : const Icon(Icons.picture_as_pdf_rounded),
                              onTap: p.pdfUrl == null ? null : () => openUrl(context, p.pdfUrl!),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
