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
import 'billing_sheets.dart';
import 'plan_look.dart';

final receiptsProvider = FutureProvider.autoDispose<List<Receipt>>((ref) => ref.watch(billingApiProvider).receipts());

/// Plan & payment, built around one question: which plan is best for me?
/// The server recommends the cheapest plan that fits the staff and what the shop used, and says why.
/// Plans are dynamic (server config); paying opens the gateway's checkout.
class BillingScreen extends ConsumerStatefulWidget {
  const BillingScreen({super.key});

  @override
  ConsumerState<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends ConsumerState<BillingScreen> {
  String _interval = 'monthly';
  String? _busyPlan;

  void _reload() {
    ref.invalidate(billingProvider);
    ref.invalidate(receiptsProvider);
    ref.invalidate(billingGroupProvider);
  }

  Future<void> _subscribe(Plan p) async {
    setState(() => _busyPlan = p.code);
    try {
      final url = await ref.read(billingApiProvider).subscribe(p.code, _interval);
      if (mounted) await openUrl(context, url);
      _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busyPlan = null);
    }
  }

  Future<void> _stop(BillingInfo b) async {
    final s = context.s;
    final until = b.subscription?.currentPeriodEnd?.toLocal() ?? DateTime.now();
    final ok = await confirmDialog(
      context,
      title: s.stopPlanTitle(b.plan?.name ?? ''),
      message: s.stopPlanBody(Dates.pretty(until, s.languageCode)),
      confirmLabel: s.stopPlan,
      destructive: true,
    );
    if (!ok || !mounted) return;
    if (await runGuarded(context, () => ref.read(billingApiProvider).cancel(), success: s.planStopped)) _reload();
  }

