import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/providers.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/models/models.dart';
import '../../../core/router/routes.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/phone.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/pickers.dart';
import '../providers/owner_providers.dart';
import 'contacts_picker_screen.dart';

/// Add one staff member (full form) or many from contacts.
class AddStaffScreen extends ConsumerStatefulWidget {
  const AddStaffScreen({super.key});

  @override
  ConsumerState<AddStaffScreen> createState() => _AddStaffScreenState();
}

class _AddStaffScreenState extends ConsumerState<AddStaffScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _rate = TextEditingController();
  final _designation = TextEditingController();
  String _wageType = 'monthly';
  String? _shiftId;
  DateTime? _joining = DateTime.now();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _rate.dispose();
    _designation.dispose();
    super.dispose();
  }

  void _invalidate() {
    ref.invalidate(employeesProvider);
    ref.invalidate(activeEmployeesProvider);
    ref.invalidate(dashboardProvider);
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    final s = context.s;
    try {
      final e = await ref
          .read(employeesApiProvider)
          .create(
            NewEmployee(
              name: _name.text.trim(),
              phone: Phones.normalize(_phone.text)!,
              wageType: _wageType,
              ratePaise: Money.parseRupees(_rate.text),
              designation: _designation.text.trim(),
              shiftId: _shiftId,
              joiningDate: _joining == null ? null : Dates.toApiDate(_joining!),
            ),
          );
      _invalidate();
      if (!mounted) return;
      showSnack(context, s.staffSaved);
      context.pushReplacement(Routes.ownerStaffProfile(e.id));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _fromContacts() async {
    final picked = await Navigator.of(context)
        .push<List<PickedContact>>(MaterialPageRoute(builder: (_) => const ContactsPickerScreen()));
    if (picked == null || picked.isEmpty || !mounted) return;
    setState(() => _busy = true);
    final s = context.s;
    try {
      final res = await ref
          .read(employeesApiProvider)
          .bulkCreate(picked.map((c) => NewEmployee(name: c.name, phone: c.phone)).toList());
      _invalidate();
      if (!mounted) return;
      showSnack(
        context,
        [s.staffAdded(res.created.length), if (res.skipped.isNotEmpty) s.staffSkipped(res.skipped.length)].join(' · '),
      );
      context.pop();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final shifts = ref.watch(shiftsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(s.addStaff)),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            OutlinedButton.icon(
              onPressed: _busy ? null : _fromContacts,
              icon: const Icon(Icons.contacts_rounded),
              label: Text(s.pickFromContacts),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: s.name),
              validator: (v) => (v ?? '').trim().isEmpty ? s.required : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
              decoration: InputDecoration(labelText: s.phone, prefixText: '+91 '),
              validator: (v) => Phones.isValid(v ?? '') ? null : s.invalidPhone,
            ),
            const SizedBox(height: 16),
            Text(s.wageType, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'monthly', label: Text(s.wageMonthly)),
                ButtonSegment(value: 'daily', label: Text(s.wageDaily)),
              ],
              selected: {_wageType},
              onSelectionChanged: (v) => setState(() => _wageType = v.first),
            ),
            const SizedBox(height: 12),
            AmountField(controller: _rate, label: _wageType == 'daily' ? s.dailyWage : s.monthlySalary),
            const SizedBox(height: 12),
            TextFormField(
              controller: _designation,
              decoration: InputDecoration(labelText: '${s.designation} (${s.optional})', hintText: s.designationHint),
            ),
            const SizedBox(height: 12),
            shifts.maybeWhen(
              data: (list) => list.isEmpty
                  ? const SizedBox.shrink()
                  : DropdownButtonFormField<String?>(
                      initialValue: _shiftId,
                      decoration: InputDecoration(labelText: s.shift),
                      items: [
                        DropdownMenuItem(value: null, child: Text(s.defaultShift)),
                        for (final sh in list)
                          DropdownMenuItem(value: sh.id, child: Text('${sh.name} (${sh.start}–${sh.end})')),
                      ],
                      onChanged: (v) => setState(() => _shiftId = v),
                    ),
              orElse: () => const SizedBox.shrink(),
            ),
            const SizedBox(height: 12),
            DateField(label: s.joiningDate, value: _joining, onChanged: (d) => setState(() => _joining = d)),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : Text(s.save),
            ),
          ],
        ),
      ),
    );
  }
}
