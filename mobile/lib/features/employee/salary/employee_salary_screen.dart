import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/bilingual.dart';
import '../../../core/widgets/common.dart';
import '../../owner/salary/payslip_receipt.dart';
import '../employee_providers.dart';

/// My salary: this month's running estimate as a receipt, advance balance,
/// and past payslips (each opens as a stamped receipt with WhatsApp / PDF).
class EmployeeSalaryScreen extends ConsumerWidget {
  const EmployeeSalaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final salary = ref.watch(mySalaryProvider);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(subtitle: s.navSalaryBi.joined, title: s.mySalary),
            Expanded(
              child: AsyncBody<SalaryOverview>(
                value: salary,
                onRetry: () => ref.invalidate(mySalaryProvider),
                data: (o) => RefreshableList(
                  onRefresh: () => ref.refresh(mySalaryProvider.future),
                  padding: const EdgeInsets.only(bottom: 32),
                  children: [
                    if (o.estimate != null) ...[
                      SectionHeader(s.runningEstimate),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: PayslipReceipt(payslip: o.estimate!),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Text(s.estimateNote, style: const TextStyle(color: AppColors.muted, fontSize: 14)),
                      ),
                    ],
                    SectionHeader(s.advanceBalance),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.account_balance_wallet_rounded),
                        title: Text(
                          Money.format(o.advanceBalancePaise),
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: o.advanceBalancePaise > 0 ? AppColors.red : AppColors.ink,
                          ),
                        ),
                      ),
                    ),
                    SectionHeader(s.payslips),
                    if (o.payslips.isEmpty)
                      EmptyView(message: s.noPayslips, icon: Icons.receipt_long_outlined)
                    else
                      Card(
                        child: Column(
                          children: [
                            for (final p in o.payslips)
                              PayslipTile(
                                payslip: p,
                                title: Dates.monthTitle(Dates.parseMonth(p.month), s.languageCode),
                                onTap: () => openPayslipDetail(context, p, stamp: payslipStamp(s, p)),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
