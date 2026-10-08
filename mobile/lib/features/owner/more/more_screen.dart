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
      leading: Icon(icon, size: 28),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: trailing ?? const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );

    return Scaffold(
      appBar: AppBar(title: Text(s.moreTitle)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          Card(
            margin: const EdgeInsets.all(16),
            child: ListTile(
              leading: InitialsAvatar(session.company?.name ?? s.appName),
              title: Text(session.company?.name ?? s.appName, style: Theme.of(context).textTheme.titleMedium),
              subtitle: Text('${session.user?.name ?? ''} · ${session.user?.phone ?? ''}'),
            ),
          ),
          Card(
            child: Column(
              children: [
                tile(Icons.beach_access_rounded, s.leaveRequests, () => context.push(Routes.ownerLeaves)),
                tile(Icons.description_rounded, s.reports, () => context.push(Routes.ownerReports)),
                if (isOwner) tile(Icons.settings_rounded, s.settings, () => context.push(Routes.ownerSettings)),
                if (isOwner) tile(Icons.workspace_premium_rounded, s.billing, () => context.push(Routes.ownerBilling)),
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
                  leading: const Icon(Icons.translate_rounded, size: 28),
                  title: Text(s.language),
                  trailing: LanguageToggle(
                    value: lang,
                    onChanged: (v) {
                      ref.read(localeProvider.notifier).setLanguage(v);
                      ref.read(meApiProvider).update(language: v).ignore();
                    },
                  ),
                ),
                tile(Icons.help_outline_rounded, s.help, () => context.push(Routes.ownerHelp)),
                ListTile(
                  leading: const Icon(Icons.logout_rounded, size: 28, color: Colors.redAccent),
                  title: Text(s.logout, style: const TextStyle(color: Colors.redAccent)),
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
    );
  }
}
