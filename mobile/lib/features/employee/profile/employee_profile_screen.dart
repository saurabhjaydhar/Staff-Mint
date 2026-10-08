import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/providers.dart';
import '../../../core/i18n/locale_provider.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/utils/phone.dart';
import '../../../core/widgets/common.dart';
import '../../auth/auth_controller.dart';
import '../punch/punch_providers.dart';

class EmployeeProfileScreen extends ConsumerWidget {
  const EmployeeProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final session = ref.watch(authControllerProvider);
    final lang = ref.watch(localeProvider);
    final emp = session.employee;
    final name = emp?.name ?? session.user?.name ?? '';
    return Scaffold(
      appBar: AppBar(title: Text(s.myProfile)),
      body: ListView(
        children: [
          const SizedBox(height: 16),
          Center(child: InitialsAvatar(name, radius: 44)),
          const SizedBox(height: 12),
          Center(child: Text(name, style: Theme.of(context).textTheme.titleLarge)),
          Center(child: Text(Phones.display(session.user?.phone ?? ''))),
          if (emp?.designation != null) Center(child: Text(emp!.designation!)),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                if (session.company != null)
                  ListTile(leading: const Icon(Icons.storefront_rounded), title: Text(session.company!.name)),
                ListTile(
                  leading: const Icon(Icons.translate_rounded),
                  title: Text(s.language),
                  trailing: LanguageToggle(
                    value: lang,
                    onChanged: (v) {
                      ref.read(localeProvider.notifier).setLanguage(v);
                      ref.read(meApiProvider).update(language: v).ignore();
                    },
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.logout_rounded, color: Colors.redAccent),
                  title: Text(s.logout, style: const TextStyle(color: Colors.redAccent)),
                  onTap: () async {
                    if (!await confirmDialog(context, title: s.logout, message: s.logoutConfirm)) return;
                    // Try to flush offline punches before the token goes away.
                    try {
                      await ref.read(punchSyncProvider.notifier).syncNow().timeout(const Duration(seconds: 8));
                    } catch (_) {}
                    await ref.read(authControllerProvider.notifier).logout();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