  /// Tapping a plan: Free explains itself; a smaller plan first shows what stops; then the pay sheet.
  Future<void> _choose(Plan p, BillingInfo b, Map<String, PlanLook> looks) async {
    final s = context.s;
    final trial = b.trial;
    final trialOn = trial != null && trial.active;
    final current = b.plan;
    final paid = b.subscription?.isPaid ?? false;
    if (p.priceMonthlyPaise <= 0) {
      if (paid) return _stop(b);
      if (trialOn) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(p.name),
            content: Text(s.freeAfterTrial(Dates.pretty(trial.endsAt.toLocal(), s.languageCode))),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.ok))],
          ),
        );
      }
      return;
    }
    final staff = b.billStaffCount;
    if (current != null && current.code != p.code && current.priceMonthlyPaise > p.priceMonthlyPaise) {
      final losesUsed = current.features.any((f) => !p.has(f) && (b.usage[f] ?? 0) > 0);
      if (losesUsed || !p.fits(staff)) {
        final go = await showSwitchSheet(
          context,
          target: p,
          look: looks[p.code]!,
          current: current,
          usage: b.usage,
          staff: staff,
        );
        if (!go || !mounted) return;
      }
    }
    final group = ref.read(billingGroupProvider).value;
    final extraBiz = group != null && group.isPayer ? group.members.length : 0;
    final extraBizPrice = group?.extraBusinessPricePaise ?? 0;
    final go = await showPaySheet(
      context,
      plan: p,
      look: looks[p.code]!,
      title: current?.code == p.code ? s.keepPlanNamed(p.name) : s.choosePlanNamed(p.name),
      interval: _interval,
      bill: billFor(p, _interval, staff: staff, extraBusinesses: extraBiz, extraBusinessPricePaise: extraBizPrice),
      extraBusinessPricePaise: extraBizPrice,
      priceLockMonths: b.priceLockMonths,
      trialEndsAt: trialOn ? trial.endsAt.toLocal() : null,
    );
    if (go && mounted) await _subscribe(p);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final info = ref.watch(billingProvider);
    final plans = ref.watch(plansProvider);
    return Scaffold(
      appBar: AppBar(title: Text(s.billing)),
      body: RefreshableList(
        onRefresh: () async {
          _reload();
          ref.invalidate(plansProvider);
          await ref.read(billingProvider.future);
        },
        children: [
          if (info.hasError)
            ErrorView(error: info.error!, onRetry: () => ref.invalidate(billingProvider))
          else if (plans.hasError)
            ErrorView(error: plans.error!, onRetry: () => ref.invalidate(plansProvider))
          else if (!info.hasValue || !plans.hasValue)
            const LoadingView()
          else
            ..._content(info.value!, plans.value!),
        ],
      ),
    );
  }

  List<Widget> _content(BillingInfo b, List<Plan> plans) {
    final s = context.s;
    final sorted = [...plans]..sort((a, c) => a.priceMonthlyPaise.compareTo(c.priceMonthlyPaise));
    final looks = {for (final (i, p) in sorted.indexed) p.code: PlanLook.of(p, i)};
    Plan? byCode(String? code) {
      for (final p in sorted) {
        if (p.code == code) return p;
      }
      return null;
    }

    final trial = b.trial;
    final trialOn = trial != null && trial.active;
    final sub = b.subscription;
    final paid = sub?.isPaid ?? false;
    final paidCode = paid ? sub!.planCode : null;
    final staff = b.billStaffCount;
    final rec = b.recommendation;
    final recPlan = byCode(rec?.planCode);
    final cheaper = byCode(rec?.cheaperCode);
    final monthsFree = sorted.map(monthsFreeYearly).fold(0, (a, c) => c > a ? c : a);

    if (b.billedToName != null) {
      return [
        _StatusStrip(b: b),
        Padding(
          padding: const EdgeInsets.all(16),
          child: NoteBox(
            key: const Key('billedWith'),
            icon: Icons.storefront_rounded,
            text: s.billedWith(b.billedToName!),
          ),
        ),
      ];
    }

    return [
      _StatusStrip(b: b),
      if (recPlan != null) ...[
        SectionHeader(s.billBestTitle),
        _BestCard(
          plan: recPlan,
          look: looks[recPlan.code]!,
          rec: rec!,
          trial: trial,
          isYours: paidCode == recPlan.code,
          isCurrent: b.plan?.code == recPlan.code,
          busy: _busyPlan == recPlan.code,
          onChoose: _busyPlan != null ? null : () => _choose(recPlan, b, looks),
        ),
        if (cheaper != null && paidCode != cheaper.code)
          _CheaperCard(
            plan: cheaper,
            look: looks[cheaper.code]!,
            staff: staff,
            loses: [for (final l in rec.cheaperLoses) l.feature],
            onTap: _busyPlan != null ? null : () => _choose(cheaper, b, looks),
          ),
      ],
      SectionHeader(s.allPlans),
      Padding(
        padding: EdgeInsets.fromLTRB(16, monthsFree > 0 ? 10 : 0, 16, 0),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                key: const Key('billingInterval'),
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: 'monthly', label: Text(s.monthly)),
                  ButtonSegment(value: 'yearly', label: Text(s.yearly)),
                ],
                selected: {_interval},
                onSelectionChanged: (v) => setState(() => _interval = v.first),
              ),
            ),
            // The yearly saving sits on the Yearly half, like a sticker.
            if (monthsFree > 0)
              Positioned(
                top: -10,
                right: 14,
                child: IgnorePointer(child: _Pill(s.monthsFree(monthsFree), color: AppColors.amber)),
              ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      for (final (i, p) in sorted.indexed)
        _PlanCard(
          plan: p,
          look: looks[p.code]!,
          added: addedFeatures(sorted, i),
          first: i == 0,
          yearly: _interval == 'yearly',
          fits: p.fits(staff),
          recommended: rec?.planCode == p.code,
          yours: paidCode == p.code,
          onTrial: trialOn && trial.planCode == p.code,
          busy: _busyPlan == p.code,
          onTap: _busyPlan != null || (paidCode == p.code && sub?.interval == _interval)
              ? null
              : () => _choose(p, b, looks),
        ),
      if (plansNested(sorted))
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
          child: Text(
            s.plansNested,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, fontSize: 13.5),
          ),
        ),
      SectionHeader(s.comparePlans),
      _CompareTable(plans: sorted, looks: looks, highlight: rec?.planCode ?? b.plan?.code),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Column(
          children: [
            if (b.priceLockMonths > 0) NoteBox(icon: Icons.lock_rounded, text: s.priceLocked(b.priceLockMonths)),
            for (final p in sorted)
              if (p.extraStaffPricePaise > 0) ...[
                const SizedBox(height: 8),
                NoteBox(
                  icon: Icons.groups_rounded,
                  amber: true,
                  text: s.extraStaffNote(p.name, p.staffLimit, s.money(p.extraStaffPricePaise)),
                ),
              ],
          ],
        ),
      ),
      SectionHeader(s.payments),
      _PaymentsCard(b: b, recPlan: recPlan),
      const _OneBillCard(),
      _HelpCard(),
      if (paid && sub!.status != 'cancelled') ...[
        TextButton(
          key: const Key('stopPlan'),
          style: TextButton.styleFrom(foregroundColor: AppColors.red),
          onPressed: () => _stop(b),
          child: Text(s.stopPlan, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            s.dataSafeNote,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
        ),
      ],
    ];
  }
}

