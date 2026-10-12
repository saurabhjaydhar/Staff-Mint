import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/models/models.dart';
import '../../../core/router/routes.dart';
import '../../../core/storage/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../auth/auth_controller.dart';

/// Free trial on the owner's home screen: one small line ("Free trial: 9
/// days left · See plans") until the last 3 days, then a full card; after the
/// trial, "Your free trial has ended" with what keeps working (dismissible).
class TrialBanner extends ConsumerStatefulWidget {
  const TrialBanner({super.key, this.padding = const EdgeInsets.fromLTRB(14, 4, 14, 6)});
  final EdgeInsets padding;

  @override
  ConsumerState<TrialBanner> createState() => _TrialBannerState();
}

class _TrialBannerState extends ConsumerState<TrialBanner> {
  String _key(Company c) => 'sm_trial_ended_seen_${c.id}';

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final session = ref.watch(authControllerProvider);
    final company = session.company;
    final trial = company?.trial;
    if (!session.isOwner || company == null || trial == null) return const SizedBox.shrink();
    final prefs = ref.watch(sharedPreferencesProvider);
    final now = DateTime.now();
    final active = trial.activeAt(now);
    final endsIso = trial.endsAt.toIso8601String();
    if (!active && prefs.getString(_key(company)) == endsIso) return const SizedBox.shrink();

    final days = trial.daysLeftAt(now);
    final soon = active && days <= 3;
    final date = Dates.dayMonth(trial.endsAt.toLocal(), s.languageCode);
    final paused = trial.paidFeatures.where((f) => f != 'priority_support').map(s.featureLabel).join(', ');
    final color = active ? (soon ? AppColors.amberDark : AppColors.mintDark) : AppColors.ink;
    final bg = active ? (soon ? AppColors.amberLight : AppColors.mintLight) : AppColors.mutedLight;

    if (active && !soon) {
      return Padding(
        padding: widget.padding,
        child: Material(
          key: const Key('trialBanner'),
          color: AppColors.mintFaint,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            key: const Key('trialSeePlans'),
            borderRadius: BorderRadius.circular(12),
            onTap: () => GoRouter.maybeOf(context)?.push(Routes.ownerBilling),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome_rounded, size: 18, color: AppColors.mintDark),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.trialLeft(trial.planName, days),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5, color: AppColors.mintDark, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    s.seePlans,
                    style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.mintDark),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: widget.padding,
      child: Container(
        key: Key(active ? 'trialBanner' : 'trialEndedBanner'),
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(active ? Icons.auto_awesome_rounded : Icons.info_outline_rounded, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        active ? s.trialLeft(trial.planName, days) : s.trialEndedTitle,
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: color),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        active ? (soon ? s.trialEndsSoon(date) : s.trialAllOn(date)) : s.trialEndedBody(paused),
                        style: const TextStyle(color: AppColors.muted, fontSize: 13.5),
                      ),
                    ],
                  ),
                ),
                if (!active)
                  IconButton(
                    tooltip: s.ok,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () async {
                      await prefs.setString(_key(company), endsIso);
                      if (mounted) setState(() {});
                    },
                  ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const Key('trialSeePlans'),
                onPressed: () => GoRouter.maybeOf(context)?.push(Routes.ownerBilling),
                child: Text(active ? s.seePlans : s.upgrade),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
