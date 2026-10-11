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
import '../../../core/widgets/pickers.dart';
import '../../auth/auth_controller.dart';
import '../../setup/setup_screen.dart' show businessTypes;
import '../providers/owner_providers.dart';

/// Company settings: every default from setup can be changed here (PRD F1).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final company = ref.watch(companyProvider);
    return Scaffold(
      appBar: AppBar(title: Text(s.settings)),
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
  late final _grace = TextEditingController(text: '${widget.company.settings.graceMinutes}');
  late final _halfDay = TextEditingController(text: '${widget.company.settings.halfDayHours}');
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _grace.dispose();
    _halfDay.dispose();
    super.dispose();
  }

  void _set(String key, Object value) => setState(() => _settings[key] = value);

  Future<void> _save() async {
    final s = context.s;
    _settings['graceMinutes'] = int.tryParse(_grace.text) ?? widget.company.settings.graceMinutes;
    _settings['halfDayHours'] = num.tryParse(_halfDay.text) ?? widget.company.settings.halfDayHours;
    setState(() => _busy = true);
    final ok = await runGuarded(context, () async {
      final api = ref.read(companyApiProvider);
      if (_name.text.trim() != widget.company.name || _type != widget.company.businessType) {
        await api.update(name: _name.text.trim(), businessType: _type);
      }
      await api.updateSettings(_settings);
    }, success: s.settingsSaved);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      ref.invalidate(companyProvider);
      ref.invalidate(rulesProvider);
      ref.read(authControllerProvider.notifier).refreshMe().ignore();
    }
  }

  Widget _radioGroup(String title, String key, List<(String, String)> options, {String? help}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(title, style: Theme.of(context).textTheme.titleSmall),
        ),
        if (help != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(help, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
          ),
        RadioGroup<String>(
          groupValue: _settings[key]?.toString(),
          onChanged: (v) {
            if (v != null) _set(key, v);
          },
          child: Column(
            children: [
              for (final (value, label) in options)
                RadioListTile<String>(dense: true, value: value, title: Text(label)),
            ],
          ),
        ),
      ],
    );
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
                const SizedBox(height: 12),
                TextField(
                  controller: _grace,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: s.graceMinutes),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _halfDay,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: s.halfDayHours),
                ),
                const SizedBox(height: 12),
                TimeField(
                  label: s.digestTime,
                  value: _settings['digestTime']?.toString() ?? '09:30',
                  onChanged: (v) => _set('digestTime', v),
                ),
              ],
            ),
          ),
        ),
        Card(
          child: Column(
            children: [
              _radioGroup(s.monthDivisor, 'monthDivisor', [
                ('days_in_month', s.divisorDaysInMonth),
                ('30', s.divisor30),
                ('26', s.divisor26),
              ]),
              _radioGroup(s.missingCheckoutPolicy, 'missingCheckoutPolicy', [
                ('half_day', s.policyHalfDay),
                ('present', s.policyPresent),
                ('flag', s.policyFlag),
              ]),
              _radioGroup(s.outsideGeofencePolicy, 'outsideGeofencePolicy', [
                ('block', s.policyBlock),
                ('request_approval', s.policyRequestApproval),
              ]),
              _radioGroup(s.phoneLockPolicy, 'phoneLockPolicy', [
                ('off', s.lockPolicyOff),
                ('recommended', s.lockPolicyRecommended),
                ('required', s.lockPolicyRequired),
              ], help: s.phoneLockPolicyHelp),
              _radioGroup(s.faceMatchPolicy, 'faceMatchPolicy', [
                ('off', s.faceMatchOff),
                ('review', s.faceMatchReview),
              ], help: s.faceMatchPolicyHelp),
            ],
          ),
        ),
        Card(
          child: Column(
            children: [
              for (final (key, label) in [
                ('weekOffsPaid', s.weekOffsPaid),
                ('holidaysPaid', s.holidaysPaid),
                ('sickLeavePaid', s.sickLeavePaid),
                ('selfieRequired', s.selfieRequired),
                ('roundToRupee', s.roundToRupee),
                ('whatsappAlerts', s.whatsappAlerts),
                ('exStaffPayslips', s.exStaffPayslips),
              ])
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
                leading: const Icon(Icons.schedule_rounded),
                title: Text(s.shifts),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(Routes.ownerShifts),
              ),
              ListTile(
                leading: const Icon(Icons.location_on_rounded),
                title: Text(s.geofence),
                subtitle: Text(s.branches),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(Routes.ownerBranches),
              ),
              ListTile(
                leading: const Icon(Icons.celebration_rounded),
                title: Text(s.holidays),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(Routes.ownerHolidays),
              ),
              ListTile(
                key: const Key('settingsOwners'),
                leading: const Icon(Icons.groups_rounded),
                title: Text(s.ownersBi.text),
                subtitle: Text(s.ownersHint),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(Routes.ownerOwners),
              ),
              ListTile(
                key: const Key('settingsAccountants'),
                leading: const Icon(Icons.calculate_rounded),
                title: Text(s.accountantsBi.text),
                subtitle: Text(s.accountantsHint),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(Routes.ownerAccountants),
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
