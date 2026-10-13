import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/providers.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/models/models.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/shift_chip.dart';

final rosterWeekProvider = FutureProvider.autoDispose.family<RosterWeek, String>(
  (ref, week) => ref.watch(rosterApiProvider).week(week),
);

DateTime _mondayOf(DateTime d) => DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));

/// Roster: one day at a time. Tap a person to change their shift; changes reach staff only after "Send to staff".
class RosterScreen extends ConsumerStatefulWidget {
  const RosterScreen({super.key, this.initialDate});

  /// Test seam: which day to open on (default today).
  final DateTime? initialDate;

  @override
  ConsumerState<RosterScreen> createState() => _RosterScreenState();
}

class _RosterScreenState extends ConsumerState<RosterScreen> {
  late DateTime _weekStart = _mondayOf(widget.initialDate ?? DateTime.now());
  late int _day = ((widget.initialDate ?? DateTime.now()).weekday - 1).clamp(0, 6);

  /// Whole week (a grid) instead of one day.
  bool _wholeWeek = false;

  String get _weekKey => Dates.toApiDate(_weekStart);

  void _moveWeek(int by) => setState(() => _weekStart = _weekStart.add(Duration(days: 7 * by)));

  void _refresh() => ref.invalidate(rosterWeekProvider(_weekKey));

  Future<void> _copyLastWeek() async {
    final s = context.s;
    int copied = 0;
    if (await runGuarded(context, () async => copied = await ref.read(rosterApiProvider).copyLastWeek(_weekKey))) {
      _refresh();
      if (mounted) showSnack(context, s.copiedLastWeek(copied));
    }
  }

