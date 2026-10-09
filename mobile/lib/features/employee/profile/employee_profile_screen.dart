import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/locale_provider.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/utils/phone.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/bilingual.dart';
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
      body: SafeArea(
        child: ListView(
          children: [
            ScreenHeader(subtitle: s.navProfileBi.joined, title: s.myProfile),
            const SizedBox(height: 16),
            Center(child: InitialsAvatar(name, radius: 44)),
            const SizedBox(height: 12),
            Center(child: Text(name, style: Theme.of(context).textTheme.titleLarge)),
            Center(
              child: Text(Phones.display(session.user?.phone ?? ''), style: const TextStyle(color: AppColors.muted)),
            ),
            if (emp?.designation != null)
              Center(
                child: Text(emp!.designation!, style: const TextStyle(color: AppColors.muted)),
              ),
            const SizedBox(height: 16),
            Card(
              child: Column(
                children: [
                  if (session.company != null)
                    ListTile(leading: const Icon(Icons.storefront_rounded), title: Text(session.company!.name)),
                  ListTile(
                    leading: const Icon(Icons.translate_rounded),
                    title: Text(s.language),
                    trailing: LanguageToggle(value: lang, onChanged: (v) => setAppLanguage(ref, v)),
                  ),
                  ListTile(
                    leading: const Icon(Icons.logout_rounded, color: AppColors.red),
                    title: Text(s.logout, style: const TextStyle(color: AppColors.red)),
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
      ),
    );
  }
}
