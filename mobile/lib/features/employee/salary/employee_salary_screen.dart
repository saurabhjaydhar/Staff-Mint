import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/models/models.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../../owner/salary/payslip_card.dart';
import '../employee_providers.dart';

class EmployeeSalaryScreen extends ConsumerWidget {
  const EmployeeSalaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final salary = ref.watch(mySalaryProvider);
    return Scaffold(
      appBar: AppBar(title: Text(s.mySalary)),
      body: AsyncBody<SalaryOverview>(
        value: salary,
        onRetry: () => ref.invalidate(mySalaryProvider),
        data: (o) => RefreshableList(
          onRefresh: () => ref.refresh(mySalaryProvider.future),
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            if (o.estimate != null) ...[
              SectionHeader(s.runningEstimate),
              PayslipCard(
                payslip: o.estimate!,
                title: Dates.monthTitle(Dates.parseMonth(o.estimate!.month), s.languageCode),
                initiallyExpanded: true,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(s.estimateNote, style: const TextStyle(color: Colors.black54, fontSize: 14)),
              ),
            ],
            SectionHeader(s.advanceBalance),
            Card(
              child: ListTile(
                leading: const Icon(Icons.account_balance_wallet_rounded),
                title: Text(
                  Money.format(o.advanceBalancePaise),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            SectionHeader(s.payslips),
            if (o.payslips.isEmpty) EmptyView(message: s.noPayslips, icon: Icons.receipt_long_outlined),
            for (final p in o.payslips)
              PayslipCard(
                payslip: p,
                title: Dates.monthTitle(Dates.parseMonth(p.month), s.languageCode),
                allowExplain: true,
              ),
          ],
        ),
      ),
    );
  }
}