  Future<void> _send() async {
    final s = context.s;
    final sent = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: AppColors.paper,
      builder: (_) => _SendSheet(weekKey: _weekKey),
    );
    if (sent != null && mounted) {
      _refresh();
      showSnack(context, s.rosterSent(sent));
    }
  }

  Future<void> _repeat(RosterWeek w) async {
    final s = context.s;
    if (!w.repeatAllowed && w.repeat == null) {
      unawaited(context.push(Routes.ownerBilling));
      return;
    }
    final done = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: AppColors.paper,
      builder: (_) => _RepeatSheet(week: w, weekKey: _weekKey),
    );
    if (done == null || !mounted) return;
    _refresh();
    showSnack(context, done == 'off' ? s.repeatTurnedOff : s.repeatTurnedOn);
  }

  Future<void> _change(RosterWeek w, RosterStaff person, String date) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: AppColors.paper,
      builder: (_) => _ChangeShiftSheet(week: w, person: person, date: date),
    );
    if (saved == true) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final week = ref.watch(rosterWeekProvider(_weekKey));
    return Scaffold(
      appBar: AppBar(title: Text(s.rosterTitle)),
      body: week.when(
        skipLoadingOnReload: true,
        loading: () => const LoadingView(),
        error: (e, _) => e is ApiException && e.isPlanError
            ? EmptyView(
                key: const Key('rosterNeedsPlan'),
                message: s.rosterNeedsPlan,
                icon: Icons.calendar_month_rounded,
                action: FilledButton(onPressed: () => context.push(Routes.ownerBilling), child: Text(s.seePlans)),
              )
            : ErrorView(error: e, onRetry: _refresh),
        data: _body,
      ),
      bottomNavigationBar: week.hasValue
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('rosterCopy'),
                        onPressed: _copyLastWeek,
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        label: FittedBox(fit: BoxFit.scaleDown, child: Text(s.copyLastWeek, maxLines: 1)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        key: const Key('rosterSend'),
                        onPressed: _send,
                        child: FittedBox(fit: BoxFit.scaleDown, child: Text(s.sendToStaff, maxLines: 1)),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Widget _body(RosterWeek w) {
    final s = context.s;
    final lang = s.languageCode;
    final day = w.days.isEmpty ? null : w.days[_day.clamp(0, w.days.length - 1)];
    if (day == null) return const SizedBox.shrink();
    final start = DateTime.parse(w.weekStart);
    final range = '${Dates.dayMonth(start, lang)} – ${Dates.dayMonth(start.add(const Duration(days: 6)), lang)}';
    final isThisWeek = _mondayOf(DateTime.now()) == _weekStart;
    final people = [
      for (final p in w.staff)
        if (p.cellOn(day.date)?.employed ?? false) p,
    ];
    // "Morning 3 · Evening 2 · Off 1" for the chosen day.
    final counts = <String, int>{};
    var off = 0;
    for (final p in people) {
      final c = p.cellOn(day.date)!;
      if (c.isOff || c.leave != null) {
        off++;
      } else {
        counts[c.shiftId ?? ''] = (counts[c.shiftId ?? ''] ?? 0) + 1;
      }
    }
    final summary = [
      for (final sh in w.shifts)
        if ((counts[sh.id] ?? 0) > 0) '${sh.name} ${counts[sh.id]}',
      if (off > 0) '${s.dayOff} $off',
    ].join(' · ');
    return RefreshableList(
      padding: const EdgeInsets.only(bottom: 24),
      onRefresh: () async {
        _refresh();
        await ref.read(rosterWeekProvider(_weekKey).future);
      },
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
          child: Row(
            children: [
              IconButton(
                key: const Key('rosterPrevWeek'),
                tooltip: s.previousWeek,
                onPressed: () => _moveWeek(-1),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Text(
                  isThisWeek ? s.thisWeekRange(range) : range,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
              IconButton(
                key: const Key('rosterNextWeek'),
                tooltip: s.nextWeek,
                onPressed: () => _moveWeek(1),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SegmentedButton<bool>(
            key: const Key('rosterViewToggle'),
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: false, label: Text(s.viewDay, key: const Key('rosterViewDay'))),
              ButtonSegment(value: true, label: Text(s.viewWeek, key: const Key('rosterViewWeek'))),
            ],
            selected: {_wholeWeek},
            onSelectionChanged: (v) => setState(() => _wholeWeek = v.first),
          ),
        ),
        if (!_wholeWeek)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                for (final (i, d) in w.days.indexed)
                  Expanded(
                    child: _DayTab(
                      key: Key('rosterDay$i'),
                      label: s.weekdayShort(DateTime.parse(d.date).weekday % 7),
                      date: DateTime.parse(d.date).day,
                      selected: i == _day,
                      holiday: d.holiday != null,
                      changed: w.staff.any((p) => p.cellOn(d.date)?.changed ?? false),
                      onTap: () => setState(() => _day = i),
                    ),
                  ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                key: const Key('rosterStatus'),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: w.notSent > 0 ? AppColors.amberLight : AppColors.mintLight,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  w.notSent > 0 ? s.rosterNotSent(w.notSent) : s.rosterAllSent,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: w.notSent > 0 ? AppColors.amberDark : AppColors.mintDark,
                  ),
                ),
              ),
              if (summary.isNotEmpty && !_wholeWeek)
                Text(summary, style: const TextStyle(color: AppColors.muted, fontSize: 13.5)),
            ],
          ),
        ),
        if (w.shifts.isNotEmpty) _RepeatTile(week: w, onTap: () => _repeat(w)),
        if (day.holiday != null && !_wholeWeek)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: AppColors.orangeLight, borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                const Icon(Icons.celebration_rounded, color: AppColors.orange, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(s.holidayLabel(day.holiday!), style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        if (w.shifts.length < 2)
          Card(
            key: const Key('rosterShiftsTip'),
            margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            color: AppColors.mintFaint,
            child: ListTile(
              leading: const Icon(Icons.lightbulb_outline_rounded, color: AppColors.mintDark),
              title: Text(s.rosterAddShiftsTip, style: const TextStyle(fontSize: 14.5)),
              trailing: TextButton(onPressed: () => context.push(Routes.ownerTimings), child: Text(s.addShifts)),
            ),
          ),
        const SizedBox(height: 6),
        if (_wholeWeek)
          _WeekGrid(
            week: w,
            onTapCell: (p, date) => _change(w, p, date),
            onTapDay: (i) => setState(() {
              _day = i;
              _wholeWeek = false;
            }),
          )
        else
          for (final p in people)
            _StaffRow(
              key: Key('rosterRow_${p.id}'),
              week: w,
              person: p,
              cell: p.cellOn(day.date)!,
              onTap: () => _change(w, p, day.date),
            ),
      ],
    );
  }
}

