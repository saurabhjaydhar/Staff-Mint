import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/providers.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/ledger_sheet.dart';
import '../../../core/widgets/pickers.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/status_pill.dart';
import '../../accounts/accounts_screen.dart' show AccountAlerts;
import '../../auth/auth_controller.dart';
import '../attendance/attendance_detail_sheet.dart';
import '../attendance/month_summary.dart';
import '../providers/owner_providers.dart';
import 'home_header.dart';
import 'home_tips.dart';
import 'needs_you_card.dart';
import 'setup_checklist.dart';
import 'status_quick_sheet.dart';
import 'trial_banner.dart';

/// Owner Home: business name once, a Day | Month switch, the day in words
/// ("6 of 9 at work"), a ledger with column headings and tappable statuses,
/// what needs the owner's OK, and a getting-started checklist for new shops.
/// Fixing a day: pick what happened, optional reason, Save; Undo for 5 s.
class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key});

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  DateTime _date = Dates.today();
  bool _monthMode = false;
  DateTime _month = Dates.firstOfMonth(DateTime.now());
  bool _showOffList = false;

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
      showUndoSnackBar(context, s.markedAs(prev.employee.name, s.statusShort(c.status)), () => _undo(prev, date));
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
    final lang = s.languageCode;
    final isToday = Dates.isSameDay(_date, Dates.today());
    final subtitle = _monthMode
        ? Dates.monthTitle(_month, lang)
        : (isToday ? s.todayOn(Dates.weekdayShort(_date, lang)) : Dates.weekdayShort(_date, lang));
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            HomeHeader(subtitle: subtitle),
            DayMonthSwitch(month: _monthMode, onChanged: (v) => setState(() => _monthMode = v)),
            const AccountAlerts(),
            if (_monthMode) ...[
              MonthSwitcher(month: _month, onChanged: (m) => setState(() => _month = m)),
              Expanded(child: MonthSummaryView(month: _month)),
            ] else ...[
              DateSwitcher(
                date: _date,
                onChanged: (d) => setState(() {
                  _date = d;
                  _showOffList = false;
                }),
              ),
              Expanded(child: _dayBody(isToday)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _dayBody(bool isToday) {
    final s = context.s;
    final session = ref.watch(authControllerProvider);
    final rows = ref.watch(dayAttendanceProvider(_dateKey));
    final dash = isToday ? ref.watch(dashboardProvider).value : null;
    final setup = dash?.setup;
    final Widget sheet;
    if (rows.hasValue) {
      final list = _effective(rows.requireValue);
      final dayOff =
          list.isNotEmpty && list.every((r) => _offStatuses.contains(r.displayStatus) && r.record?.firstIn == null);
      if (list.isEmpty) {
        sheet = EmptyView(message: s.emptyStaffHome, icon: Icons.people_outline);
      } else if (dayOff && !_showOffList) {
        sheet = _DayOffCard(
          isToday: isToday,
          holidayName: list.first.displayStatus == 'holiday' ? list.first.holidayName : null,
          onShowList: () => setState(() => _showOffList = true),
        );
      } else {
        sheet = _Ledger(rows: list, me: session.user?.id, onPill: _openRow, onRow: _openRow);
      }
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
          if (isToday && session.isOwner) const HomeTips(),
          if (setup != null) ...[SetupChecklistCard(setup: setup), InviteStatusBanner(setup: setup)],
          if (dash != null) NeedsYouCard(dashboard: dash),
          sheet,
          const TrialBanner(padding: EdgeInsets.fromLTRB(14, 12, 14, 0)),
        ],
      ),
    );
  }
}

const _offStatuses = {'week_off', 'holiday'};

/// Days off say so, instead of "0 / 9 present" and nine grey rows.
class _DayOffCard extends StatelessWidget {
  const _DayOffCard({required this.isToday, required this.holidayName, required this.onShowList});
  final bool isToday;
  final String? holidayName;
  final VoidCallback onShowList;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final holiday = holidayName != null;
    return Container(
      key: const Key('dayOffCard'),
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(holiday ? Icons.celebration_rounded : Icons.weekend_rounded, color: AppColors.mintDark, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  holiday ? s.holidayTitle(holidayName!) : (isToday ? s.weeklyOffTitle : s.dayOffPastTitle),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 38),
            child: Text(holiday ? s.holidayBody : s.weeklyOffBody, style: const TextStyle(color: AppColors.muted)),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(key: const Key('showOffList'), onPressed: onShowList, child: Text(s.showStaffList)),
          ),
        ],
      ),
    );
  }
}

