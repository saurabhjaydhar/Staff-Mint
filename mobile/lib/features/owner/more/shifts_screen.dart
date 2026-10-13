import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/providers.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/models/models.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/shift_text.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/pickers.dart';
import '../../auth/auth_controller.dart';
import '../providers/owner_providers.dart';

/// Add or change a shift in a bottom sheet; refreshes the list when saved. Returns the saved shift.
Future<Shift?> editShift(BuildContext context, WidgetRef ref, [Shift? shift]) async {
  final saved = await showModalBottomSheet<Shift>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _ShiftForm(shift: shift),
  );
  if (saved != null) ref.invalidate(shiftsProvider);
  return saved;
}

const _newShift = '__new_shift__';

/// The shift dropdown when adding or editing staff. Its last item, "Add shift", makes a new shift right
/// there and picks it.
class ShiftPicker extends ConsumerStatefulWidget {
  const ShiftPicker({super.key, required this.value, required this.onChanged});

  /// null: the business's default shift.
  final String? value;
  final ValueChanged<String> onChanged;

  @override
  ConsumerState<ShiftPicker> createState() => _ShiftPickerState();
}

class _ShiftPickerState extends ConsumerState<ShiftPicker> {
  /// A shift just made here, shown before the list has reloaded with it.
  Shift? _made;

  /// Bumped to show the right choice again after "Add shift" (saved or cancelled).
  int _rev = 0;