class _DayTab extends StatelessWidget {
  const _DayTab({
    super.key,
    required this.label,
    required this.date,
    required this.selected,
    required this.holiday,
    required this.changed,
    required this.onTap,
  });
  final String label;
  final int date;
  final bool selected;
  final bool holiday;
  final bool changed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 2.5),
    child: Material(
      color: selected ? AppColors.ink : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: selected ? AppColors.ink : AppColors.line, width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Center(
                child: Column(
                  children: [
                    FittedBox(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: selected ? Colors.white : AppColors.ink,
                        ),
                      ),
                    ),
                    Text('$date', style: TextStyle(fontSize: 12, color: selected ? Colors.white70 : AppColors.muted)),
                  ],
                ),
              ),
            ),
            if (holiday || changed)
              Positioned(
                top: 3,
                right: 3,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: changed ? AppColors.amber : AppColors.orange,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _StaffRow extends StatelessWidget {
  const _StaffRow({super.key, required this.week, required this.person, required this.cell, required this.onTap});
  final RosterWeek week;
  final RosterStaff person;
  final RosterCell cell;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: InkWell(
        borderRadius: AppTheme.radius,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
          child: Row(
            children: [
              InitialsAvatar(person.name),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(person.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
                    if (person.designation != null)
                      Text(person.designation!, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                  ],
                ),
              ),
              if (cell.leave != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                  decoration: BoxDecoration(color: AppColors.redLight, borderRadius: BorderRadius.circular(12)),
                  child: Text(
                    s.onLeaveTag,
                    style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                )
              else
                ShiftChip(shifts: week.shifts, shiftId: cell.shiftId, off: cell.isOff),
              if (cell.changed)
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Icon(Icons.circle, size: 9, color: AppColors.amber),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pick a shift or Day off for one person and day; optionally the same shift all week.
class _ChangeShiftSheet extends ConsumerStatefulWidget {
  const _ChangeShiftSheet({required this.week, required this.person, required this.date});
  final RosterWeek week;
  final RosterStaff person;
  final String date;

  @override
  ConsumerState<_ChangeShiftSheet> createState() => _ChangeShiftSheetState();
}

class _ChangeShiftSheetState extends ConsumerState<_ChangeShiftSheet> {
  /// A shift id, `off`, or `usual`.
  late String _pick;
  bool _allWeek = false;
  bool _busy = false;

  RosterCell get _cell => widget.person.cellOn(widget.date)!;

  @override
  void initState() {
    super.initState();
    _pick = _cell.isOff ? 'off' : (_cell.shiftId ?? 'off');
  }

  Future<void> _save() async {
    final pick = _pick;
    final kind = pick == 'off' || pick == 'usual' ? pick : 'shift';
    final shiftId = kind == 'shift' ? pick : null;
    final cells = <({String employeeId, String date, String kind, String? shiftId})>[
      (employeeId: widget.person.id, date: widget.date, kind: kind, shiftId: shiftId),
      if (_allWeek && kind == 'shift')
        for (final c in widget.person.cells)
          if (c.date != widget.date && c.employed && !c.isOff && c.leave == null)
            (employeeId: widget.person.id, date: c.date, kind: kind, shiftId: shiftId),
    ];
    setState(() => _busy = true);
    final ok = await runGuarded(context, () => ref.read(rosterApiProvider).setCells(cells));
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final lang = s.languageCode;
    final w = widget.week;
    Widget tile(String id, String title, String sub, ({Color fg, Color bg}) c) {
      final selected = _pick == id;
      return Material(
        color: selected ? AppColors.mintFaint : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: selected ? AppColors.mint : AppColors.line, width: 2),
        ),
        child: InkWell(
          key: Key('rosterPick_$id'),
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => _pick = id),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(color: c.fg, fontWeight: FontWeight.w800, fontSize: 17),
                ),
                const SizedBox(height: 2),
                Text(sub, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
              ],
            ),
          ),
        ),
      );
    }

    final tiles = [
      for (final sh in w.shifts) tile(sh.id, sh.name, fullHours(sh, lang), shiftColors(w.shifts, sh.id)),
      tile('off', s.dayOff, s.noWork, (fg: AppColors.muted, bg: AppColors.mutedLight)),
    ];
    return SingleChildScrollView(
      key: const Key('rosterChangeSheet'),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InitialsAvatar(widget.person.name),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.person.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                    Text(
                      Dates.weekdayShort(DateTime.parse(widget.date), lang),
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_cell.leave != null)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: AppColors.redLight, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: AppColors.red, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.problemLeave(widget.person.name, Dates.weekdayOnly(DateTime.parse(widget.date), lang)),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          // Two big tiles per row; each row as tall as its tallest tile, so long names and Hindi never clip.
          for (var i = 0; i < tiles.length; i += 2)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: tiles[i]),
                    const SizedBox(width: 10),
                    Expanded(child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox.shrink()),
                  ],
                ),
              ),
            ),
          if (!_cell.usual)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ListTile(
                key: const Key('rosterPick_usual'),
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  _pick == 'usual' ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                  color: _pick == 'usual' ? AppColors.mint : AppColors.muted,
                ),
                title: Text(s.usualShiftOption, style: const TextStyle(fontWeight: FontWeight.w700)),
                onTap: () => setState(() => _pick = 'usual'),
              ),
            ),
          SwitchListTile(
            key: const Key('rosterAllWeek'),
            contentPadding: EdgeInsets.zero,
            value: _allWeek && _pick != 'off' && _pick != 'usual',
            onChanged: _pick == 'off' || _pick == 'usual' ? null : (v) => setState(() => _allWeek = v),
            title: Text(s.sameAllWeek, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(s.sameAllWeekHint),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(key: const Key('rosterSave'), onPressed: _busy ? null : _save, child: Text(s.save)),
          ),
        ],
      ),
    );
  }
}