class _Ledger extends StatelessWidget {
  const _Ledger({required this.rows, required this.me, required this.onPill, required this.onRow});
  final List<DayRow> rows;
  final String? me;
  final ValueChanged<DayRow> onPill;
  final ValueChanged<DayRow> onRow;

  static const _atWork = {'present', 'late', 'checked_in', 'half_day'};

  /// One plain line under the name that says why the row looks the way it does.
  String? _why(S s, DayRow r) {
    final rec = r.record;
    final away = r.awayM;
    if (r.needsCheck && away != null) return s.rowAway(away);
    if (rec != null && rec.overridden) {
      final reason = rec.overrideReason;
      return [
        rec.overriddenBy != null && rec.overriddenBy == me ? s.rowChangedByYou : s.rowChangedByOther,
        if (reason != null && reason.isNotEmpty && reason != 'Undo') reason,
      ].join(' · ');
    }
    switch (r.displayStatus) {
      case 'late':
        return (rec?.lateMinutes ?? 0) > 0 ? s.rowLateBy(rec!.lateMinutes) : null;
      case 'not_marked':
        if (!r.employee.linked) {
          return [s.rowNotInstalled, if (r.employee.invitedAt != null) s.rowInvited].join(' · ');
        }
        return s.rowNotCheckedIn;
      case 'leave':
        return s.rowLeaveApproved;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    int count(String st) => rows.where((r) => r.displayStatus == st).length;
    final expected = rows.where((r) => !_offStatuses.contains(r.displayStatus)).length;
    final atWork = rows.where((r) => _atWork.contains(r.displayStatus)).length;
    final present = count('present') + count('checked_in');
    final late = count('late');
    final half = count('half_day');
    final leave = count('leave');
    final absent = count('absent');
    final notIn = count('not_marked');
    return LedgerSheet(
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(LedgerSheet.marginX + 12, 12, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.atWorkSummary(atWork, expected),
                  key: const Key('atWorkSummary'),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (present > 0) LedgerChip(label: s.chipPresentN(present), status: 'present'),
                    if (late > 0) LedgerChip(label: s.chipLateN(late), status: 'late'),
                    if (half > 0) LedgerChip(label: s.chipHalfDayN(half), status: 'half_day'),
                    if (leave > 0) LedgerChip(label: s.chipLeaveN(leave), status: 'leave'),
                    if (absent > 0) LedgerChip(label: s.chipAbsentN(absent), status: 'absent'),
                    if (notIn > 0) LedgerChip(label: s.chipNotInN(notIn), status: 'not_marked'),
                  ],
                ),
              ],
            ),
          ),
          Container(
            key: const Key('ledgerColumns'),
            decoration: const BoxDecoration(
              color: AppColors.paper,
              border: Border(
                top: BorderSide(color: AppColors.line),
                bottom: BorderSide(color: AppColors.line),
              ),
            ),
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                SizedBox(
                  width: LedgerSheet.marginX,
                  child: Text(s.colInAt, textAlign: TextAlign.center, style: _colStyle),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(s.colName, style: _colStyle)),
                Padding(
                  padding: const EdgeInsets.only(right: 18),
                  child: Text('${s.colStatus} ▾', style: _colStyle),
                ),
              ],
            ),
          ),
        ],
      ),
      rows: [
        for (final r in rows)
          Builder(
            builder: (context) {
              final inP = r.record?.firstIn;
              final lock = r.lockIssue;
              return LedgerRow(
                key: Key('ledgerRow_${r.employee.id}'),
                margin: inP == null ? '—' : Dates.clock(inP.clientTime),
                title: r.employee.name,
                subtitle: _why(s, r),
                meta: lock == null ? null : s.lockTagShort(lock),
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

  static const _colStyle = TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w700);
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
