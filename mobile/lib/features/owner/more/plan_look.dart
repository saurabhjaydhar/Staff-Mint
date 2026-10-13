import 'package:flutter/material.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';

/// One colour and picture per plan, the same everywhere, so people can tell plans apart at a glance.
class PlanLook {
  const PlanLook(this.icon, this.fg, this.bg);
  final IconData icon;
  final Color fg;
  final Color bg;

  static const _byCode = {
    'free': PlanLook(Icons.spa_rounded, AppColors.muted, AppColors.mutedLight),
    'starter': PlanLook(Icons.storefront_rounded, AppColors.indigo, AppColors.indigoLight),
    'growth': PlanLook(Icons.trending_up_rounded, AppColors.mintDark, AppColors.mintLight),
    'pro': PlanLook(Icons.apartment_rounded, AppColors.orange, AppColors.orangeLight),
  };
  static const _others = [
    PlanLook(Icons.workspace_premium_rounded, AppColors.indigo, AppColors.indigoLight),
    PlanLook(Icons.star_rounded, AppColors.amberDark, AppColors.amberLight),
  ];

  static PlanLook of(Plan p, [int index = 0]) => _byCode[p.code] ?? _others[index % _others.length];
}

/// The plan's picture in its colour.
class PlanBadge extends StatelessWidget {
  const PlanBadge(this.look, {super.key, this.size = 44, this.faded = false});
  final PlanLook look;
  final double size;
  final bool faded;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: faded ? 0.55 : 1,
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: look.bg, borderRadius: BorderRadius.circular(size * 0.32)),
      child: Icon(look.icon, color: look.fg, size: size * 0.5),
    ),
  );
}

/// Picture for each paid feature (and the compare-table rows).
IconData featureIcon(String f) => switch (f) {
  'attendance' => Icons.event_available_rounded,
  'leave' => Icons.beach_access_rounded,
  'digest' => Icons.summarize_rounded,
  'payroll' => Icons.currency_rupee_rounded,
  'advances' => Icons.payments_rounded,
  'payslips' => Icons.receipt_long_rounded,
  'reports' => Icons.bar_chart_rounded,
  'roster' => Icons.calendar_view_week_rounded,
  'roster_repeat' => Icons.event_repeat_rounded,
  'assistant' => Icons.mic_rounded,
  'branches' => Icons.store_mall_directory_rounded,
  'whatsapp_payslips' || 'whatsapp_assistant' => Icons.chat_rounded,
  'face_match' => Icons.face_rounded,
  'ca_access' => Icons.account_balance_rounded,
  'priority_support' => Icons.headset_mic_rounded,
  _ => Icons.check_circle_rounded,
};

/// Rows of the compare table: a few features people think of as one thing share a row.
const compareGroups = <(String, IconData, List<String>)>[
  ('attendance', Icons.event_available_rounded, ['attendance', 'leave', 'digest']),
  ('salary', Icons.currency_rupee_rounded, ['payroll', 'advances']),
  ('slips', Icons.receipt_long_rounded, ['payslips', 'reports']),
  ('roster', Icons.calendar_view_week_rounded, ['roster']),
  ('roster_repeat', Icons.event_repeat_rounded, ['roster_repeat']),
  ('mint', Icons.mic_rounded, ['assistant']),
  ('branches', Icons.store_mall_directory_rounded, ['branches']),
  ('whatsapp', Icons.chat_rounded, ['whatsapp_payslips', 'whatsapp_assistant']),
  ('face', Icons.face_rounded, ['face_match']),
  ('ca', Icons.account_balance_rounded, ['ca_access']),
  ('support', Icons.headset_mic_rounded, ['priority_support']),
];

/// What a plan adds over the one before it (the first plan: all it has), skipping the daily summary.
List<String> addedFeatures(List<Plan> sorted, int i) {
  final before = i == 0 ? const <String>{} : sorted[i - 1].features.toSet();
  return [
    for (final f in sorted[i].features)
      if (!before.contains(f) && f != 'digest') f,
  ];
}

/// True when every plan has everything the cheaper ones have.
bool plansNested(List<Plan> sorted) {
  for (var i = 1; i < sorted.length; i++) {
    if (!sorted[i - 1].features.every(sorted[i].has)) return false;
  }
  return true;
}

/// Whole rupees, so "₹33 a day" rather than "₹33.30".
String wholeRupees(num paise) => Money.format((paise / 100).round() * 100);

String perDay(Plan p) => wholeRupees(p.priceMonthlyPaise / 30);

/// Free months when paying yearly ("2 months free"), 0 when there is no saving.
int monthsFreeYearly(Plan p) {
  if (p.priceMonthlyPaise <= 0 || p.priceYearlyPaise <= 0) return 0;
  return ((p.priceMonthlyPaise * 12 - p.priceYearlyPaise) / p.priceMonthlyPaise).round();
}

/// Plan names joined in plain words: "Face check and Salary slips on WhatsApp".
String featureList(S s, Iterable<String> features) => s.andJoin([for (final f in features) s.featureLabel(f)]);

/// What the bill comes to for [p]: plan price plus extra staff and extra businesses (yearly: ×10).
({int total, int extraStaff, int extraBusinesses}) billFor(
  Plan p,
  String interval, {
  required int staff,
  int extraBusinesses = 0,
  int extraBusinessPricePaise = 0,
}) {
  final yearly = interval == 'yearly';
  final extraStaff = p.extraStaffPricePaise > 0 && staff > p.staffLimit ? staff - p.staffLimit : 0;
  final mult = yearly ? 10 : 1;
  final total =
      (yearly ? p.priceYearlyPaise : p.priceMonthlyPaise) +
      extraStaff * p.extraStaffPricePaise * mult +
      extraBusinesses * extraBusinessPricePaise * mult;
  return (total: total, extraStaff: extraStaff, extraBusinesses: extraBusinesses);
}