/// One line on top: trial days left, renewal date, a failed payment, or when a stopped plan ends.
class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.b});
  final BillingInfo b;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final lang = s.languageCode;
    final trial = b.trial;
    final sub = b.subscription;
    final planName = b.plan?.name ?? '';
    final end = sub?.currentPeriodEnd?.toLocal();
    (IconData, Color, Color, String, String)? look;
    if (trial != null && trial.active) {
      look = (
        Icons.calendar_month_rounded,
        AppColors.amberLight,
        AppColors.amberDark,
        s.billTrialLeft(trial.daysLeft),
        ' · ${s.billTrialEnds(Dates.dayMonth(trial.endsAt.toLocal(), lang))}',
      );
    } else if (trial != null) {
      look = (
        Icons.info_rounded,
        AppColors.amberLight,
        AppColors.amberDark,
        s.billTrialEnded(Dates.dayMonth(trial.endsAt.toLocal(), lang)),
        '',
      );
    } else if (sub?.status == 'past_due') {
      look = (Icons.error_rounded, AppColors.redLight, AppColors.red, s.billPaymentDue(planName), '');
    } else if (sub?.status == 'cancelled' && end != null && end.isAfter(DateTime.now())) {
      look = (
        Icons.event_busy_rounded,
        AppColors.mutedLight,
        AppColors.muted,
        s.billStopsOn(planName, Dates.pretty(end, lang)),
        '',
      );
    } else if (sub?.status == 'active' && end != null) {
      look = (
        Icons.verified_rounded,
        AppColors.mintLight,
        AppColors.mintDark,
        s.billRenews(planName, Dates.pretty(end, lang)),
        '',
      );
    }
    if (look == null) return const SizedBox(height: 4);
    final (icon, bg, fg, bold, rest) = look;
    return Container(
      key: const Key('billingStatus'),
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(icon, color: fg, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: bold,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  TextSpan(text: rest),
                ],
              ),
              style: const TextStyle(fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, {required this.color, this.icon});
  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 1),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(99)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, color: Colors.white, size: 14), const SizedBox(width: 4)],
        Text(
          text,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5),
        ),
      ],
    ),
  );
}

