import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/providers.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/phone.dart';
import '../../../core/utils/shift_text.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/pickers.dart';
import '../../auth/auth_controller.dart';
import '../attendance/month_summary.dart' show MonthTally, PersonMonthScreen;
import '../../profile/profile_screen.dart' show BankCard;
import '../../profile/profile_sheets.dart';
import '../providers/owner_providers.dart';
import '../salary/money_dialogs.dart';
import '../salary/advances_view.dart';
import 'slip_details_sheet.dart';
import 'verify_card.dart';

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
            TextButton.icon(
              key: const Key('editStaffButton'),
              icon: const Icon(Icons.edit_rounded, size: 18),
              label: Text(s.edit),
              onPressed: () async {
                final changed = await showModalBottomSheet<bool>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
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
          final shift = shifts.where((x) => x.id == e.shiftId).firstOrNull ?? defaultShiftOf(shifts);
          final lb = e.leaveBalance;
          // Only the owner may set where salary goes.
          final canEditBank = ref.read(authControllerProvider).user?.isOwner ?? false;
          Future<void> editBank(BankInfo? current) async {
            final api = ref.read(profileApiProvider);
            final saved = await showEditSheet(
              context,
              BankSheet(initial: current, defaultHolder: e.name, onSave: (b) => api.setStaffBank(e.id, b)),
            );
            if (saved) {
              invalidate();
              if (context.mounted) showSnack(context, s.salaryAccountSaved);
            }
          }

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
                  trailing: IconButton.filled(
                    tooltip: s.callStaff,
                    icon: const Icon(Icons.call_rounded),
                    onPressed: () => openUrl(context, 'tel:${e.phone}'),
                  ),
                ),
              ),
              // Only the owner sees document checks (they include date of birth and names on records).
              if (canEditBank) VerifyCard(employee: e),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _ThisMonth(employeeId: e.id),
              ),
              SectionHeader(s.pay),
              Card(
                child: Column(
                  children: [
                    _InfoRow(
                      label: s.salary,
                      value: e.ratePaise > 0
                          ? (e.isDaily ? s.perDay(Money.format(e.ratePaise)) : s.perMonth(Money.format(e.ratePaise)))
                          : '—',
                    ),
                    _InfoRow(
                      key: const Key('advanceToRecover'),
                      label: s.advanceToRecover,
                      value: Money.format(e.advanceBalancePaise ?? 0),
                      valueColor: (e.advanceBalancePaise ?? 0) > 0 ? AppColors.red : null,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              key: const Key('profileGiveAdvance'),
                              style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
                              onPressed: () async {
                                if (await showAddAdvanceSheet(context, ref, employee: e)) invalidate();
                              },
                              child: Text(s.giveAdvanceShort),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              key: const Key('profileBonusCut'),
                              style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
                              onPressed: () async {
                                final month = Dates.toApiMonth(DateTime.now());
                                if (await showAddAdjustmentSheet(context, ref, month: month, employee: e)) {
                                  invalidate();
                                }
                              },
                              child: Text(s.bonusCutShort),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              AdvancesList(employeeId: e.id, compact: true),
              SectionHeader(s.work),
              Card(
                key: const Key('workGroup'),
                child: Column(
                  children: [
                    _InfoRow(
                      label: s.shift,
                      value: shift == null
                          ? '—'
                          : '${Dates.hhmmToDisplay(shift.start, s.languageCode)} – ${Dates.hhmmToDisplay(shift.end, s.languageCode)}',
                    ),
                    if (shift != null && shift.weeklyOff.isNotEmpty)
                      _InfoRow(label: s.weeklyOffLabel, value: s.offDaysText(shift.weeklyOff, shift.weeklyOffWeeks)),
                    if (e.joiningDate != null)
                      _InfoRow(label: s.joinedLabel, value: Dates.prettyApiDate(e.joiningDate!, s.languageCode)),
                    _WhoMarksTile(employee: e, onChanged: invalidate),
                  ],
                ),
              ),
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
              SectionHeader(s.salaryAccountBi.text),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: e.bank == null
                    ? OutlinedButton.icon(
                        key: const Key('staffAddBank'),
                        onPressed: canEditBank ? () => editBank(null) : null,
                        icon: const Icon(Icons.account_balance_rounded),
                        label: Text(s.addSalaryAccount),
                      )
                    : BankCard(bank: e.bank!, onEdit: canEditBank ? () => editBank(e.bank) : null),
              ),
              if (canEditBank) ...[
                SectionHeader(s.slipDetailsBi.text),
                SlipDetailsCard(
                  details: e.statutory,
                  onEdit: () async {
                    final saved = await showEditSheet(
                      context,
                      SlipDetailsSheet(employeeId: e.id, initial: e.statutory),
                    );
                    if (saved) {
                      invalidate();
                      if (context.mounted) showSnack(context, s.saved);
                    }
                  },
                ),
              ],
              if (e.emergencyContact != null) ...[
                SectionHeader(s.emergencyBi.text),
                Card(
                  child: ListTile(
                    key: const Key('staffEmergency'),
                    leading: const Icon(Icons.contact_emergency_rounded, color: AppColors.red),
                    title: Text([e.emergencyContact!.name, ?e.emergencyContact!.relation].join(' · ')),
                    subtitle: e.emergencyContact!.phone == null
                        ? null
                        : Text(Phones.display(e.emergencyContact!.phone!)),
                    trailing: e.emergencyContact!.phone == null
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.call_rounded, color: AppColors.mintDark),
                            onPressed: () => openUrl(context, 'tel:${e.emergencyContact!.phone}'),
                          ),
                  ),
                ),
              ],
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
                    // Not on the app yet: send (or resend) the WhatsApp invite with the app link.
                    if (!e.linked && e.isActive)
                      ListTile(
                        key: const Key('inviteTile'),
                        leading: const Icon(Icons.send_to_mobile_rounded, color: AppColors.amberDark),
                        title: Text(s.appNotJoined),
                        subtitle: e.invitedAt == null
                            ? null
                            : Text(
                                s.invitedAgo(
                                  '${Dates.dayMonth(e.invitedAt!.toLocal(), s.languageCode)}, ${Dates.time(e.invitedAt!, s.languageCode)}',
                                ),
                              ),
                        trailing: TextButton(
                          key: const Key('inviteButton'),
                          onPressed: () async {
                            if (await runGuarded(
                              context,
                              () => ref.read(accountsApiProvider).invite(e.id),
                              success: s.inviteSent,
                            )) {
                              invalidate();
                            }
                          },
                          child: Text(e.invitedAt == null ? s.sendInvite : s.resendInvite),
                        ),
                      ),
                    // Staff the owner marks never check in, so location consent doesn't apply.
                    if (!e.ownerMarks(ref.watch(authControllerProvider).company?.settings))
                      ListTile(
                        leading: Icon(
                          e.locationConsent ? Icons.verified_user_rounded : Icons.privacy_tip_outlined,
                          color: e.locationConsent ? AppColors.mint : AppColors.muted,
                        ),
                        title: Text(e.locationConsent ? s.consentGiven : s.consentPending),
                      ),
                    if (e.faceStatus != 'none') _FaceTile(employee: e, onChanged: invalidate),
                  ],
                ),
              ),
              if (e.isActive)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.red,
                      side: const BorderSide(color: AppColors.red, width: 1.5),
                    ),
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

