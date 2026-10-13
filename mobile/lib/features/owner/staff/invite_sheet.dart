import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/providers.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/phone.dart';
import '../../../core/widgets/common.dart';
import '../providers/owner_providers.dart';

/// "Remind" for everyone who hasn't joined: sends the invite and shows, per person, what happened.
Future<void> remindNotJoined(BuildContext context, WidgetRef ref) async {
  RemindResult? r;
  final ok = await runGuarded(context, () async => r = await ref.read(accountsApiProvider).remindNotJoined());
  // Show the result before refreshing: the refresh rebuilds the list this button sits in.
  if (ok && r != null && context.mounted) await showInviteSheet(context, r!);
  ref.invalidate(dashboardProvider);
  ref.invalidate(employeesProvider);
}

/// "Remind" for one person.
Future<void> remindOne(BuildContext context, WidgetRef ref, Employee e) async {
  RemindResult? r;
  final ok = await runGuarded(context, () async => r = await ref.read(accountsApiProvider).inviteOne(e));
  if (ok && r != null && context.mounted) await showInviteSheet(context, r!);
  ref.invalidate(employeesProvider);
  ref.invalidate(employeeDetailProvider(e.id));
}

Future<void> showInviteSheet(BuildContext context, RemindResult r) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  backgroundColor: AppColors.paper,
  builder: (_) => _InviteSheet(result: r),
);

class _InviteSheet extends StatelessWidget {
  const _InviteSheet({required this.result});
  final RemindResult result;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final r = result;
    final helpNeeded = !r.whatsappConnected || r.failed > 0;
    return ListView(
      key: const Key('inviteSheet'),
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Text(s.inviteSheetTitle, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        if (r.people.isEmpty)
          Text(s.inviteEveryoneJoined, style: const TextStyle(color: AppColors.muted))
        else
          Container(
            key: const Key('inviteHelp'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: helpNeeded ? AppColors.amberLight : AppColors.mintFaint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              !r.whatsappConnected ? s.inviteNotConnected : (r.failed > 0 ? s.inviteSomeFailed : s.inviteOwnWhatsApp),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        const SizedBox(height: 8),
        for (final p in r.people)
          ListTile(
            key: Key('invitePerson_${p.phone}'),
            contentPadding: EdgeInsets.zero,
            title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
              [Phones.display(p.phone), if (r.whatsappConnected) s.inviteStatus(p.status)].join(' · '),
              style: TextStyle(color: p.status == 'failed' ? AppColors.red : AppColors.muted),
            ),
            trailing: FilledButton.tonalIcon(
              key: Key('inviteWa_${p.phone}'),
              onPressed: () {
                final digits = Phones.waDigits(p.phone);
                if (digits == null) return;
                openUrl(context, 'https://wa.me/$digits?text=${Uri.encodeComponent(p.shareText)}');
              },
              icon: const Icon(Icons.chat_rounded, size: 18),
              label: Text(s.whatsappShort),
            ),
          ),
      ],
    );
  }
}
