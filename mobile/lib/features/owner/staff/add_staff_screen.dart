import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../more/shifts_screen.dart';
import '../../../core/api/providers.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/models/models.dart';
import '../../../core/router/routes.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/phone.dart';
import '../../../core/theme/app_theme.dart';
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
  bool _typing = false;

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
    final picked = await Navigator.of(
      context,
    ).push<List<PickedContact>>(MaterialPageRoute(builder: (_) => const ContactsPickerScreen()));
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
    return Scaffold(
      appBar: AppBar(
        title: Text(_typing ? s.newStaff : s.addStaff),
        leading: _typing ? BackButton(onPressed: () => setState(() => _typing = false)) : null,
      ),
      body: _typing ? _formView(s) : _chooseView(s),
    );
  }

  /// Three clear ways to add staff, and what happens after.
  Widget _chooseView(S s) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
    children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(s.chooseAWay, style: const TextStyle(color: AppColors.muted)),
      ),
      _WayCard(
        key: const Key('wayContacts'),
        emoji: '📇',
        title: s.pickFromContacts,
        hint: s.wayContactsHint,
        button: s.openScreen,
        primary: true,
        onTap: _busy ? null : _fromContacts,
      ),
      _WayCard(
        key: const Key('wayType'),
        emoji: '✍️',
        title: s.wayType,
        hint: s.wayTypeHint,
        button: s.wayTypeButton,
        onTap: () => setState(() => _typing = true),
      ),
      _WayCard(
        key: const Key('wayExcel'),
        emoji: '📊',
        title: s.wayExcel,
        hint: s.wayExcelHint,
        button: s.sendLink,
        onTap: () => openUrl(context, 'https://wa.me/?text=${Uri.encodeComponent(s.importLinkText)}'),
      ),
      const SizedBox(height: 8),
      Container(
        key: const Key('whatHappensNext'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.mintFaint, borderRadius: AppTheme.radius),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.whatHappensNext, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            for (final line in [s.next1, s.next2, s.next3])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(Icons.check_rounded, size: 18, color: AppColors.mint),
                    ),
                    const SizedBox(width: 6),
                    Expanded(child: Text(line, style: const TextStyle(height: 1.35))),
                  ],
                ),
              ),
          ],
        ),
      ),
    ],
  );

  Widget _formView(S s) {
    final joining = _joining ?? DateTime.now();
    final isToday = Dates.toApiDate(joining) == Dates.toApiDate(DateTime.now());
    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
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
          Text(s.howSalaryPaid, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'monthly', label: Text(s.everyMonth)),
              ButtonSegment(value: 'daily', label: Text(s.everyDay)),
            ],
            selected: {_wageType},
            onSelectionChanged: (v) => setState(() => _wageType = v.first),
          ),
          const SizedBox(height: 12),
          AmountField(controller: _rate, label: _wageType == 'daily' ? s.dailyWage : s.monthlySalary),
          const SizedBox(height: 12),
          ShiftPicker(key: const Key('shiftPicker'), value: _shiftId, onChanged: (v) => setState(() => _shiftId = v)),
          const SizedBox(height: 12),
          TextFormField(
            controller: _designation,
            decoration: InputDecoration(labelText: '${s.designation} (${s.optional})', hintText: s.designationHint),
          ),
          const SizedBox(height: 8),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                s.joiningLine(isToday ? s.today.toLowerCase() : Dates.pretty(joining, s.languageCode)),
                style: const TextStyle(color: AppColors.muted),
              ),
              TextButton(
                key: const Key('changeJoining'),
                onPressed: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: joining,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (d != null) setState(() => _joining = d);
                },
                child: Text(s.changeLink),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('addAndInvite'),
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                  )
                : Text(s.addAndInvite),
          ),
        ],
      ),
    );
  }
}

class _WayCard extends StatelessWidget {
  const _WayCard({
    super.key,
    required this.emoji,
    required this.title,
    required this.hint,
    required this.button,
    required this.onTap,
    this.primary = false,
  });
  final String emoji;
  final String title;
  final String hint;
  final String button;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: InkWell(
      borderRadius: AppTheme.radius,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 2),
                  Text(hint, style: const TextStyle(color: AppColors.muted, fontSize: 13.5, height: 1.3)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            primary
                ? FilledButton(onPressed: onTap, child: Text(button))
                : OutlinedButton(onPressed: onTap, child: Text(button)),
          ],
        ),
      ),
    ),
  );
}
