import 'package:flutter/material.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import 'plan_look.dart';

Future<bool> _sheet(BuildContext context, Widget Function(BuildContext ctx) builder) async {
  final r = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: AppColors.paper,
    builder: (ctx) => SingleChildScrollView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 20), child: builder(ctx)),
  );
  return r ?? false;
}

/// Before paying: exactly what happens, in three steps. True when the owner goes ahead.
Future<bool> showPaySheet(
  BuildContext context, {
  required Plan plan,
  required PlanLook look,
  required String title,
  required String interval,
  required ({int total, int extraStaff, int extraBusinesses}) bill,
  required int extraBusinessPricePaise,
  required int priceLockMonths,
  DateTime? trialEndsAt,
}) {
  final s = context.s;
  final yearly = interval == 'yearly';
  final amount = s.money(bill.total);
  final firstAt = trialEndsAt ?? DateTime.now();
  final steps = <(String, String)>[
    if (trialEndsAt != null) ...[
      (s.payTodayZero, s.paySetUp),
      (
        s.payOnDate(Dates.dayMonth(trialEndsAt, s.languageCode), amount),
        yearly ? s.payThenYearly : s.payThenMonthly(firstAt.day),
      ),
    ] else ...[
      (s.payToday(amount), s.payBy),
      (s.payThenEvery(amount, yearly), yearly ? s.payThenYearly : s.payThenMonthly(firstAt.day)),
    ],
    (s.payReceiptHere, s.payReceiptHereSub),
  ];
  return _sheet(
    context,
    (ctx) => Column(
      key: const Key('paySheet'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            PlanBadge(look),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  Text(s.paySheetSub, style: const TextStyle(color: AppColors.muted)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (final (i, (head, sub)) in steps.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 13,
                  backgroundColor: AppColors.ink,
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(head, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      Text(sub, style: const TextStyle(color: AppColors.muted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (bill.extraStaff > 0)
          _Line(s.payExtraStaff(bill.extraStaff, s.money(plan.extraStaffPricePaise * (yearly ? 10 : 1)))),
        if (bill.extraBusinesses > 0)
          _Line(s.payExtraBusinesses(bill.extraBusinesses, s.money(extraBusinessPricePaise * (yearly ? 10 : 1)))),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final m in ['UPI', s.cardShort, s.netBanking])
              Chip(
                label: Text(m, style: const TextStyle(fontWeight: FontWeight.w700)),
                backgroundColor: Colors.white,
                side: const BorderSide(color: AppColors.line),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        const SizedBox(height: 8),
        NoteBox(icon: Icons.lock_rounded, text: s.payLockLine(priceLockMonths)),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: const Key('payGo'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(trialEndsAt != null ? s.payButtonZero : s.payButton(amount)),
          ),
        ),
      ],
    ),
  );
}

/// Moving to a smaller plan: the saving, what stops (with the shop's own numbers) and whether staff fit.
Future<bool> showSwitchSheet(
  BuildContext context, {
  required Plan target,
  required PlanLook look,
  required Plan current,
  required Map<String, int> usage,
  required int staff,
}) {
  final s = context.s;
  final lost = [
    for (final f in current.features)
      if (!target.has(f)) f,
  ]..sort((a, b) => (usage[b] ?? 0).compareTo(usage[a] ?? 0));
  final fits = target.fits(staff);
  final save = current.priceMonthlyPaise - target.priceMonthlyPaise;
  return _sheet(
    context,
    (ctx) => Column(
      key: const Key('switchSheet'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            PlanBadge(look),
            const SizedBox(width: 12),
            Expanded(
              child: Text(s.switchToQ(target.name), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
        if (save > 0) ...[
          const SizedBox(height: 6),
          Text(
            s.youSave(s.money(save), s.money(target.priceMonthlyPaise), s.money(current.priceMonthlyPaise)),
            style: const TextStyle(color: AppColors.muted, fontSize: 16),
          ),
        ],
        if (lost.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(s.willStop, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          for (final f in lost.take(5))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.remove_circle_rounded, color: AppColors.red, size: 20),
                  const SizedBox(width: 8),
                  Icon(featureIcon(f), color: AppColors.red, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      (usage[f] ?? 0) > 0 ? s.usedTimes(s.featureLabel(f), usage[f]!) : s.featureLabel(f),
                      style: const TextStyle(fontSize: 15.5),
                    ),
                  ),
                ],
              ),
            ),
        ],
        const SizedBox(height: 12),
        Container(
          key: Key(fits ? 'staffFits' : 'staffTooMany'),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: fits ? AppColors.mintFaint : AppColors.redLight,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                fits ? Icons.check_circle_rounded : Icons.error_rounded,
                color: fits ? AppColors.mint : AppColors.red,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  fits
                      ? s.staffFitIn(staff, target.name, target.staffLimit)
                      : s.staffNoFit(staff, target.name, target.staffLimit),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.keepPlanNamed(current.name))),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            key: const Key('switchGo'),
            onPressed: fits ? () => Navigator.pop(ctx, true) : null,
            child: Text(s.switchTo(target.name)),
          ),
        ),
      ],
    ),
  );
}

class _Line extends StatelessWidget {
  const _Line(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 38, bottom: 4),
    child: Text(text, style: const TextStyle(color: AppColors.muted, fontSize: 13.5)),
  );
}

/// A soft coloured note with an icon ("Your price stays the same for 2 years.").
class NoteBox extends StatelessWidget {
  const NoteBox({super.key, required this.icon, required this.text, this.amber = false});
  final IconData icon;
  final String text;
  final bool amber;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
      color: amber ? AppColors.amberLight : AppColors.mintLight,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Icon(icon, size: 18, color: amber ? AppColors.amberDark : AppColors.mintDark),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        ),
      ],
    ),
  );
}
