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
                      Container(
                        key: const Key('earnedSoFar'),
                        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(20)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${s.earnedSoFarTitle} · ${s.monthTillToday(Dates.monthTitle(Dates.parseMonth(o.estimate!.month), s.languageCode).split(' ').first)}',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13),
                            ),
                            Text(
                              Money.format(o.estimate!.netPaise),
                              style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w800),
                            ),
                            Text(
                              s.paidOnSalaryDay,
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      SectionHeader(s.howWorkedOut),
                      _WorkedOut(payslip: o.estimate!),
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
                              ListTile(
                                key: Key('mySlip_${p.month}'),
                                leading: const CircleAvatar(
                                  backgroundColor: AppColors.mintLight,
                                  child: Text('🧾', style: TextStyle(fontSize: 18)),
                                ),
                                title: Text(
                                  Dates.monthTitle(Dates.parseMonth(p.month), s.languageCode),
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                                subtitle: Text(
                                  p.paidOn == null
                                      ? s.notPaidYet
                                      : s.slipPaidLine(
                                          Dates.dayMonth(DateTime.parse(p.paidOn!), s.languageCode),
                                          s.paymentMethodLabel(p.paymentMethod ?? 'cash'),
                                        ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      Money.format(p.netPaise),
                                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                                    ),
                                    const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                                  ],
                                ),
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

/// One line per reason, each with its amount; deductions only when there are some.
class _WorkedOut extends StatelessWidget {
  const _WorkedOut({required this.payslip});
  final Payslip payslip;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = payslip;
    final sm = p.summary;
    final daily = p.wageType == 'daily';
    final dayRate = daily ? p.ratePaise.toDouble() : (p.divisor > 0 ? p.ratePaise / p.divisor : 0.0);
    // Whole rupees, like the slip.
    int rupees(num paise) => (paise / 100).round() * 100;
    String amt(num days) => Money.format(rupees(days * dayRate));
    // Days paid by the shop's rules (weekly offs, holidays) are what's left of payable days.
    final ruled = p.payableDays - sm.present - sm.halfDay / 2 - sm.paidLeave;
    final rows = <(String, String?, String, bool)>[
      if (sm.present > 0)
        (s.wkPresent(sm.present), '${_n(sm.present)} × ${Money.format(rupees(dayRate))}', amt(sm.present), false),
      if (sm.halfDay > 0) (s.wkHalfDays(sm.halfDay), null, amt(sm.halfDay / 2), false),
      if (sm.paidLeave > 0) (s.wkPaidLeave(sm.paidLeave), null, amt(sm.paidLeave), false),
      if (ruled > 0 && ruled == sm.weekOffs) (s.wkWeekOffs(sm.weekOffs), s.paidByRule, amt(ruled), false),
      if (ruled > 0 && ruled == sm.holidays) (s.wkHolidays(sm.holidays), s.paidByRule, amt(ruled), false),
      if (ruled > 0 && ruled != sm.weekOffs && ruled != sm.holidays)
        (s.wkOffsPaid(ruled), s.paidByRule, amt(ruled), false),
      if (sm.absent + sm.unmarked + sm.unpaidLeave > 0)
        (s.wkNotPaid(sm.absent, sm.unmarked, sm.unpaidLeave), s.notPaidWord, Money.format(0), false),
      for (final l in p.lines)
        if (l.isDeduction && l.amountPaise != 0) (l.label, null, '− ${Money.format(l.amountPaise.abs())}', true),
    ];
    return Card(
      key: const Key('workedOut'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (label, detail, amount, minus) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                          if (detail != null)
                            Text(detail, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                        ],
                      ),
                    ),
                    Text(
                      amount,
                      style: TextStyle(fontWeight: FontWeight.w800, color: minus ? AppColors.red : AppColors.ink),
                    ),
                  ],
                ),
              ),
            if (!daily && p.divisor > 0) ...[
              const Divider(),
              Text(
                s.oneDayRate(Money.format(p.ratePaise), _n(p.divisor), Money.format(rupees(dayRate))),
                style: const TextStyle(color: AppColors.muted, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _n(num v) => v == v.roundToDouble() ? '${v.round()}' : '$v';