/// The recommended plan, with plain reasons from the shop's own use.
class _BestCard extends StatelessWidget {
  const _BestCard({
    required this.plan,
    required this.look,
    required this.rec,
    required this.trial,
    required this.isYours,
    required this.isCurrent,
    required this.busy,
    required this.onChoose,
  });
  final Plan plan;
  final PlanLook look;
  final PlanRecommendation rec;
  final Trial? trial;
  final bool isYours;
  final bool isCurrent;
  final bool busy;
  final VoidCallback? onChoose;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final trialOn = trial != null && trial!.active;
    final free = plan.priceMonthlyPaise <= 0;
    final reasons = [
      for (final r in rec.reasons)
        r.feature == null
            ? s.reasonStaff(r.staff!, r.limit!)
            : s.reasonFeature(r.feature!, r.count, trial: trial != null),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            key: const Key('bestPlan'),
            padding: const EdgeInsets.fromLTRB(16, 22, 16, 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.mint, width: 2.5),
              boxShadow: [
                BoxShadow(color: AppColors.mint.withValues(alpha: 0.15), blurRadius: 18, offset: const Offset(0, 6)),
              ],
            ),
            child: Column(
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
                          Text(plan.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                          Text(s.planWho(plan.code, plan.staffLimit), style: const TextStyle(color: AppColors.muted)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          s.money(plan.priceMonthlyPaise),
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                        ),
                        Text(
                          free ? s.freeForever : s.aMonth,
                          style: const TextStyle(color: AppColors.muted, fontSize: 13.5),
                        ),
                      ],
                    ),
                  ],
                ),
                if (!free) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    decoration: BoxDecoration(color: look.bg, borderRadius: BorderRadius.circular(99)),
                    child: Text(
                      s.aboutPerDay(perDay(plan)),
                      style: TextStyle(color: look.fg, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Text(s.whyThisPlan, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                for (final r in reasons)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_rounded, color: AppColors.mint, size: 20),
                        const SizedBox(width: 10),
                        Expanded(child: Text(r, style: const TextStyle(fontSize: 15))),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                if (free)
                  Text(
                    s.freeIsEnough(trial: trialOn),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  )
                else ...[
                  SizedBox(
                    width: double.infinity,
                    child: isYours
                        ? OutlinedButton.icon(
                            key: const Key('bestIsYours'),
                            onPressed: null,
                            icon: const Icon(Icons.check_rounded),
                            label: Text(s.thisIsYourPlan),
                          )
                        : FilledButton(
                            key: const Key('bestChoose'),
                            onPressed: onChoose,
                            child: busy
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : Text(isCurrent ? s.keepPlanNamed(plan.name) : s.choosePlanNamed(plan.name)),
                          ),
                  ),
                  if (!isYours) ...[
                    const SizedBox(height: 6),
                    Center(
                      child: Text(
                        trialOn
                            ? s.billFootTrial(Dates.dayMonth(trial!.endsAt.toLocal(), s.languageCode))
                            : s.billFootPaid,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.muted, fontSize: 13.5),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
          Positioned(
            top: -13,
            left: 16,
            child: _Pill(s.billBestBadge, color: AppColors.mint, icon: Icons.star_rounded),
          ),
        ],
      ),
    );
  }
}