  Future<void> _add() async {
    final made = await editShift(context, ref);
    if (!mounted) return;
    setState(() {
      _rev++;
      if (made != null) _made = made;
    });
    if (made != null) widget.onChanged(made.id);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final loaded = ref.watch(shiftsProvider).value ?? const <Shift>[];
    final shifts = [...loaded, if (_made != null && !loaded.any((x) => x.id == _made!.id)) _made!];
    final selected = shifts.any((x) => x.id == widget.value) ? widget.value : defaultShiftOf(shifts)?.id;
    // Only owners make shifts (managers can still pick one).
    final canAdd = ref.watch(authControllerProvider).isOwner;
    return DropdownButtonFormField<String>(
      key: ValueKey('shiftPicker_${selected}_${shifts.length}_$_rev'),
      initialValue: selected,
      isExpanded: true,
      decoration: InputDecoration(labelText: s.shift),
      items: [
        for (final sh in shifts)
          DropdownMenuItem(
            value: sh.id,
            child: Text(shiftText(s, sh, withName: shifts.length > 1), overflow: TextOverflow.ellipsis),
          ),
        if (canAdd)
          DropdownMenuItem(
            key: const Key('shiftPickerAdd'),
            value: _newShift,
            child: Row(
              children: [
                const Icon(Icons.add_rounded, size: 20),
                const SizedBox(width: 6),
                Text(s.addShift, style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
      ],
      onChanged: (v) {
        if (v == _newShift) {
          _add();
        } else if (v != null) {
          widget.onChanged(v);
        }
      },
    );
  }
}

class ShiftsScreen extends ConsumerWidget {
  const ShiftsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final shifts = ref.watch(shiftsProvider);
    Future<void> edit([Shift? shift]) => editShift(context, ref, shift);

    return Scaffold(
      appBar: AppBar(
        title: Text(s.shifts),
        actions: [IconButton(tooltip: s.addShift, icon: const Icon(Icons.add), onPressed: () => edit())],
      ),
      body: AsyncBody<List<Shift>>(
        value: shifts,
        onRetry: () => ref.invalidate(shiftsProvider),
        data: (list) => RefreshableList(
          onRefresh: () => ref.refresh(shiftsProvider.future),
          children: [
            if (list.isEmpty) EmptyView(message: s.nothingHere),
            for (final sh in list)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.schedule_rounded),
                  title: Text(sh.name),
                  subtitle: Text(
                    [
                      '${Dates.hhmmToDisplay(sh.start, s.languageCode)} – ${Dates.hhmmToDisplay(sh.end, s.languageCode)}',
                      if (sh.weeklyOff.isNotEmpty) '${s.weeklyOff}: ${s.offDaysText(sh.weeklyOff, sh.weeklyOffWeeks)}',
                      if (sh.graceMinutes != null) '${s.graceMinutes}: ${sh.graceMinutes}',
                    ].join('\n'),
                  ),
                  trailing: const Icon(Icons.edit_rounded),
                  onTap: () => edit(sh),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ShiftForm extends ConsumerStatefulWidget {
  const _ShiftForm({this.shift});
  final Shift? shift;

  @override
  ConsumerState<_ShiftForm> createState() => _ShiftFormState();
}

class _ShiftFormState extends ConsumerState<_ShiftForm> {
  late final _name = TextEditingController(text: widget.shift?.name ?? '');
  late final _grace = TextEditingController(text: widget.shift?.graceMinutes?.toString() ?? '');
  late final _minStaff = TextEditingController(
    text: (widget.shift?.minStaff ?? 0) > 0 ? '${widget.shift!.minStaff}' : '',
  );
  late String _start = widget.shift?.start ?? '09:00';
  late String _end = widget.shift?.end ?? '19:00';
  late List<int> _weeklyOff = [...?widget.shift?.weeklyOff];
  late final Map<int, List<int>> _offWeeks = {...?widget.shift?.weeklyOffWeeks};
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _grace.dispose();
    _minStaff.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = context.s;
    if (_name.text.trim().isEmpty) {
      showSnack(context, s.required, error: true);
      return;
    }
    final body = {
      'name': _name.text.trim(),
      'start': _start,
      'end': _end,
      'weeklyOff': _weeklyOff,
      'weeklyOffWeeks': {
        for (final d in _weeklyOff)
          if (_offWeeks[d]?.isNotEmpty == true) '$d': _offWeeks[d],
      },
      'graceMinutes': int.tryParse(_grace.text),
      'minStaff': int.tryParse(_minStaff.text) ?? 0,
    };
    setState(() => _busy = true);
    final api = ref.read(companyApiProvider);
    Shift? saved;
    final ok = await runGuarded(context, () async {
      saved = widget.shift == null ? await api.createShift(body) : await api.updateShift(widget.shift!.id, body);
    }, success: s.saved);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context, saved);
  }

  Widget _offWeeksRow(S s, int day) {
    final current = _offWeeks[day] ?? const <int>[];
    final options = <List<int>>[
      const [],
      const [1, 3],
      const [2, 4],
      if (current.isNotEmpty && !(_sameList(current, const [1, 3]) || _sameList(current, const [2, 4]))) current,
    ];
    return Padding(
      key: Key('offWeeks_$day'),
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.whichWeekdayOff(s.weekday(day)), style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final o in options)
                ChoiceChip(
                  key: Key('offWeeks_${day}_${o.join('_')}'),
                  label: Text(o.isEmpty ? s.everyWeek : s.weeksOfMonth(o)),
                  selected: _sameList(current, o),
                  onSelected: (_) => setState(() => _offWeeks[day] = o),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static bool _sameList(List<int> a, List<int> b) =>
      a.length == b.length && [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((x) => x);

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        children: [
          Text(widget.shift == null ? s.addShift : s.edit, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            decoration: InputDecoration(labelText: s.shiftName),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TimeField(label: s.startTime, value: _start, onChanged: (v) => setState(() => _start = v)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TimeField(label: s.endTime, value: _end, onChanged: (v) => setState(() => _end = v)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _grace,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: s.useCompanyGrace),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('shiftMinStaff'),
            controller: _minStaff,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: s.minStaffLabel, helperText: s.minStaffHint),
          ),
          const SizedBox(height: 12),
          Text(s.weeklyOff, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          WeekdayChips(selected: _weeklyOff, onChanged: (v) => setState(() => _weeklyOff = v)),
          // Alternating offs, e.g. only the 1st and 3rd Saturday.
          for (final d in _weeklyOff) _offWeeksRow(s, d),
          const SizedBox(height: 20),
          FilledButton(onPressed: _busy ? null : _save, child: Text(s.save)),
        ],
      ),
    );
  }
}
