import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/providers.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/models/models.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/json.dart';
import '../../../core/widgets/common.dart';
import '../../auth/auth_controller.dart';
import '../../setup/setup_screen.dart' show businessTypes;
import '../providers/owner_providers.dart';

/// Business details & branches: name and type, branches, PF/ESI/PT, who can
/// open the business, messages, and closing the business. Shop rules live on
/// their own small pages (timings, attendance, salary, check-in safety).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final company = ref.watch(companyProvider);
    return Scaffold(
      appBar: AppBar(title: Text(s.businessDetailsTitle)),
      body: AsyncBody<Company>(
        value: company,
        onRetry: () => ref.invalidate(companyProvider),
        data: (c) => _SettingsForm(company: c),
      ),
    );
  }
}

class _SettingsForm extends ConsumerStatefulWidget {
  const _SettingsForm({required this.company});
  final Company company;

  @override
  ConsumerState<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends ConsumerState<_SettingsForm> {
  late final Json _settings = widget.company.settings.toJson();
  late final _name = TextEditingController(text: widget.company.name);
  late String _type = businessTypes.contains(widget.company.businessType) ? widget.company.businessType : 'other';
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// The only settings edited here; shop rules have their own pages.
  static const _keys = ['whatsappAlerts', 'exStaffPayslips'];

  void _set(String key, Object value) => setState(() => _settings[key] = value);

  Future<void> _save() async {
    final s = context.s;
    setState(() => _busy = true);
    final ok = await runGuarded(context, () async {
      final api = ref.read(companyApiProvider);
      if (_name.text.trim() != widget.company.name || _type != widget.company.businessType) {
        await api.update(name: _name.text.trim(), businessType: _type);
      }
      await api.updateSettings({for (final k in _keys) k: _settings[k]});
    }, success: s.settingsSaved);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      ref.invalidate(companyProvider);
      ref.invalidate(rulesProvider);
      ref.read(authControllerProvider.notifier).refreshMe().ignore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final rules = ref.watch(rulesProvider);
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        SectionHeader(s.companySettings),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _name,
                  decoration: InputDecoration(labelText: s.businessName),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _type,
                  decoration: InputDecoration(labelText: s.businessType),
                  items: [
                    for (final t in businessTypes) DropdownMenuItem(value: t, child: Text(s.businessTypeLabel(t))),
                  ],
                  onChanged: (v) => setState(() => _type = v ?? _type),
                ),
              ],
            ),
          ),
        ),
        Card(
          child: Column(
            children: [
              for (final (key, label) in [('whatsappAlerts', s.whatsappAlerts), ('exStaffPayslips', s.exStaffPayslips)])
                SwitchListTile(value: _settings[key] == true, title: Text(label), onChanged: (v) => _set(key, v)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(onPressed: _busy ? null : _save, child: Text(s.save)),
        ),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.location_on_rounded),
                title: Text(s.geofence),
                subtitle: Text(s.branches),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(Routes.ownerBranches),
              ),
              ListTile(
                key: const Key('settingsTeam'),
                leading: const Icon(Icons.key_rounded),
                title: Text(s.teamAccess),
                subtitle: Text(s.teamAccessHint),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(Routes.ownerTeam),
              ),
              ListTile(
                key: const Key('settingsStatutory'),
                leading: const Icon(Icons.account_balance_rounded),
                title: Text(s.statutoryBi.text),
                subtitle: Text(s.statutoryHint),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(Routes.ownerStatutory),
              ),
            ],
          ),
        ),
        SectionHeader(s.rulesInPlainWords),
        rules.when(
          loading: () => const LoadingView(),
          error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(rulesProvider)),
          data: (list) => Card(
            child: Column(
              children: [for (final r in list) ListTile(leading: const Icon(Icons.rule_rounded), title: Text(r.text))],
            ),
          ),
        ),
        SectionHeader(s.dangerZone),
        Card(
          child: ListTile(
            key: const Key('closeBusiness'),
            leading: const Icon(Icons.store_mall_directory_outlined, color: AppColors.red),
            title: Text(
              s.closeBusiness,
              style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w700),
            ),
            subtitle: Text(s.closeBusinessHint),
            onTap: () => showCloseBusinessDialog(context, ref),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// Type the business name to confirm; the phone then moves to the owner's next account.
Future<void> showCloseBusinessDialog(BuildContext context, WidgetRef ref) async {
  final s = context.s;
  final name = ref.read(authControllerProvider).company?.name ?? '';
  final ctrl = TextEditingController();
  final ok = await showDialogWithControllers<bool>(
    context,
    [ctrl],
    (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(s.closeBusiness),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.closeBusinessHint),
            const SizedBox(height: 14),
            TextField(
              key: const Key('closeConfirmName'),
              controller: ctrl,
              autofocus: true,
              decoration: InputDecoration(labelText: s.typeNameToConfirm(name)),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: ctrl.text.trim().toLowerCase() == name.trim().toLowerCase() && name.isNotEmpty
                ? () => Navigator.pop(ctx, true)
                : null,
            child: Text(s.closeForever),
          ),
        ],
      ),
    ),
  );
  final typed = ctrl.text;
  if (ok != true || !context.mounted) return;
  try {
    await ref.read(authControllerProvider.notifier).closeBusiness(typed);
    if (context.mounted) showSnack(context, s.businessClosed(name));
  } on PendingPunchesException catch (e) {
    if (context.mounted) showSnack(context, s.pendingPunchesBlock(e.count), error: true);
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}
