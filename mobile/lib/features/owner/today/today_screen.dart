import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/providers.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/bilingual.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/ledger_sheet.dart';
import '../../../core/widgets/pickers.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/status_pill.dart';
import '../../accounts/accounts_screen.dart' show BusinessSwitchChip;
import '../../auth/auth_controller.dart';
import '../attendance/attendance_detail_sheet.dart';
import '../attendance/month_grid.dart';
import '../providers/owner_providers.dart';
import 'needs_you_card.dart';
import 'status_quick_sheet.dart';

/// Owner "Today": the ledger day-sheet (who came, when) plus what needs the
/// owner. Tap a status pill to fix it in two taps; every save can be undone.
class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key});

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  DateTime _date = Dates.today();
  bool _monthMode = false;
  DateTime _month = Dates.firstOfMonth(DateTime.now());

  /// Optimistic rows by employee id, applied on top of [_patchBase] (the
  /// list they were made against). A fresh list from the server drops them.
  final Map<String, DayRow> _patches = {};
  List<DayRow>? _patchBase;

  String get _dateKey => Dates.toApiDate(_date);

  /// Shows [row] immediately on the sheet for [date] (if still on screen).
  void _patch(String date, DayRow row) {
    final base = ref.read(dayAttendanceProvider(date)).value;
    if (date != _dateKey || base == null) return;
    setState(() {
      if (!identical(base, _patchBase)) _patches.clear();
      _patchBase = base;
      _patches[row.employee.id] = row;
    });
  }

  List<DayRow> _effective(List<DayRow> list) {
    if (!identical(list, _patchBase)) {
      _patches.clear();
      _patchBase = null;
    }
    return [for (final r in list) _patches[r.employee.id] ?? r];
  }

  Future<void> _refresh() async {
    ref.invalidate(dashboardProvider);
    ref.invalidate(dayAttendanceProvider(_dateKey));
    await ref.read(dayAttendanceProvider(_dateKey).future);
  }

  void _openDetails(DayRow row) => showAttendanceDetail(context, row: row, date: _dateKey);

  /// Whole row and pill behave the same: 2-tap quick sheet, or details when a punch needs a decision.
  void _openRow(DayRow row) => row.needsCheck ? _openDetails(row) : _openQuick(row);

  Future<void> _openQuick(DayRow row) async {
    final date = _dateKey;
    final choice = await showStatusQuickSheet(context, row: row, date: date, onDetails: () => _openDetails(row));
    if (choice == null || !mounted) return;
    await _save(date, row, choice);
  }

  Future<void> _save(String date, DayRow prev, StatusChoice c) async {
    final s = context.s;
    final api = ref.read(attendanceApiProvider);
    _patch(date, DayRow(employee: prev.employee, record: prev.record, displayStatus: c.status));
    try {
      final rec = await api.overrideStatus(
        employeeId: prev.employee.id,
        date: date,
        status: c.status,
        leaveType: c.status == 'leave' ? c.leaveType : null,
        reason: c.reason,
      );
      if (!mounted) return;
      _patch(date, prev.withRecord(rec, fallback: c.status));
      invalidateAttendance(ref);
      showUndoSnackBar(context, s.statusSaved(prev.employee.name, s.statusShort(c.status)), () => _undo(prev, date));
    } catch (e) {
      if (!mounted) return;
      setState(() => _patches.remove(prev.employee.id));
      showError(context, e);
    }
  }

  /// Puts the day back: re-applies an earlier owner override, otherwise
  /// clears the override so the server recomputes from punches/leave/holiday.
  Future<void> _undo(DayRow prev, String date) async {
    final s = context.s;
    final api = ref.read(attendanceApiProvider);
    final rec = prev.record;
    final wasOverride = rec != null && rec.overridden && rec.status != null;
    _patch(date, prev);
    try {
      if (wasOverride) {
        await api.overrideStatus(
          employeeId: prev.employee.id,
          date: date,
          status: rec.status!,
          leaveType: rec.leaveType,
          reason: 'Undo',
        );
      } else {
        await api.clearOverride(employeeId: prev.employee.id, date: date, reason: 'Undo');
      }
      if (!mounted) return;
      invalidateAttendance(ref);
      showSnack(context, s.undone);
    } catch (e) {
      if (!mounted) return;
      invalidateAttendance(ref); // show the server's truth again
      showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final company = ref.watch(authControllerProvider.select((v) => v.company?.name));
    final isToday = Dates.isSameDay(_date, Dates.today());
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            ScreenHeader(
              subtitle: [Dates.weekdayShort(_monthMode ? DateTime.now() : _date, s.languageCode), ?company].join(' · '),
              title: _monthMode ? s.dayTitle : (isToday ? s.todayTitle : s.dayTitle),
              actions: [
                IconButton(
                  key: const Key('monthToggle'),
                  tooltip: s.dayMonthToggle,
                  icon: Icon(_monthMode ? Icons.view_agenda_rounded : Icons.calendar_view_month_rounded),
                  onPressed: () => setState(() => _monthMode = !_monthMode),
                ),
              ],
            ),
            const BusinessSwitchChip(),
            if (_monthMode) ...[
              MonthSwitcher(month: _month, onChanged: (m) => setState(() => _month = m)),
              Expanded(child: MonthGridView(month: Dates.toApiMonth(_month))),
            ] else ...[
              DateSwitcher(date: _date, onChanged: (d) => setState(() => _date = d)),
              Expanded(child: _dayBody(isToday)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _dayBody(bool isToday) {
    final s = context.s;
    final rows = ref.watch(dayAttendanceProvider(_dateKey));
    final dash = isToday ? ref.watch(dashboardProvider).value : null;
    final Widget sheet;
    if (rows.hasValue) {
      final list = _effective(rows.requireValue);
      sheet = list.isEmpty
          ? EmptyView(message: s.noAttendanceRows, icon: Icons.event_busy_outlined)
          : _Ledger(rows: list, onPill: _openRow, onRow: _openRow);
    } else if (rows.hasError) {
      sheet = ErrorView(error: rows.error!, onRetry: () => ref.invalidate(dayAttendanceProvider(_dateKey)));
    } else {
      sheet = const _LedgerSkeleton();
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (dash != null) NeedsYouCard(dashboard: dash),
          sheet,
        ],
      ),
    );
  }
}

class _Ledger extends StatelessWidget {
  const _Ledger({required this.rows, required this.onPill, required this.onRow});
  final List<DayRow> rows;
  final ValueChanged<DayRow> onPill;
  final ValueChanged<DayRow> onRow;

  static const _presentLike = {'present', 'late', 'checked_in', 'half_day'};

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    int count(String st) => rows.where((r) => r.displayStatus == st).length;
    final present = rows.where((r) => _presentLike.contains(r.displayStatus)).length;
    final late = count('late');
    final leave = count('leave');
    final absent = count('absent');
    final remaining = count('not_marked');
    return LedgerSheet(
      header: LedgerHeader(
        label: s.presentBi.joined,
        value: '$present',
        total: '${rows.length}',
        chips: [
          if (late > 0) LedgerChip(label: s.chipLate(late), status: 'late'),
          if (leave > 0) LedgerChip(label: s.chipLeave(leave), status: 'leave'),
          if (absent > 0) LedgerChip(label: s.chipAbsent(absent), status: 'absent'),
          if (remaining > 0) LedgerChip(label: s.chipRemaining(remaining), status: 'not_marked'),
        ],
      ),
      rows: [
        for (final r in rows)
          Builder(
            builder: (context) {
              final inP = r.record?.firstIn;
              final late = r.record?.lateMinutes ?? 0;
              final away = r.awayM;
              final lock = r.lockIssue;
              final meta = [
                if (r.needsCheck && away != null)
                  s.metersShort(away)
                else if (r.displayStatus == 'late' && late > 0)
                  s.minutesShort(late),
                if (lock != null) s.lockTagShort(lock),
              ];
              return LedgerRow(
                key: Key('ledgerRow_${r.employee.id}'),
                margin: inP == null ? '—' : Dates.clock(inP.clientTime),
                title: r.employee.name,
                meta: meta.isEmpty ? null : meta.join(' · '),
                trailing: StatusPill(
                  key: Key('pill_${r.employee.id}'),
                  status: r.needsCheck ? StatusStyle.needsCheck : r.displayStatus,
                  onTap: () => onPill(r),
                ),
                onTap: () => onRow(r),
              );
            },
          ),
      ],
    );
  }
}

class _LedgerSkeleton extends StatelessWidget {
  const _LedgerSkeleton();

  @override
  Widget build(BuildContext context) => LedgerSheet(
    header: const Padding(
      padding: EdgeInsets.fromLTRB(LedgerSheet.marginX + 12, 14, 12, 14),
      child: Row(children: [SkeletonBox(width: 70, height: 40), Spacer(), SkeletonBox(width: 120, height: 18)]),
    ),
    rows: [
      for (var i = 0; i < 6; i++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            children: [
              const SizedBox(
                width: LedgerSheet.marginX,
                child: Center(child: SkeletonBox(width: 24, height: 10)),
              ),
              const SizedBox(width: 12),
              SkeletonBox(width: i.isEven ? 130 : 96, height: 14),
              const Spacer(),
              const SkeletonBox(width: 70, height: 20, radius: 9),
              const SizedBox(width: 10),
            ],
          ),
        ),
    ],
  );
}
