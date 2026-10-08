import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/providers.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/phone.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/pickers.dart';
import '../providers/owner_providers.dart';
import '../salary/money_dialogs.dart';
import '../salary/advances_view.dart';

class StaffProfileScreen extends ConsumerWidget {
  const StaffProfileScreen({super.key, required this.employeeId});
  final String employeeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final emp = ref.watch(employeeDetailProvider(employeeId));
    final shifts = ref.watch(shiftsProvider).value ?? const <Shift>[];

    void invalidate() {
      ref.invalidate(employeeDetailProvider(employeeId));
      ref.invalidate(employeesProvider);
      ref.invalidate(activeEmployeesProvider);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(emp.value?.name ?? s.staffTitle),
        actions: [
          if (emp.hasValue)
            IconButton(
              tooltip: s.editStaff,
              icon: const Icon(Icons.edit_rounded),
              onPressed: () async {
                final changed = await showModalBottomSheet<bool>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  showDragHandle: true,
                  builder: (_) => _EditStaffSheet(employee: emp.requireValue),
                );
                if (changed == true) invalidate();
              },
            ),
        ],
      ),
      body: AsyncBody<Employee>(
        value: emp,
        onRetry: () => ref.invalidate(employeeDetailProvider(employeeId)),
        data: (e) {
          final shift = shifts.where((x) => x.id == e.shiftId).firstOrNull;
          final lb = e.leaveBalance;
          return RefreshableList(
            onRefresh: () => ref.refresh(employeeDetailProvider(employeeId).future),
            children: [
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: InitialsAvatar(e.name, radius: 28),
                  title: Text(e.name, style: Theme.of(context).textTheme.titleLarge),
                  subtitle: Text(
                    [
                      if (e.designation != null && e.designation!.isNotEmpty) e.designation!,
                      Phones.display(e.phone),
                      if (!e.isActive) s.inactive,
                    ].join('\n'),
                  ),
                  isThreeLine: true,
                  trailing: IconButton.filledTonal(
                    tooltip: s.callStaff,
                    icon: const Icon(Icons.call_rounded),
                    onPressed: () => openUrl(context, 'tel:${e.phone}'),
                  ),
                ),
              ),
              SectionHeader(s.salary),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.currency_rupee_rounded),
                      title: Text(
                        e.ratePaise > 0
                            ? (e.isDaily ? s.perDay(Money.format(e.ratePaise)) : s.perMonth(Money.format(e.ratePaise)))
                            : '—',
                      ),
                      subtitle: Text(e.isDaily ? s.wageDaily : s.wageMonthly),
                    ),
                    ListTile(
                      leading: const Icon(Icons.schedule_rounded),
                      title: Text(
                        shift == null
                            ? s.defaultShift
                            : '${shift.name} · ${Dates.hhmmToDisplay(shift.start, s.languageCode)}–${Dates.hhmmToDisplay(shift.end, s.languageCode)}',
                      ),
                      subtitle: Text(s.shift),
                    ),
                    if (e.joiningDate != null)
                      ListTile(
                        leading: const Icon(Icons.event_rounded),
                        title: Text(Dates.prettyApiDate(e.joiningDate!, s.languageCode)),
                        subtitle: Text(s.joiningDate),
                      ),
                  ],
                ),
              ),
              SectionHeader(
                s.advances,
                trailing: TextButton.icon(
                  icon: const Icon(Icons.add),
                  label: Text(s.addAdvance),
                  onPressed: () async {
                    if (await showAddAdvanceSheet(context, ref, employee: e)) invalidate();
                  },
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.account_balance_wallet_rounded),
                  title: Text(
                    Money.format(e.advanceBalancePaise ?? 0),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
                  ),
                  subtitle: Text(s.advanceBalance),
                ),
              ),
              AdvancesList(employeeId: e.id, compact: true),
              SectionHeader(
                s.leaveBalance,
                trailing: TextButton(
                  onPressed: () async {
                    if (await _editLeaveBalance(context, ref, e)) invalidate();
                  },
                  child: Text(s.edit),
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.beach_access_rounded),
                  title: Text(lb == null ? '—' : s.leaveLeft(lb.paidLeft, lb.sickLeft)),
                  subtitle: lb == null ? null : Text('${s.paidLeaves}: ${lb.paid} · ${s.sickLeaves}: ${lb.sick}'),
                ),
              ),
              SectionHeader(s.device),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(e.hasDevice ? Icons.phone_android_rounded : Icons.phonelink_off_rounded),
                      title: Text(e.hasDevice ? s.deviceBound : s.deviceNotLinked),
                      trailing: e.hasDevice
                          ? TextButton(
                              onPressed: () async {
                                if (!await confirmDialog(
                                  context,
                                  title: s.resetDevice,
                                  message: s.resetDeviceConfirm,
                                )) {
                                  return;
                                }
                                if (!context.mounted) return;
                                if (await runGuarded(
                                  context,
                                  () => ref.read(employeesApiProvider).resetDevice(e.id),
                                  success: s.deviceReset,
                                )) {
                                  invalidate();
                                }
                              },
                              child: Text(s.resetDevice),
                            )
                          : null,
                    ),
                    ListTile(
                      leading: Icon(
                        e.locationConsent ? Icons.verified_user_rounded : Icons.privacy_tip_outlined,
                        color: e.locationConsent ? AppColors.mint : Colors.grey,
                      ),
                      title: Text(e.locationConsent ? s.consentGiven : s.consentPending),
                    ),
                  ],
                ),
              ),
              if (e.isActive)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.absent),
                    icon: const Icon(Icons.person_off_rounded),
                    label: Text(s.deactivate),
                    onPressed: () async {
                      if (!await confirmDialog(
                        context,
                        title: s.deactivate,
                        message: s.deactivateConfirm,
                        destructive: true,
                      )) {
                        return;
                      }
                      if (!context.mounted) return;
                      if (await runGuarded(
                        context,
                        () => ref.read(employeesApiProvider).deactivate(e.id),
                        success: s.deactivated,
                      )) {
                        invalidate();
                        ref.invalidate(dashboardProvider);
                      }
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<bool> _editLeaveBalance(BuildContext context, WidgetRef ref, Employee e) async {
    final s = context.s;
    final year = DateTime.now().year;
    final paid = TextEditingController(text: '${e.leaveBalance?.paid ?? 0}');
    final sick = TextEditingController(text: '${e.leaveBalance?.sick ?? 0}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${s.editLeaveBalance} · $year'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: paid,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: s.paidLeaves),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: sick,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: s.sickLeaves),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.save)),
        ],
      ),
    );
    if (ok != true || !context.mounted) return false;
    return runGuarded(
      context,
      () => ref
          .read(leaveApiProvider)
          .setBalance(e.id, year: year, paid: num.tryParse(paid.text) ?? 0, sick: num.tryParse(sick.text) ?? 0),
      success: s.saved,
    );
  }
}

