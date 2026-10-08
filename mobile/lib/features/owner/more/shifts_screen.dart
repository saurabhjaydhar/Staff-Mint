import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/providers.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/models/models.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/pickers.dart';
import '../providers/owner_providers.dart';

class ShiftsScreen extends ConsumerWidget {
  const ShiftsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final shifts = ref.watch(shiftsProvider);
    Future<void> edit([Shift? shift]) async {
      final changed = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => _ShiftForm(shift: shift),
      );
      if (changed == true) ref.invalidate(shiftsProvider);
    }

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
                      if (sh.weeklyOff.isNotEmpty) '${s.weeklyOff}: ${sh.weeklyOff.map(s.weekdayShort).join(', ')}',
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
  late String _start = widget.shift?.start ?? '09:00';
  late String _end = widget.shift?.end ?? '19:00';
  late List<int> _weeklyOff = [...?widget.shift?.weeklyOff];
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _grace.dispose();
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
      'graceMinutes': int.tryParse(_grace.text),
    };
    setState(() => _busy = true);
    final api = ref.read(companyApiProvider);
    final ok = await runGuarded(context, () async {
      if (widget.shift == null) {
        await api.createShift(body);
      } else {
        await api.updateShift(widget.shift!.id, body);
      }
    }, success: s.saved);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context, true);
  }

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
          Text(s.weeklyOff, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          WeekdayChips(selected: _weeklyOff, onChanged: (v) => setState(() => _weeklyOff = v)),
          const SizedBox(height: 20),
          FilledButton(onPressed: _busy ? null : _save, child: Text(s.save)),
        ],
      ),
    );
  }
}
