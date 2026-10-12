import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/providers.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/models/models.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/json.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/pickers.dart';
import '../../auth/auth_controller.dart';
import '../providers/owner_providers.dart';

/// One small rules page: loads the shop's settings, edits a few of them and
/// saves only what changed. Every page ends with "Changes apply from today".
class _RulesPage extends ConsumerStatefulWidget {
  const _RulesPage({required this.title, required this.builder, this.intro});
  final String title;
  final String? intro;
  final List<Widget> Function(BuildContext context, Json draft, void Function(String key, Object value) set) builder;

  @override
  ConsumerState<_RulesPage> createState() => _RulesPageState();
}

class _RulesPageState extends ConsumerState<_RulesPage> {
  Json? _base;
  Json? _draft;
  bool _busy = false;

  Future<void> _save() async {
    final changed = <String, Object?>{
      for (final e in _draft!.entries)
        if (e.value != _base![e.key]) e.key: e.value,
    };
    final s = context.s;
    if (changed.isEmpty) return Navigator.of(context).maybePop().ignore();
    setState(() => _busy = true);
    final ok = await runGuarded(
      context,
      () => ref.read(companyApiProvider).updateSettings(changed),
      success: s.rulesSaved,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      ref.invalidate(companyProvider);
      ref.invalidate(rulesProvider);
      ref.read(authControllerProvider.notifier).refreshMe().ignore();
      Navigator.of(context).maybePop().ignore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final company = ref.watch(companyProvider);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title),
            Text(s.groupShopRules, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
          ],
        ),
      ),
      bottomNavigationBar: company.hasValue
          ? StickySaveBar(
              buttonKey: const Key('saveRules'),
              label: s.save,
              note: s.appliesFromToday,
              onPressed: _busy ? null : _save,
            )
          : null,
      body: AsyncBody<Company>(
        value: company,
        onRetry: () => ref.invalidate(companyProvider),
        data: (c) {
          _base ??= c.settings.toJson();
          _draft ??= Json.of(_base!);
          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              if (widget.intro != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(widget.intro!, style: const TextStyle(color: AppColors.muted, height: 1.35)),
                ),
              ...widget.builder(context, _draft!, (k, v) => setState(() => _draft![k] = v)),
            ],
          );
        },
      ),
    );
  }
}

/// A rule with a real example underneath, so the number means something.
class _Rule extends StatelessWidget {
  const _Rule({required this.title, required this.child, this.example});
  final String title;
  final Widget child;
  final String? example;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
          const SizedBox(height: 8),
          child,
          if (example != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(color: AppColors.whyBg, borderRadius: BorderRadius.circular(10)),
              child: Text(example!, style: const TextStyle(fontSize: 13, color: AppColors.ink, height: 1.35)),
            ),
          ],
        ],
      ),
    ),
  );
}

String _clock(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:${m.toString().padLeft(2, '0')}';
}

class AttendanceRulesScreen extends StatelessWidget {
  const AttendanceRulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return _RulesPage(
      title: s.attendanceRulesTitle,
      builder: (context, d, set) {
        final grace = asInt(d['graceMinutes'], 15);
        final half = asNum(d['halfDayHours'], 4);
        final halfLabel = half == half.roundToDouble() ? '${half.round()}' : '$half';
        return [
          _Rule(
            title: s.lateAfterLabel(grace),
            example: s.lateExample('9:00', _clock(9 * 60 + grace + 1)),
            child: Wrap(
              spacing: 8,
              children: [
                for (final m in const [0, 5, 10, 15, 20, 30])
                  ChoiceChip(
                    key: Key('grace_$m'),
                    label: Text('$m'),
                    selected: grace == m,
                    onSelected: (_) => set('graceMinutes', m),
                  ),
              ],
            ),
          ),
          _Rule(
            title: s.halfDayIfLabel(halfLabel),
            example: s.halfDayExample('9:00', _clock(9 * 60 + (half * 60).round() - 30)),
            child: Wrap(
              spacing: 8,
              children: [
                for (final h in const [3, 4, 5, 6])
                  ChoiceChip(
                    key: Key('halfDay_$h'),
                    label: Text('$h'),
                    selected: half == h,
                    onSelected: (_) => set('halfDayHours', h),
                  ),
              ],
            ),
          ),
          _Rule(
            title: s.forgotCheckout,
            example: s.forgotHint,
            child: SegmentedButton<String>(
              key: const Key('missingCheckout'),
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: 'half_day', label: Text(s.statusShort('half_day'))),
                ButtonSegment(value: 'present', label: Text(s.optFullDay)),
                ButtonSegment(value: 'flag', label: Text(s.optAskMe)),
              ],
              selected: {d['missingCheckoutPolicy']?.toString() ?? 'half_day'},
              onSelectionChanged: (v) => set('missingCheckoutPolicy', v.first),
            ),
          ),
          _Rule(
            title: s.morningSummary,
            example: s.morningSummaryHint,
            child: TimeField(
              label: s.digestTime,
              value: d['digestTime']?.toString() ?? '09:30',
              onChanged: (v) => set('digestTime', v),
            ),
          ),
        ];
      },
    );
  }
}