/// Before sending: problems with one-tap fixes, then "Send to N staff".
class _SendSheet extends ConsumerStatefulWidget {
  const _SendSheet({required this.weekKey});
  final String weekKey;

  @override
  ConsumerState<_SendSheet> createState() => _SendSheetState();
}

class _SendSheetState extends ConsumerState<_SendSheet> {
  bool _busy = false;

  Future<void> _fix(RosterProblem p) async {
    final ok = await runGuarded(
      context,
      () =>
          ref.read(rosterApiProvider).setCells([(employeeId: p.employeeId, date: p.date, kind: 'off', shiftId: null)]),
    );
    if (ok) ref.invalidate(rosterWeekProvider(widget.weekKey));
  }

  Future<void> _send() async {
    setState(() => _busy = true);
    int sent = 0;
    final ok = await runGuarded(context, () async => sent = await ref.read(rosterApiProvider).send(widget.weekKey));
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context, sent);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final lang = s.languageCode;
    final w = ref.watch(rosterWeekProvider(widget.weekKey)).value;
    if (w == null) return const SizedBox(height: 200, child: LoadingView(rows: 2));
    final people = w.staff.where((p) => p.cells.any((c) => c.changed)).length;
    String day(String d) => Dates.weekdayOnly(DateTime.parse(d), lang);
    return SingleChildScrollView(
      key: const Key('rosterSendSheet'),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.sendSheetTitle, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(s.sendSheetBody, style: const TextStyle(color: AppColors.muted)),
          if (w.problems.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(s.thingsToFix(w.problems.length), style: const TextStyle(fontWeight: FontWeight.w800)),
            for (final p in w.problems)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: AppColors.amber, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        p.type == 'leave_working' ? s.problemLeave(p.name, day(p.date)) : s.problemNoOff(p.name),
                        style: const TextStyle(fontSize: 15),
                      ),
                    ),
                    FilledButton.tonal(
                      key: Key('rosterFix_${p.employeeId}_${p.date}'),
                      onPressed: () => _fix(p),
                      child: Text(p.type == 'leave_working' ? s.fixMakeOff : s.fixGiveOff(day(p.date))),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const Key('rosterSendNow'),
              onPressed: _busy || people == 0 ? null : _send,
              child: Text(people == 0 ? s.nothingToSend : s.sendToN(people)),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Repeat every week": off, on (same / swap) with how it reaches staff, or locked on smaller plans.
class _RepeatTile extends StatelessWidget {
  const _RepeatTile({required this.week, required this.onTap});
  final RosterWeek week;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final r = week.repeat;
    final locked = r == null && !week.repeatAllowed;
    return Card(
      key: const Key('rosterRepeatTile'),
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      color: r != null ? AppColors.mintFaint : null,
      child: ListTile(
        onTap: onTap,
        leading: Icon(Icons.event_repeat_rounded, color: locked ? AppColors.muted : AppColors.mintDark),
        title: Text(
          r == null ? s.repeatTitle : (r.swaps ? s.repeatOnSwap : s.repeatOnSame),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          r == null ? (locked ? s.repeatNeedsPlan : s.repeatOffHint) : (r.autoSend ? s.repeatAutoOn : s.repeatAutoOff),
        ),
        trailing: Icon(locked ? Icons.lock_outline_rounded : Icons.chevron_right_rounded),
      ),
    );
  }
}

/// Shifts used this week, in start-time order (the order people move through when shifts swap).
List<Shift> _usedShifts(RosterWeek w) {
  final used = {
    for (final p in w.staff)
      for (final c in p.cells)
        if (c.employed && !c.isOff && c.shiftId != null) c.shiftId,
  };
  return [
    for (final sh in w.shifts)
      if (used.contains(sh.id)) sh,
  ];
}

class _RepeatSheet extends ConsumerStatefulWidget {
  const _RepeatSheet({required this.week, required this.weekKey});
  final RosterWeek week;
  final String weekKey;