/// "Want to spend less?": the next cheaper plan that holds the staff, and honestly what stops there.
class _CheaperCard extends StatelessWidget {
  const _CheaperCard({
    required this.plan,
    required this.look,
    required this.staff,
    required this.loses,
    required this.onTap,
  });
  final Plan plan;
  final PlanLook look;
  final int staff;
  final List<String> loses;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Card(
      key: const Key('cheaperPlan'),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: InkWell(
        borderRadius: AppTheme.radius,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  PlanBadge(look),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.spendLess(plan.name), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        Text(
                          plan.priceMonthlyPaise <= 0
                              ? s.freeForever
                              : s.priceMonthDay(s.money(plan.priceMonthlyPaise), perDay(plan)),
                          style: const TextStyle(color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                ],
              ),
              if (loses.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  s.fitsButStops(staff, featureList(s, loses)),
                  style: const TextStyle(color: AppColors.amberDark, fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One plan: its colour and picture, who it is for, price a day, and only what it adds.
class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.look,
    required this.added,
    required this.first,
    required this.yearly,
    required this.fits,
    required this.recommended,
    required this.yours,
    required this.onTrial,
    required this.busy,
    required this.onTap,
  });
  final Plan plan;
  final PlanLook look;
  final List<String> added;
  final bool first;
  final bool yearly;
  final bool fits;
  final bool recommended;
  final bool yours;
  final bool onTrial;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final free = plan.priceMonthlyPaise <= 0;
    final faded = !fits;
    final tags = [if (recommended) s.billBestBadge, if (yours) s.yourPlan, if (onTrial) s.onTrialNow];
    final strong = recommended || yours;
    final price = yearly && !free ? plan.priceYearlyPaise : plan.priceMonthlyPaise;
    final saving = plan.priceMonthlyPaise * 12 - plan.priceYearlyPaise;
    final muted = faded ? const Color(0xFFA49B8A) : AppColors.ink;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, tags.isEmpty ? 0 : 14, 16, 10),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: faded ? const Color(0xFFFAF8F2) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: strong ? AppColors.mint : AppColors.line, width: strong ? 2.5 : 1),
            ),
            child: InkWell(
              key: Key('plan_${plan.code}'),
              borderRadius: BorderRadius.circular(16),
              onTap: onTap,
              child: Padding(
                padding: EdgeInsets.fromLTRB(12, tags.isEmpty ? 11 : 16, 12, 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        PlanBadge(look, faded: faded),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                plan.name,
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: muted),
                              ),
                              Text(
                                faded ? s.notForYouStaff(plan.staffLimit) : s.planWho(plan.code, plan.staffLimit),
                                style: TextStyle(
                                  color: faded ? AppColors.amberDark : AppColors.muted,
                                  fontWeight: faded ? FontWeight.w700 : FontWeight.w400,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            busy
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(
                                          text: s.money(price),
                                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: muted),
                                        ),
                                        if (!free)
                                          TextSpan(
                                            text: ' / ${yearly ? s.aYear : s.aMonth}',
                                            style: const TextStyle(fontSize: 13, color: AppColors.muted),
                                          ),
                                      ],
                                    ),
                                  ),
                            Text(
                              free ? s.freeForever : s.perDayShort(perDay(plan)),
                              style: TextStyle(
                                color: free ? AppColors.muted : look.fg,
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (yearly && !free && saving > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          s.yearlyPerMonthSave(wholeRupees(plan.priceYearlyPaise / 12), s.money(saving)),
                          style: const TextStyle(
                            color: AppColors.mintDark,
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Opacity(
                      opacity: faded ? 0.55 : 1,
                      child: Wrap(
                        spacing: 5,
                        runSpacing: 5,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _FeatureChip(
                            icon: Icons.people_rounded,
                            label: s.staffChip(plan.staffLimit, more: plan.extraStaffPricePaise > 0),
                            fg: AppColors.ink,
                            bg: AppColors.mutedLight,
                          ),
                          if (!first)
                            const Text(
                              '+',
                              style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.muted),
                            ),
                          for (final f in added)
                            _FeatureChip(icon: featureIcon(f), label: s.featureLabel(f), fg: look.fg, bg: look.bg),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (tags.isNotEmpty)
            Positioned(
              top: -12,
              left: 12,
              child: _Pill(tags.join(' · '), color: AppColors.mint, icon: recommended ? Icons.star_rounded : null),
            ),
        ],
      ),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip({required this.icon, required this.label, required this.fg, required this.bg});
  final IconData icon;
  final String label;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(6, 2, 9, 2),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: fg),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 13),
        ),
      ],
    ),
  );
}