class _ThisMonth extends ConsumerWidget {
  const _ThisMonth({required this.employeeId});
  final String employeeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final month = Dates.firstOfMonth(DateTime.now());
    final grid = ref.watch(employeeMonthProvider((month: Dates.toApiMonth(month), employeeId: employeeId)));
    final row = grid.value?.rows.where((r) => r.employee.id == employeeId).firstOrNull ?? grid.value?.rows.firstOrNull;
    if (row == null) return grid.isLoading ? const SkeletonBox(height: 72, radius: 16) : const SizedBox.shrink();
    final t = MonthTally(row.totals);
    final chips = [
      ('present', s.chipPresentN((row.totals['present'] ?? 0).round())),
      if (t.late > 0) ('late', s.chipLateN(t.late.round())),
      if (t.absent > 0) ('absent', s.chipAbsentN(t.absent.round())),
      if (t.halfDay > 0) ('half_day', s.chipHalfDayN(t.halfDay.round())),
      if (t.leave > 0) ('leave', s.chipLeaveN(t.leave.round())),
    ];
    return Container(
      key: const Key('profileMonth'),
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppTheme.radius,
        border: Border.all(color: AppColors.line, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  s.monthSoFar(Dates.monthOnly(Dates.toApiMonth(month), s.languageCode)),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              TextButton(
                key: const Key('profileCalendar'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PersonMonthScreen(employee: row.employee, month: month),
                  ),
                ),
                child: Text('${s.calendarLink} ›'),
              ),
            ],
          ),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              for (final (status, label) in chips)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(StatusStyle.of(status).icon, size: 16, color: StatusStyle.of(status).fg),
                    const SizedBox(width: 4),
                    Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({super.key, required this.label, required this.value, this.valueColor});
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
    child: Row(
      children: [
        Text(label, style: const TextStyle(color: AppColors.muted)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(fontWeight: FontWeight.w800, color: valueColor ?? AppColors.ink),
          ),
        ),
      ],
    ),
  );
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
            if (shifts.isNotEmpty)
              DropdownButtonFormField<String>(
                initialValue: shifts.any((x) => x.id == _shiftId) ? _shiftId : defaultShiftOf(shifts)?.id,
                isExpanded: true,
                decoration: InputDecoration(labelText: s.shift),
                items: [
                  for (final sh in shifts)
                    DropdownMenuItem(
                      value: sh.id,
                      child: Text(shiftText(s, sh, withName: shifts.length > 1), overflow: TextOverflow.ellipsis),
                    ),
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

/// Who marks this person's attendance. Only the owner can change it.
class _WhoMarksTile extends ConsumerWidget {
  const _WhoMarksTile({required this.employee, required this.onChanged});
  final Employee employee;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final session = ref.watch(authControllerProvider);
    final isOwner = session.user?.isOwner ?? false;
    final business = session.company?.settings.attendanceMarking == 'owner' ? s.marksOwnerShort : s.marksSelfShort;
    // '' = follow the business setting (null on the server).
    String label(String v) => switch (v) {
      'self' => s.marksSelfShort,
      'owner' => s.marksOwnerShort,
      _ => s.marksSameAsBusiness(business),
    };
    final current = employee.attendanceMarking ?? '';
    return ListTile(
      key: const Key('staffWhoMarks'),
      leading: const Icon(Icons.how_to_reg_rounded),
      title: Text(s.whoMarksTitle),
      subtitle: Text(label(current)),
      trailing: isOwner ? const Icon(Icons.chevron_right_rounded) : null,
      onTap: !isOwner
          ? null
          : () async {
              final picked = await showDialog<String>(
                context: context,
                builder: (ctx) => SimpleDialog(
                  title: Text(s.whoMarksTitle),
                  children: [
                    for (final v in const ['', 'self', 'owner'])
                      SimpleDialogOption(
                        onPressed: () => Navigator.pop(ctx, v),
                        child: Row(
                          children: [
                            Icon(
                              v == current ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                              color: AppColors.mintDark,
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Text(label(v))),
                          ],
                        ),
                      ),
                  ],
                ),
              );
              if (picked == null || picked == current || !context.mounted) return;
              final ok = await runGuarded(
                context,
                () => ref.read(employeesApiProvider).update(employee.id, {
                  'attendanceMarking': picked.isEmpty ? null : picked,
                }),
                success: s.saved,
              );
              if (ok) onChanged();
            },
    );
  }
}

final employeeFaceProvider = FutureProvider.autoDispose.family<FaceInfo, String>(
  (ref, id) => ref.watch(employeesApiProvider).face(id),
);

/// Face check photo: approve a new one, ask for another, or reset.
class _FaceTile extends ConsumerWidget {
  const _FaceTile({required this.employee, required this.onChanged});
  final Employee employee;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final face = ref.watch(employeeFaceProvider(employee.id)).value;
    final api = ref.read(employeesApiProvider);
    Future<void> act(Future<void> Function() call, String done) async {
      if (await runGuarded(context, call, success: done)) {
        ref.invalidate(employeeFaceProvider(employee.id));
        onChanged();
      }
    }

    final url = face?.photoUrl;
    return ListTile(
      key: const Key('staffFaceTile'),
      leading: CircleAvatar(
        backgroundColor: AppColors.mintLight,
        backgroundImage: url == null ? null : NetworkImage(url),
        child: url == null ? const Icon(Icons.face_retouching_natural_rounded, color: AppColors.mint) : null,
      ),
      title: Text(s.faceCheckBi.text),
      subtitle: Text(s.faceStatusLabel(employee.faceStatus)),
      trailing: employee.faceStatus == 'pending'
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: s.faceAskRetake,
                  icon: const Icon(Icons.close_rounded, color: AppColors.red),
                  onPressed: () => act(() => api.resetFace(employee.id), s.rejected),
                ),
                IconButton(
                  key: const Key('approveFace'),
                  tooltip: s.approve,
                  icon: const Icon(Icons.check_rounded, color: AppColors.mint),
                  onPressed: () => act(() => api.approveFace(employee.id), s.approved),
                ),
              ],
            )
          : TextButton(
              onPressed: () async {
                if (!await confirmDialog(context, title: s.faceAskRetake, destructive: true)) return;
                if (context.mounted) await act(() => api.resetFace(employee.id), s.faceRemoved);
              },
              child: Text(s.faceAskRetake),
            ),
    );
  }
}