class _EditStaffSheet extends ConsumerStatefulWidget {
  const _EditStaffSheet({required this.employee});
  final Employee employee;

  @override
  ConsumerState<_EditStaffSheet> createState() => _EditStaffSheetState();
}

class _EditStaffSheetState extends ConsumerState<_EditStaffSheet> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.employee.name);
  late final _designation = TextEditingController(text: widget.employee.designation ?? '');
  late final _rate = TextEditingController(
    text: widget.employee.ratePaise > 0 ? Money.plainRupees(widget.employee.ratePaise) : '',
  );
  late String _wageType = widget.employee.wageType;
  late String? _shiftId = widget.employee.shiftId;
  DateTime _effectiveFrom = DateTime(DateTime.now().year, DateTime.now().month);
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _designation.dispose();
    _rate.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final e = widget.employee;
    final rate = Money.parseRupees(_rate.text);
    final rateChanged = rate != null && (rate != e.ratePaise || _wageType != e.wageType);
    final body = <String, dynamic>{
      'name': _name.text.trim(),
      'designation': _designation.text.trim(),
      'wageType': _wageType,
      'ratePaise': ?rate,
      'shiftId': _shiftId,
      if (rateChanged) 'effectiveFrom': Dates.toApiDate(_effectiveFrom),
    };
    setState(() => _busy = true);
    final ok = await runGuarded(
      context,
      () => ref.read(employeesApiProvider).update(e.id, body),
      success: context.s.staffSaved,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final shifts = ref.watch(shiftsProvider).value ?? const <Shift>[];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Form(
        key: _form,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            Text(s.editStaff, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              decoration: InputDecoration(labelText: s.name),
              validator: (v) => (v ?? '').trim().isEmpty ? s.required : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _designation,
              decoration: InputDecoration(labelText: s.designation),
            ),
            const SizedBox(height: 12),
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
            DateField(
              label: s.effectiveFrom,
              value: _effectiveFrom,
              onChanged: (d) => setState(() => _effectiveFrom = d),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: shifts.any((x) => x.id == _shiftId) ? _shiftId : null,
              decoration: InputDecoration(labelText: s.shift),
              items: [
                DropdownMenuItem(value: null, child: Text(s.defaultShift)),
                for (final sh in shifts)
                  DropdownMenuItem(value: sh.id, child: Text('${sh.name} (${sh.start}–${sh.end})')),
              ],
              onChanged: (v) => setState(() => _shiftId = v),
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: _busy ? null : _save, child: Text(s.save)),
          ],
        ),
      ),
    );
  }
}