/// Every plan side by side: a picture per row, a tick in each plan's colour.
class _CompareTable extends StatelessWidget {
  const _CompareTable({required this.plans, required this.looks, this.highlight});
  final List<Plan> plans;
  final Map<String, PlanLook> looks;
  final String? highlight;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final rows = [
      for (final g in compareGroups)
        if (plans.any((p) => g.$3.any(p.has))) g,
    ];
    Widget cell(Plan p, Widget child) => Container(
      color: p.code == highlight ? AppColors.mintFaint : null,
      height: 34,
      alignment: Alignment.center,
      child: child,
    );
    Widget label(IconData icon, String text, {bool bold = false}) => SizedBox(
      height: 34,
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13.5, fontWeight: bold ? FontWeight.w800 : FontWeight.w400),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
    final line = TableRow(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.lineSoft)),
      ),
      children: [const SizedBox.shrink(), for (final _ in plans) const SizedBox.shrink()],
    );
    return Card(
      key: const Key('compareTable'),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
        child: Table(
          columnWidths: {
            0: const FlexColumnWidth(2.5),
            for (var i = 1; i <= plans.length; i++) i: const FlexColumnWidth(1.05),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              children: [
                const SizedBox.shrink(),
                for (final p in plans)
                  Container(
                    color: p.code == highlight ? AppColors.mintFaint : null,
                    padding: const EdgeInsets.only(top: 4, bottom: 6),
                    child: Column(
                      children: [
                        PlanBadge(looks[p.code]!, size: 26),
                        const SizedBox(height: 2),
                        FittedBox(
                          child: Text(
                            p.name,
                            style: TextStyle(color: looks[p.code]!.fg, fontWeight: FontWeight.w800, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            TableRow(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.lineSoft)),
              ),
              children: [
                label(Icons.people_rounded, s.compareRow('staff')),
                for (final p in plans)
                  cell(
                    p,
                    Text(
                      '${p.staffLimit}${p.extraStaffPricePaise > 0 ? '+' : ''}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                    ),
                  ),
              ],
            ),
            for (final (key, icon, features) in rows)
              TableRow(
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: AppColors.lineSoft)),
                ),
                children: [
                  label(icon, s.compareRow(key)),
                  for (final p in plans)
                    cell(
                      p,
                      features.any(p.has)
                          ? Container(
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(color: looks[p.code]!.fg, shape: BoxShape.circle),
                              child: const Icon(Icons.check_rounded, size: 13, color: Colors.white),
                            )
                          : Container(width: 10, height: 2, color: const Color(0xFFD5CDBB)),
                    ),
                ],
              ),
            TableRow(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.lineSoft)),
              ),
              children: [
                label(Icons.calendar_today_rounded, s.priceADay, bold: true),
                for (final p in plans)
                  cell(
                    p,
                    Text(
                      p.priceMonthlyPaise <= 0 ? Money.format(0) : perDay(p),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: p.code == highlight ? FontWeight.w800 : FontWeight.w400,
                      ),
                    ),
                  ),
              ],
            ),
            line,
          ],
        ),
      ),
    );
  }
}

