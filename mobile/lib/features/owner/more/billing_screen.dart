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

/// Plans are dynamic (server config); subscribing opens the checkout URL.
class BillingScreen extends ConsumerStatefulWidget {
  const BillingScreen({super.key});

  @override
  ConsumerState<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends ConsumerState<BillingScreen> {
  String _interval = 'monthly';
  String? _busyPlan;

  Future<void> _subscribe(Plan p) async {
    setState(() => _busyPlan = p.code);
    try {
      final url = await ref.read(billingApiProvider).subscribe(p.code, _interval);
      if (mounted) await openUrl(context, url);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busyPlan = null);
    }
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
          ref.invalidate(billingProvider);
          ref.invalidate(plansProvider);
          await ref.read(plansProvider.future);
        },
        children: [
          info.when(
            loading: () => const LoadingView(),
            error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(billingProvider)),
            data: (b) => Card(
              color: AppColors.mintLight,
              shape: const RoundedRectangleBorder(
                borderRadius: AppTheme.radius,
                side: BorderSide(color: AppColors.mint, width: 1.5),
              ),
              margin: const EdgeInsets.all(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.currentPlan, style: Theme.of(context).textTheme.bodyMedium),
                    Text(
                      b.plan?.name ?? '—',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    if (b.subscription != null) Text(s.subscriptionStatus(b.subscription!.status)),
                    if (b.subscription?.currentPeriodEnd != null)
                      Text(s.renewsOn(Dates.pretty(b.subscription!.currentPeriodEnd!.toLocal(), s.languageCode))),
                    if (b.plan != null) Text(s.staffUsage(b.staffCount, b.plan!.staffLimit)),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'monthly', label: Text(s.monthly)),
                ButtonSegment(value: 'yearly', label: Text(s.yearly)),
              ],
              selected: {_interval},
              onSelectionChanged: (v) => setState(() => _interval = v.first),
            ),
          ),
          const SizedBox(height: 8),
          plans.when(
            loading: () => const LoadingView(),
            error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(plansProvider)),
            data: (list) {
              final currentCode = info.value?.plan?.code;
              return Column(
                children: [
                  for (final p in list)
                    Card(
                      shape: p.code == currentCode
                          ? RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: const BorderSide(color: AppColors.mint, width: 2),
                            )
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(child: Text(p.name, style: Theme.of(context).textTheme.titleLarge)),
                                Text(
                                  _interval == 'monthly'
                                      ? s.priceMonthly(Money.format(p.priceMonthlyPaise))
                                      : s.priceYearly(Money.format(p.priceYearlyPaise)),
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              [s.staffLimit(p.staffLimit), if (p.trialDays > 0) s.trialDays(p.trialDays)].join(' · '),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final f in p.features)
                                  Chip(
                                    visualDensity: VisualDensity.compact,
                                    avatar: const Icon(Icons.check_rounded, size: 16, color: AppColors.mint),
                                    side: BorderSide.none,
                                    backgroundColor: AppColors.mintFaint,
                                    label: Text(s.featureLabel(f), style: const TextStyle(fontSize: 13)),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: p.code == currentCode
                                  ? OutlinedButton(onPressed: null, child: Text(s.yourPlan))
                                  : FilledButton(
                                      onPressed: _busyPlan != null ? null : () => _subscribe(p),
                                      child: _busyPlan == p.code
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                            )
                                          : Text(s.choosePlan),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
