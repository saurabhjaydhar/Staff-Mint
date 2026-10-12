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
  late String _name = widget.company.name;
  late String _type = businessTypes.contains(widget.company.businessType) ? widget.company.businessType : 'other';

  void _refresh() {
    ref.invalidate(companyProvider);
    ref.invalidate(rulesProvider);
    ref.read(authControllerProvider.notifier).refreshMe().ignore();
  }

  /// Every change saves at once, with a small "Saved".
  Future<void> _setSwitch(String key, bool value) async {
    final before = _settings[key];
    setState(() => _settings[key] = value);
    final ok = await runGuarded(
      context,
      () => ref.read(companyApiProvider).updateSettings({key: value}),
      success: context.s.saved,
    );
    if (!mounted) return;
    if (ok) {
      _refresh();
    } else {
      setState(() => _settings[key] = before);
    }
  }

  Future<void> _saveBusiness({String? name, String? type}) async {
    final ok = await runGuarded(
      context,
      () => ref.read(companyApiProvider).update(name: name ?? _name, businessType: type ?? _type),
      success: context.s.saved,
    );
    if (!mounted || !ok) return;
    setState(() {
      _name = name ?? _name;
      _type = type ?? _type;
    });
    _refresh();
  }

  Future<void> _editName() async {
    final s = context.s;
    final ctrl = TextEditingController(text: _name);
    final ok = await showDialogWithControllers<bool>(
      context,
      [ctrl],
      (ctx) => AlertDialog(
        title: Text(s.businessName),
        content: TextField(controller: ctrl, autofocus: true, textCapitalization: TextCapitalization.words),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.save)),
        ],
      ),
    );
    final name = ctrl.text.trim();
    if (ok == true && name.isNotEmpty && name != _name) await _saveBusiness(name: name);
  }

  Future<void> _editType() async {
    final s = context.s;
    final type = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: RadioGroup<String>(
          groupValue: _type,
          onChanged: (v) => Navigator.pop(ctx, v),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final t in businessTypes) RadioListTile<String>(value: t, title: Text(s.businessTypeLabel(t))),
            ],
          ),
        ),
      ),
    );
    if (type != null && type != _type) await _saveBusiness(type: type);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              ListTile(
                key: const Key('businessName'),
                title: Text(s.businessName, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                subtitle: Text(
                  _name,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.ink),
                ),
                trailing: const Icon(Icons.edit_rounded, size: 20),
                onTap: _editName,
              ),
              ListTile(
                key: const Key('businessType'),
                title: Text(s.businessType, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                subtitle: Text(
                  s.businessTypeLabel(_type),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.ink),
                ),
                trailing: const Icon(Icons.edit_rounded, size: 20),
                onTap: _editType,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
          child: Text(s.savesAtOnce, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
        ),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                key: const Key('whatsappAlerts'),
                value: _settings['whatsappAlerts'] == true,
                title: Text(s.alertsOnWhatsapp),
                subtitle: Text(s.alertsOnWhatsappHint),
                onChanged: (v) => _setSwitch('whatsappAlerts', v),
              ),
              SwitchListTile(
                key: const Key('exStaffPayslips'),
                value: _settings['exStaffPayslips'] == true,
                title: Text(s.oldStaffSlips),
                subtitle: Text(s.oldStaffSlipsHint),
                onChanged: (v) => _setSwitch('exStaffPayslips', v),
              ),
            ],
          ),
        ),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.location_on_rounded),
                title: Text(s.geofence),
                subtitle: Text(s.shopAreaHint),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(Routes.ownerBranches),
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
        const SizedBox(height: 8),
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