/// Next payment and receipts.
class _PaymentsCard extends ConsumerWidget {
  const _PaymentsCard({required this.b, required this.recPlan});
  final BillingInfo b;
  final Plan? recPlan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final lang = s.languageCode;
    final sub = b.subscription;
    final trial = b.trial;
    final receipts = ref.watch(receiptsProvider).value ?? const <Receipt>[];
    final String next;
    if (sub != null && sub.status == 'active' && sub.currentPeriodEnd != null) {
      next = s.nextPaymentOn(
        s.money(sub.pricePaise ?? b.plan?.priceMonthlyPaise ?? 0),
        Dates.pretty(sub.currentPeriodEnd!.toLocal(), lang),
      );
    } else if (trial != null && trial.active && recPlan != null && recPlan!.priceMonthlyPaise > 0) {
      next = s.nextPaymentTrial(
        s.money(recPlan!.priceMonthlyPaise),
        Dates.dayMonth(trial.endsAt.toLocal(), lang),
        recPlan!.name,
      );
    } else {
      next = s.nothingToPay;
    }
    Widget icon(IconData i, Color fg, Color bg) => Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Icon(i, color: fg, size: 20),
    );
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        children: [
          ListTile(
            key: const Key('nextPayment'),
            leading: icon(Icons.calendar_month_rounded, AppColors.amberDark, AppColors.amberLight),
            title: Text(s.nextPayment, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(next),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            leading: icon(Icons.receipt_long_rounded, AppColors.mintDark, AppColors.mintLight),
            title: Text(s.receipts, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: receipts.isEmpty ? Text(s.receiptsEmpty) : null,
          ),
          for (final r in receipts.take(6))
            ListTile(
              key: Key('receipt_${r.id}'),
              dense: true,
              contentPadding: const EdgeInsets.fromLTRB(72, 0, 16, 0),
              title: Text(s.receiptFor(r.planName ?? '', r.interval == 'yearly')),
              subtitle: Text(
                [Dates.pretty(r.paidAt.toLocal(), lang), if (r.hasInvoice) s.openInvoice].join(' · '),
                style: TextStyle(color: r.hasInvoice ? AppColors.mintDark : AppColors.muted),
              ),
              trailing: Text(s.money(r.amountPaise), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              onTap: r.hasInvoice
                  ? () async {
                      String? url;
                      final ok = await runGuarded(
                        context,
                        () async => url = await ref.read(billingApiProvider).receiptLink(r.id),
                      );
                      if (ok && url != null && context.mounted) await openUrl(context, url!);
                    }
                  : null,
            ),
        ],
      ),
    );
  }
}

class _HelpCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final whatsapp = ref.watch(publicConfigProvider).value?.supportWhatsApp;
    if (whatsapp == null || whatsapp.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: ListTile(
        key: const Key('paymentHelp'),
        leading: const Icon(Icons.chat_rounded, color: AppColors.whatsapp),
        title: Text(s.paymentQuestions, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(s.chatOnWhatsApp),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => openUrl(context, 'https://wa.me/${whatsapp.replaceAll(RegExp(r'[^0-9]'), '')}'),
      ),
    );
  }
}

final billingGroupProvider = FutureProvider.autoDispose<BillingGroup>(
  (ref) => ref.watch(accountsApiProvider).billingGroup(),
);

/// One bill for several businesses of the same main owner (PRD F14 Phase 4).
class _OneBillCard extends ConsumerWidget {
  const _OneBillCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final g = ref.watch(billingGroupProvider).value;
    // Nothing to show for a single business.
    if (g == null || !g.isPayer || (g.members.isEmpty && g.candidates.isEmpty)) return const SizedBox.shrink();
    final api = ref.read(accountsApiProvider);
    Future<void> act(Future<BillingGroup> Function() call) async {
      if (await runGuarded(context, call)) {
        ref.invalidate(billingGroupProvider);
        ref.invalidate(billingProvider);
      }
    }

    return Card(
      key: const Key('oneBillCard'),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: const BoxDecoration(color: AppColors.mutedLight, shape: BoxShape.circle),
                  child: const Icon(Icons.storefront_rounded, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(s.oneBillBi.text, style: Theme.of(context).textTheme.titleMedium)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              s.oneBillHint(Money.format(g.extraBusinessPricePaise)),
              style: const TextStyle(color: AppColors.muted),
            ),
            if (g.members.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(s.totalStaffOnBill(g.totalStaff), style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
            for (final m in g.members)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.check_circle_rounded, color: AppColors.mint),
                title: Text(m.name),
                subtitle: Text(s.onThisBill),
                trailing: TextButton(
                  onPressed: () => act(() => api.removeFromBill(m.companyId)),
                  child: Text(s.removeFromBill),
                ),
              ),
            for (final c in g.candidates)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.storefront_rounded, color: AppColors.muted),
                title: Text(c.name),
                trailing: FilledButton.tonal(
                  key: Key('addToBill-${c.companyId}'),
                  onPressed: () => act(() => api.addToBill(c.companyId)),
                  child: Text(s.addToBill),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
