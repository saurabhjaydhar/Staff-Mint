import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/storage/providers.dart';
import '../../../core/theme/app_theme.dart';

/// First-time tips on Home: three short lines about the main controls
/// (Month, tapping a status, Ask Mint). Shown once; replayable from Help.
class HomeTips extends ConsumerStatefulWidget {
  const HomeTips({super.key});

  static const prefKey = 'sm_tips_home_v1';

  /// Help → "Show tips again".
  static Future<void> replay(WidgetRef ref) => ref.read(sharedPreferencesProvider).remove(prefKey);

  @override
  ConsumerState<HomeTips> createState() => _HomeTipsState();
}

class _HomeTipsState extends ConsumerState<HomeTips> {
  int _i = 0;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final prefs = ref.watch(sharedPreferencesProvider);
    if (prefs.getBool(HomeTips.prefKey) == true) return const SizedBox.shrink();
    final tips = [
      (Icons.calendar_month_rounded, s.tipMonth),
      (Icons.touch_app_rounded, s.tipStatus),
      (Icons.mic_rounded, s.tipMint),
    ];
    final last = _i == tips.length - 1;
    return Container(
      key: const Key('homeTips'),
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 6),
      decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(tips[_i].$1, color: AppColors.mintLight, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tips[_i].$2,
                  key: const Key('homeTipText'),
                  style: const TextStyle(color: Colors.white, fontSize: 14.5, height: 1.35),
                ),
              ),
            ],
          ),
          Row(
            children: [
              const SizedBox(width: 28),
              Text(
                s.tipCount(_i + 1, tips.length),
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12.5),
              ),
              const Spacer(),
              TextButton(
                key: const Key('homeTipNext'),
                style: TextButton.styleFrom(foregroundColor: AppColors.mintLight),
                onPressed: () async {
                  if (!last) return setState(() => _i++);
                  await prefs.setBool(HomeTips.prefKey, true);
                  if (mounted) setState(() {});
                },
                child: Text(last ? s.gotIt : s.next),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