class SalaryRulesScreen extends StatelessWidget {
  const SalaryRulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return _RulesPage(
      title: s.salaryRulesTitle,
      builder: (context, d, set) {
        final divisor = d['monthDivisor']?.toString() ?? 'days_in_month';
        final n = switch (divisor) {
          '30' => 30,
          '26' => 26,
          _ => 31,
        };
        Widget toggle(String key, String title, String hint) => SwitchListTile(
          key: Key('rule_$key'),
          value: d[key] == true,
          title: Text(title),
          subtitle: Text(hint),
          onChanged: (v) => set(key, v),
        );
        return [
          _Rule(
            title: s.monthDivisor,
            example: s.divisorExample(Money.format((1200000 / n).round()), divisor == 'days_in_month' ? '31' : '$n'),
            child: RadioGroup<String>(
              groupValue: divisor,
              onChanged: (v) {
                if (v != null) set('monthDivisor', v);
              },
              child: Column(
                children: [
                  for (final (v, label) in [
                    ('days_in_month', s.divisorDaysInMonth),
                    ('30', s.divisor30),
                    ('26', s.divisor26),
                  ])
                    RadioListTile<String>(dense: true, contentPadding: EdgeInsets.zero, value: v, title: Text(label)),
                ],
              ),
            ),
          ),
          Card(
            child: Column(
              children: [
                toggle('weekOffsPaid', s.weekOffsPaid, s.weekOffsPaidHint),
                toggle('holidaysPaid', s.holidaysPaid, s.holidaysPaidHint),
                toggle('sickLeavePaid', s.sickLeavePaid, s.sickLeavePaidHint),
                toggle('roundToRupee', s.roundToRupee, s.roundToRupeeHint),
              ],
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.account_balance_rounded),
              title: Text(s.statutoryBi.text),
              subtitle: Text(s.statutoryHint),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push(Routes.ownerStatutory),
            ),
          ),
        ];
      },
    );
  }
}

class CheckInSafetyScreen extends ConsumerWidget {
  const CheckInSafetyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final radius = ref.watch(branchesProvider).value?.firstOrNull?.radiusM ?? 100;
    return _RulesPage(
      title: s.safetyTitle,
      intro: s.safetyIntro,
      builder: (context, d, set) {
        final lock = d['phoneLockPolicy']?.toString() ?? 'off';
        return [
          Card(
            child: Column(
              children: [
                ListTile(
                  key: const Key('safetyArea'),
                  leading: const Icon(Icons.location_on_rounded, color: AppColors.mintDark),
                  title: Text(s.mustBeAtShop, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(s.mustBeAtShopHint(radius)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(Routes.ownerBranches),
                ),
                RadioGroup<String>(
                  groupValue: d['outsideGeofencePolicy']?.toString() ?? 'request_approval',
                  onChanged: (v) {
                    if (v != null) set('outsideGeofencePolicy', v);
                  },
                  child: Column(
                    children: [
                      RadioListTile<String>(dense: true, value: 'request_approval', title: Text(s.awayAskMe)),
                      RadioListTile<String>(dense: true, value: 'block', title: Text(s.awayBlock)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  key: const Key('safetySelfie'),
                  secondary: const Icon(Icons.camera_front_rounded),
                  value: d['selfieRequired'] == true,
                  title: Text(s.selfieTitle, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(s.selfieHint),
                  onChanged: (v) => set('selfieRequired', v),
                ),
                SwitchListTile(
                  key: const Key('safetyLock'),
                  secondary: const Icon(Icons.lock_rounded),
                  value: lock != 'off',
                  title: Text(s.phoneLockTitle, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(s.phoneLockHint),
                  onChanged: (v) => set('phoneLockPolicy', v ? 'recommended' : 'off'),
                ),
                if (lock != 'off')
                  CheckboxListTile(
                    key: const Key('safetyLockMust'),
                    value: lock == 'required',
                    title: Text(s.phoneLockMust),
                    onChanged: (v) => set('phoneLockPolicy', v == true ? 'required' : 'recommended'),
                  ),
                SwitchListTile(
                  key: const Key('safetyFace'),
                  secondary: const Icon(Icons.face_retouching_natural_rounded),
                  value: d['faceMatchPolicy']?.toString() == 'review',
                  title: Row(
                    children: [
                      Text(s.faceTitle, style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(color: AppColors.amberLight, borderRadius: BorderRadius.circular(6)),
                        child: Text(s.growthPlan, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ),
                  subtitle: Text(s.faceHint),
                  onChanged: (v) => set('faceMatchPolicy', v ? 'review' : 'off'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Text(s.safetyRecommend, style: const TextStyle(fontSize: 13.5, height: 1.35)),
          ),
        ];
      },
    );
  }
}

/// Shifts (with weekly off) and festival holidays.
class TimingsScreen extends StatelessWidget {
  const TimingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Scaffold(
      appBar: AppBar(title: Text(s.timingsTitle)),
      body: ListView(
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  key: const Key('timingsShifts'),
                  leading: const Icon(Icons.schedule_rounded),
                  title: Text(s.shifts),
                  subtitle: Text(s.timingsHint),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(Routes.ownerShifts),
                ),
                ListTile(
                  key: const Key('timingsHolidays'),
                  leading: const Icon(Icons.celebration_rounded),
                  title: Text(s.holidays),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(Routes.ownerHolidays),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
