import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/bilingual.dart';
import '../../auth/auth_controller.dart';

/// Business name once (with "Switch ▾" only for people with more than one
/// business), the day in words underneath, and the language pill.
class HomeHeader extends ConsumerWidget {
  const HomeHeader({super.key, required this.subtitle});
  final String subtitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final session = ref.watch(authControllerProvider);
    final name = session.activeMembership?.companyName ?? session.company?.name ?? '';
    final many = session.hasManyAccounts;
    final title = Text(
      name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, height: 1.15),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 8, 2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (many)
                  InkWell(
                    key: const Key('businessSwitch'),
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => context.push(Routes.accounts),
                    child: Row(
                      children: [
                        Flexible(child: title),
                        Text(
                          ' · ${s.switchBusiness}',
                          style: const TextStyle(color: AppColors.mintDark, fontWeight: FontWeight.w700),
                        ),
                        const Icon(Icons.arrow_drop_down_rounded, color: AppColors.mintDark),
                      ],
                    ),
                  )
                else
                  title,
                Text(
                  subtitle,
                  key: const Key('homeSubtitle'),
                  style: const TextStyle(fontSize: 14, color: AppColors.muted),
                ),
              ],
            ),
          ),
          const LangPill(),
        ],
      ),
    );
  }
}

/// "📋 Day | 📅 Month" in words, replacing the unlabelled grid icon.
class DayMonthSwitch extends StatelessWidget {
  const DayMonthSwitch({super.key, required this.month, required this.onChanged});
  final bool month;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 2),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<bool>(
          key: const Key('dayMonthSwitch'),
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: false,
              icon: const Icon(Icons.view_agenda_outlined, size: 18),
              label: Text(s.dayTab, key: const Key('dayTab')),
            ),
            ButtonSegment(
              value: true,
              icon: const Icon(Icons.calendar_month_rounded, size: 18),
              label: Text(s.monthTab, key: const Key('monthTab')),
            ),
          ],
          selected: {month},
          onSelectionChanged: (v) => onChanged(v.first),
        ),
      ),
    );
  }
}
