import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/providers.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/models/models.dart';
import '../../profile/profile_sheets.dart';

/// Owner-only card: what this person's salary slip shows besides name and phone.
class SlipDetailsCard extends StatelessWidget {
  const SlipDetailsCard({super.key, required this.details, required this.onEdit});
  final EmployeeStatutory? details;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final d = details;
    final parts = [
      if (d?.employeeCode != null) '${s.employeeCodeLabel}: ${d!.employeeCode}',
      if (d?.uan != null) 'UAN: ${d!.uan}',
      if (d?.esicNumber != null) 'ESIC: ${d!.esicNumber}',
      if (d?.panMasked != null) 'PAN: ${d!.panMasked}',
      if (d?.pfExempt ?? false) s.pfExemptLabel,
      if (d?.esiExempt ?? false) s.esiExemptLabel,
    ];
    return Card(
      child: ListTile(
        key: const Key('staffSlipDetails'),
        leading: const Icon(Icons.badge_rounded),
        title: Text(parts.isEmpty ? s.slipDetailsHint : parts.join('\n')),
        trailing: const Icon(Icons.edit_rounded),
        onTap: onEdit,
      ),
    );
  }
}

class SlipDetailsSheet extends ConsumerStatefulWidget {
  const SlipDetailsSheet({super.key, required this.employeeId, this.initial});
  final String employeeId;
  final EmployeeStatutory? initial;

  @override
  ConsumerState<SlipDetailsSheet> createState() => _SlipDetailsSheetState();
}

class _SlipDetailsSheetState extends ConsumerState<SlipDetailsSheet> {
  late final _code = TextEditingController(text: widget.initial?.employeeCode ?? '');
  late final _uan = TextEditingController(text: widget.initial?.uan ?? '');
  late final _esic = TextEditingController(text: widget.initial?.esicNumber ?? '');
  final _pan = TextEditingController();
  late bool _pfExempt = widget.initial?.pfExempt ?? false;
  late bool _esiExempt = widget.initial?.esiExempt ?? false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_code, _uan, _esic, _pan]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(employeesApiProvider).updateStatutory(widget.employeeId, {
        'employeeCode': _code.text.trim().isEmpty ? null : _code.text.trim(),
        'uan': _uan.text.trim().isEmpty ? null : _uan.text.trim(),
        'esicNumber': _esic.text.trim().isEmpty ? null : _esic.text.trim(),
        // PAN only comes back masked, so it is sent only when typed again.
        if (_pan.text.trim().isNotEmpty) 'pan': _pan.text.trim(),
        'pfExempt': _pfExempt,
        'esiExempt': _esiExempt,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = apiFieldError(context, e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(s.slipDetailsBi.text, style: Theme.of(context).textTheme.titleLarge),
        if (s.slipDetailsBi.hint != null) Text(s.slipDetailsBi.hint!),
        const SizedBox(height: 4),
        Text(s.slipDetailsHint, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 16),
        TextField(
          key: const Key('slipCode'),
          controller: _code,
          decoration: InputDecoration(labelText: s.employeeCodeLabel),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('slipUan'),
          controller: _uan,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: s.uanLabel),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('slipEsic'),
          controller: _esic,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: s.esicLabel),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('slipPan'),
          controller: _pan,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(labelText: s.panLabel, hintText: widget.initial?.panMasked),
        ),
        SwitchListTile(
          key: const Key('slipPfExempt'),
          contentPadding: EdgeInsets.zero,
          title: Text(s.pfExemptLabel),
          value: _pfExempt,
          onChanged: (v) => setState(() => _pfExempt = v),
        ),
        SwitchListTile(
          key: const Key('slipEsiExempt'),
          contentPadding: EdgeInsets.zero,
          title: Text(s.esiExemptLabel),
          value: _esiExempt,
          onChanged: (v) => setState(() => _esiExempt = v),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        FilledButton(key: const Key('slipSave'), onPressed: _busy ? null : _save, child: Text(s.save)),
      ],
    );
  }
}