  @override
  ConsumerState<_RepeatSheet> createState() => _RepeatSheetState();
}

class _RepeatSheetState extends ConsumerState<_RepeatSheet> {
  /// `off`, `same` or `rotate`.
  late String _mode = widget.week.repeat?.mode ?? 'same';
  late bool _autoSend = widget.week.repeat?.autoSend ?? false;
  bool _busy = false;

  Future<void> _save() async {
    final api = ref.read(rosterApiProvider);
    setState(() => _busy = true);
    final ok = await runGuarded(context, () async {
      if (_mode == 'off') {
        await api.stopRepeat();
      } else {
        await api.repeat(widget.weekKey, mode: _mode, autoSend: _autoSend);
      }
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context, _mode == 'off' ? 'off' : 'on');
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final used = _usedShifts(widget.week);
    final allowed = widget.week.repeatAllowed;
    // "Morning → Evening → Morning": back to the start shows it keeps going round.
    final chain = [...used.map((x) => x.name), if (used.isNotEmpty) used.first.name].join(' → ');
    Widget option(String mode, String title, String? sub, {bool enabled = true}) {
      final selected = _mode == mode;
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: selected ? AppColors.mintFaint : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: selected ? AppColors.mint : AppColors.line, width: 2),
          ),
          child: InkWell(
            key: Key('repeat_$mode'),
            borderRadius: BorderRadius.circular(16),
            onTap: enabled ? () => setState(() => _mode = mode) : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
              child: Row(
                children: [
                  Icon(
                    selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                    color: !enabled ? AppColors.line : (selected ? AppColors.mint : AppColors.muted),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: enabled ? AppColors.ink : AppColors.muted,
                          ),
                        ),
                        if (sub != null) Text(sub, style: const TextStyle(color: AppColors.muted, fontSize: 13.5)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      key: const Key('rosterRepeatSheet'),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.repeatSheetTitle, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          option('off', s.repeatNo, null),
          option('same', s.repeatSame, s.repeatSameHint, enabled: allowed),
          option(
            'rotate',
            s.repeatSwap,
            used.length < 2 ? s.repeatSwapNeeds : s.repeatSwapHint(chain),
            enabled: allowed && used.length >= 2,
          ),
          if (_mode != 'off')
            SwitchListTile(
              key: const Key('repeatAutoSend'),
              contentPadding: EdgeInsets.zero,
              value: _autoSend,
              onChanged: (v) => setState(() => _autoSend = v),
              title: Text(s.repeatAutoSend, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(s.repeatAutoSendHint),
            ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(key: const Key('repeatSave'), onPressed: _busy ? null : _save, child: Text(s.save)),
          ),
        ],
      ),
    );
  }
}

/// The whole week: one row per person, one box per day with the shift's letter. Tap a box to change it.
class _WeekGrid extends StatelessWidget {
  const _WeekGrid({required this.week, required this.onTapCell, required this.onTapDay});
  final RosterWeek week;
  final void Function(RosterStaff person, String date) onTapCell;
  final void Function(int day) onTapDay;

