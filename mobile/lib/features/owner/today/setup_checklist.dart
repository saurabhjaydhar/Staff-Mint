import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/providers.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/models/models.dart';
import '../../../core/router/routes.dart';
import '../../../core/storage/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../auth/auth_controller.dart';
import '../providers/owner_providers.dart';

/// "Let's get your shop running · 2 of 5": tells a new owner exactly what to
/// do next. Each step opens the right screen and ticks itself when done.
/// Goes away after the last step, or when hidden.
class SetupChecklistCard extends ConsumerStatefulWidget {
  const SetupChecklistCard({super.key, required this.setup});
  final HomeChecklist setup;

  @override
  ConsumerState<SetupChecklistCard> createState() => _SetupChecklistCardState();
}

class _SetupChecklistCardState extends ConsumerState<SetupChecklistCard> {
  String _key(String companyId) => 'sm_setup_hidden_$companyId';

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final c = widget.setup;
    final companyId = ref.watch(authControllerProvider.select((v) => v.company?.id)) ?? '';
    final prefs = ref.watch(sharedPreferencesProvider);
    if (c.complete || prefs.getBool(_key(companyId)) == true) return const SizedBox.shrink();
    final steps = <(bool, String, String?, VoidCallback?)>[
      (true, s.setupBusiness, null, null),
      (c.staffAdded, s.setupStaff, s.add, () => context.push(Routes.ownerStaffAdd)),
      (
        c.staffJoined,
        s.setupJoin,
        c.notJoined > 0 ? s.remind : null,
        c.notJoined > 0 ? () => remindNotJoined(context, ref) : null,
      ),
      (c.salarySet, s.setupSalary, s.open, () => context.go(Routes.ownerStaff)),
      (c.teamAdded, s.setupTeam, s.open, () => context.push(Routes.ownerOwners)),
    ];
    final next = steps.indexWhere((x) => !x.$1);
    return Container(
      key: const Key('setupChecklist'),
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 8),
      decoration: BoxDecoration(
        color: AppColors.mintFaint,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.mintLight, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(s.setupTitle, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ),
              Text(s.setupCount(c.done, HomeChecklist.total), style: const TextStyle(color: AppColors.muted)),
              IconButton(
                key: const Key('setupHide'),
                tooltip: s.hide,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: () async {
                  await prefs.setBool(_key(companyId), true);
                  if (mounted) setState(() {});
                },
              ),
            ],
          ),
          for (var i = 0; i < steps.length; i++)
            _Step(
              key: Key('setupStep_$i'),
              number: i + 1,
              done: steps[i].$1,
              current: i == next,
              label: steps[i].$2,
              action: steps[i].$1 ? null : steps[i].$3,
              onTap: steps[i].$1 ? null : steps[i].$4,
            ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    super.key,
    required this.number,
    required this.done,
    required this.current,
    required this.label,
    this.action,
    this.onTap,
  });
  final int number;
  final bool done;
  final bool current;
  final String label;
  final String? action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(10),
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Row(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: done ? AppColors.mint : (current ? AppColors.ink : AppColors.mutedLight),
            child: done
                ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                : Text(
                    '$number',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: current ? Colors.white : AppColors.muted,
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: current ? FontWeight.w800 : FontWeight.w600,
                color: done ? AppColors.muted : AppColors.ink,
                decoration: done ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          if (action != null && onTap != null) TextButton(onPressed: onTap, child: Text(action!)),
        ],
      ),
    ),
  );
}

/// "6 staff invited · 2 have joined · Remind": one tap re-sends the WhatsApp
/// invite to everyone who hasn't joined.
class InviteStatusBanner extends ConsumerWidget {
  const InviteStatusBanner({super.key, required this.setup});
  final HomeChecklist setup;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    if (setup.notJoined <= 0) return const SizedBox.shrink();
    return Container(
      key: const Key('inviteBanner'),
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(color: AppColors.amberLight, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          const Icon(Icons.mark_email_unread_outlined, color: AppColors.amberDark, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              s.invitedJoined(setup.staff, setup.joined),
              style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.amberDark),
            ),
          ),
          TextButton(
            key: const Key('remindInvites'),
            onPressed: () => remindNotJoined(context, ref),
            child: Text(s.remind),
          ),
        ],
      ),
    );
  }
}

Future<void> remindNotJoined(BuildContext context, WidgetRef ref) async {
  final s = context.s;
  try {
    final sent = await ref.read(accountsApiProvider).remindNotJoined();
    if (context.mounted) showSnack(context, s.remindSent(sent));
    ref.invalidate(dashboardProvider);
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}
