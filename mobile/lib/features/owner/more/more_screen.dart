import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/api/providers.dart';
import '../../../core/i18n/locale_provider.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/models/models.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/phone.dart';
import '../../../core/widgets/bilingual.dart';
import '../../../core/widgets/common.dart';
import '../../auth/auth_controller.dart';

class MoreScreen extends ConsumerStatefulWidget {
  const MoreScreen({super.key});

  @override
  ConsumerState<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends ConsumerState<MoreScreen> {
  bool _exporting = false;

  Future<void> _export() async {
    setState(() => _exporting = true);
    final s = context.s;
    try {
      final res = await ref.read(reportsApiProvider).export();
      if (!mounted) return;
      if (res.url != null) {
        await openUrl(context, res.url!);
      } else if (res.bytes != null) {
        final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/staffmint-export-${DateTime.now().millisecondsSinceEpoch}.zip');
        await file.writeAsBytes(res.bytes!);
        if (mounted) showSnack(context, s.exportSaved(file.path));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final session = ref.watch(authControllerProvider);
    final lang = ref.watch(localeProvider);
    final isOwner = session.user?.role == UserRole.owner;

    Widget tile(IconData icon, String title, VoidCallback onTap, {String? subtitle, Widget? trailing}) => ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: AppColors.mintLight, borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: AppColors.mintDark, size: 22),
      ),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: trailing ?? const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            ScreenHeader(subtitle: s.appName, title: s.moreTitle),
            Container(
              key: const Key('moreProfileCard'),
              margin: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(18)),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => context.push(Routes.ownerProfile),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      InitialsAvatar(
                        session.user?.name.isNotEmpty == true
                            ? session.user!.name
                            : (session.company?.name ?? s.appName),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              session.company?.name ?? s.appName,
                              style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800),
                            ),
                            Text(
                              [
                                session.user?.name ?? '',
                                Phones.display(session.user?.phone ?? ''),
                              ].where((t) => t.isNotEmpty).join(' · '),
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 13.5),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: Colors.white70),
                    ],
                  ),
                ),
              ),
            ),
            Card(
              child: Column(
                children: [
                  tile(Icons.beach_access_rounded, s.leaveRequests, () => context.push(Routes.ownerLeaves)),
                  tile(Icons.description_rounded, s.reports, () => context.push(Routes.ownerReports)),
                  if (isOwner) tile(Icons.settings_rounded, s.settings, () => context.push(Routes.ownerSettings)),
                  if (isOwner)
                    tile(Icons.workspace_premium_rounded, s.billing, () => context.push(Routes.ownerBilling)),
                  tile(Icons.history_rounded, s.auditLog, () => context.push(Routes.ownerAudit)),
                  if (isOwner)
                    tile(
                      Icons.download_rounded,
                      s.exportData,
                      _exporting ? () {} : _export,
                      subtitle: s.exportHint,
                      trailing: _exporting
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                          : null,
                    ),
                ],
              ),
            ),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: AppColors.mintLight, borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.translate_rounded, color: AppColors.mintDark, size: 22),
                    ),
                    title: Text(s.language),
                    trailing: LanguageToggle(value: lang, onChanged: (v) => setAppLanguage(ref, v)),
                  ),
                  tile(Icons.help_outline_rounded, s.help, () => context.push(Routes.ownerHelp)),
                  ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: AppColors.redLight, borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.logout_rounded, color: AppColors.red, size: 22),
                    ),
                    title: Text(s.logout, style: const TextStyle(color: AppColors.red)),
                    onTap: () async {
                      if (await confirmDialog(context, title: s.logout, message: s.logoutConfirm)) {
                        await ref.read(authControllerProvider.notifier).logout();
                      }
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