  static const _nameWidth = 84.0;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final w = week;
    final people = [
      for (final p in w.staff)
        if (p.cells.any((c) => c.employed)) p,
    ];
    return Padding(
      key: const Key('rosterWeekGrid'),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(width: _nameWidth),
              for (final (i, d) in w.days.indexed)
                Expanded(
                  child: InkWell(
                    key: Key('rosterGridDay$i'),
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => onTapDay(i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        children: [
                          FittedBox(
                            child: Text(
                              s.weekdayShort(DateTime.parse(d.date).weekday % 7),
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12.5,
                                color: d.holiday != null ? AppColors.orange : AppColors.ink,
                              ),
                            ),
                          ),
                          Text(
                            '${DateTime.parse(d.date).day}',
                            style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          for (final p in people)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SizedBox(
                    width: _nameWidth,
                    child: Text(
                      p.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, height: 1.15),
                    ),
                  ),
                  for (final d in w.days)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: _GridCell(
                          key: Key('rosterCell_${p.id}_${d.date}'),
                          week: w,
                          cell: p.cellOn(d.date),
                          onTap: (p.cellOn(d.date)?.employed ?? false) ? () => onTapCell(p, d.date) : null,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          // What the letters mean.
          Wrap(
            key: const Key('rosterLegend'),
            spacing: 12,
            runSpacing: 6,
            children: [
              for (final sh in w.shifts)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Letter(text: shiftShort(w.shifts, sh), colors: shiftColors(w.shifts, sh.id)),
                    const SizedBox(width: 5),
                    Text('${sh.name} ${shortHours(sh)}', style: const TextStyle(fontSize: 13)),
                  ],
                ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _Letter(text: '–', colors: (fg: AppColors.muted, bg: AppColors.mutedLight)),
                  const SizedBox(width: 5),
                  Text(s.dayOff, style: const TextStyle(fontSize: 13)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(s.tapCellHint, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
        ],
      ),
    );
  }
}

class _GridCell extends StatelessWidget {
  const _GridCell({super.key, required this.week, required this.cell, this.onTap});
  final RosterWeek week;
  final RosterCell? cell;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final c = cell;
    final shift = c == null ? null : week.shiftById(c.shiftId);
    final ({Color fg, Color bg}) colors;
    final String text;
    if (c == null || !c.employed) {
      colors = (fg: AppColors.line, bg: Colors.transparent);
      text = '';
    } else if (c.leave != null) {
      colors = (fg: AppColors.red, bg: AppColors.redLight);
      text = s.leaveShort;
    } else if (c.isOff || shift == null) {
      colors = (fg: AppColors.muted, bg: AppColors.mutedLight);
      text = '–';
    } else {
      colors = shiftColors(week.shifts, shift.id);
      text = shiftShort(week.shifts, shift);
    }
    return Material(
      color: colors.bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(9),
        side: c?.changed == true ? const BorderSide(color: AppColors.amber, width: 2) : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: SizedBox(
          height: 40,
          child: Center(
            child: Text(
              text,
              style: TextStyle(color: colors.fg, fontWeight: FontWeight.w800, fontSize: 15),
            ),
          ),
        ),
      ),
    );
  }
}

class _Letter extends StatelessWidget {
  const _Letter({required this.text, required this.colors});
  final String text;
  final ({Color fg, Color bg}) colors;

  @override
  Widget build(BuildContext context) => Container(
    width: 24,
    height: 22,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: colors.bg, borderRadius: BorderRadius.circular(6)),
    child: Text(
      text,
      style: TextStyle(color: colors.fg, fontWeight: FontWeight.w800, fontSize: 12.5),
    ),
  );
}
