import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/providers.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/models/models.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/pickers.dart';
import '../providers/owner_providers.dart';

/// Dropdown of active staff.
class EmployeeDropdown extends ConsumerWidget {
  const EmployeeDropdown({super.key, required this.value, required this.onChanged});
  final String? value;
  final ValueChanged<Employee?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final list = ref.watch(activeEmployeesProvider);
    return list.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Text(errorMessage(context, e)),
      data: (emps) => DropdownButtonFormField<String>(
        initialValue: emps.any((e) => e.id == value) ? value : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: s.selectEmployee),
        items: [
          for (final e in emps)
            DropdownMenuItem(
              value: e.id,
              child: Text(e.name, overflow: TextOverflow.ellipsis),
            ),
        ],
        validator: (v) => v == null ? s.required : null,
        onChanged: (id) => onChanged(emps.where((e) => e.id == id).firstOrNull),
      ),
    );
  }
}

Future<T?> _sheet<T>(BuildContext context, Widget child) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (ctx) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
    child: child,
  ),
);

/// Returns true when an advance was recorded.
Future<bool> showAddAdvanceSheet(BuildContext context, WidgetRef ref, {Employee? employee}) async {
  final result = await _sheet<bool>(context, _AdvanceForm(employee: employee));
  return result ?? false;
}

class _AdvanceForm extends ConsumerStatefulWidget {
  const _AdvanceForm({this.employee});
  final Employee? employee;

  @override
  ConsumerState<_AdvanceForm> createState() => _AdvanceFormState();
}

class _AdvanceFormState extends ConsumerState<_AdvanceForm> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  final _installments = TextEditingController(text: '1');
  String? _employeeId;
  DateTime _date = DateTime.now();
  String _mode = 'full_next';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _employeeId = widget.employee?.id;
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    _installments.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false) || _employeeId == null) return;
    setState(() => _busy = true);
    final s = context.s;
    final ok = await runGuarded(context, () async {
      await ref
          .read(moneyApiProvider)
          .addAdvance(
            employeeId: _employeeId!,
            amountPaise: Money.parseRupees(_amount.text)!,
            date: Dates.toApiDate(_date),
            mode: _mode,
            installments: _mode == 'installments' ? int.tryParse(_installments.text) ?? 1 : null,
            note: _note.text.trim(),
          );
    }, success: s.advanceAdded);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      invalidateMoney(ref);
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Form(
      key: _form,
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        children: [
          Text(s.addAdvance, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          if (widget.employee == null) ...[
            EmployeeDropdown(value: _employeeId, onChanged: (e) => setState(() => _employeeId = e?.id)),
            const SizedBox(height: 12),
          ] else
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: InitialsAvatar(widget.employee!.name),
              title: Text(widget.employee!.name),
            ),
          AmountField(controller: _amount, autofocus: widget.employee != null),
          const SizedBox(height: 12),
          DateField(label: s.date, value: _date, onChanged: (d) => setState(() => _date = d), lastDate: DateTime.now()),
          const SizedBox(height: 12),
          Text(s.advanceMode, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'full_next', label: Text(s.modeFullNext)),
              ButtonSegment(value: 'installments', label: Text(s.modeInstallments)),
            ],
            selected: {_mode},
            onSelectionChanged: (v) => setState(() => _mode = v.first),
          ),
          if (_mode == 'installments') ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _installments,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: s.installments),
              validator: (v) => (int.tryParse(v ?? '') ?? 0) < 1 ? s.required : null,
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            decoration: InputDecoration(labelText: '${s.note} (${s.optional})'),
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: _busy ? null : _submit, child: Text(s.save)),
        ],
      ),
    );
  }
}

/// Returns true when a bonus/deduction was added.
Future<bool> showAddAdjustmentSheet(
  BuildContext context,
  WidgetRef ref, {
  required String month,
  Employee? employee,
}) async {
  final result = await _sheet<bool>(context, _AdjustmentForm(month: month, employee: employee));
  return result ?? false;
}

class _AdjustmentForm extends ConsumerStatefulWidget {
  const _AdjustmentForm({required this.month, this.employee});
  final String month;
  final Employee? employee;

  @override
  ConsumerState<_AdjustmentForm> createState() => _AdjustmentFormState();
}

class _AdjustmentFormState extends ConsumerState<_AdjustmentForm> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String? _employeeId;
  String _type = 'bonus';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _employeeId = widget.employee?.id;
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false) || _employeeId == null) return;
    setState(() => _busy = true);
    final s = context.s;
    final ok = await runGuarded(context, () async {
      await ref
          .read(moneyApiProvider)
          .addAdjustment(
            employeeId: _employeeId!,
            month: widget.month,
            type: _type,
            amountPaise: Money.parseRupees(_amount.text)!,
            note: _note.text.trim(),
          );
    }, success: s.saved);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      invalidateMoney(ref);
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Form(
      key: _form,
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        children: [
          Text(s.addAdjustment, style: Theme.of(context).textTheme.titleLarge),
          Text(Dates.monthTitle(Dates.parseMonth(widget.month), s.languageCode)),
          const SizedBox(height: 16),
          if (widget.employee == null) ...[
            EmployeeDropdown(value: _employeeId, onChanged: (e) => setState(() => _employeeId = e?.id)),
            const SizedBox(height: 12),
          ],
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'bonus', label: Text(s.bonus), icon: const Icon(Icons.add_circle_outline)),
              ButtonSegment(
                value: 'deduction',
                label: Text(s.deduction),
                icon: const Icon(Icons.remove_circle_outline),
              ),
            ],
            selected: {_type},
            onSelectionChanged: (v) => setState(() => _type = v.first),
          ),
          const SizedBox(height: 12),
          AmountField(controller: _amount),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            decoration: InputDecoration(labelText: '${s.note} (${s.optional})'),
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: _busy ? null : _submit, child: Text(s.save)),
        ],
      ),
    );
  }
}
