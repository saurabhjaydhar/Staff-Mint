import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/providers.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/attendance_calendar.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/pickers.dart';
import '../providers/owner_providers.dart';
import '../today/status_quick_sheet.dart';
import 'attendance_detail_sheet.dart';
import 'month_grid.dart';

/// Totals for one person's month, in the words owners use.
class MonthTally {
  MonthTally(Map<String, num> t)
    : present = (t['present'] ?? 0) + (t['halfDay'] ?? 0) * 0.5,
      late = t['late'] ?? 0,
      absent = t['absent'] ?? 0,
      leave = t['leave'] ?? 0,
      halfDay = t['halfDay'] ?? 0,
      workDays =
          (t['present'] ?? 0) + (t['absent'] ?? 0) + (t['halfDay'] ?? 0) + (t['leave'] ?? 0) + (t['notMarked'] ?? 0);

  final num present;
  final num late;
  final num absent;
  final num leave;
  final num halfDay;

  /// Days the shop was open and this person was expected (holidays and week offs left out).
  final num workDays;

  String line(S s) {
    final parts = [
      if (late > 0) s.chipLateN(late.round()),
      if (absent > 0) s.chipAbsentN(absent.round()),
      if (leave > 0) s.chipLeaveN(leave.round()),
      if (halfDay > 0) s.chipHalfDayN(halfDay.round()),
    ];
    return parts.isEmpty ? s.allGood : parts.join(' · ');
  }
}

String _n(num v) => v == v.roundToDouble() ? '${v.round()}' : '$v';

/// Month opens as a simple list with each person's totals in words; tap a
/// person for their calendar. The full day-by-day grid is one tap away.
class MonthSummaryView extends ConsumerWidget {
  const MonthSummaryView({super.key, required this.month});
  final DateTime month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final key = Dates.toApiMonth(month);
    return AsyncBody<MonthGrid>(
      value: ref.watch(monthGridProvider(key)),
      onRetry: () => ref.invalidate(monthGridProvider(key)),
      data: (g) {
        if (g.rows.isEmpty) return EmptyView(message: s.emptyStaffHome, icon: Icons.people_outline);
        return RefreshIndicator(
          onRefresh: () => ref.refresh(monthGridProvider(key).future),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                child: Material(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: const BorderSide(color: AppColors.line, width: 1.5),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                        child: Row(
                          children: [
                            Expanded(child: Text(s.monthPersonHeader, style: _head)),
                            Text(s.daysPresentHeader, style: _head),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      for (final r in g.rows)
                        Builder(
                          builder: (context) {
                            final t = MonthTally(r.totals);
                            return ListTile(
                              key: Key('monthPerson_${r.employee.id}'),
                              leading: InitialsAvatar(r.employee.name),
                              title: Text(r.employee.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(t.line(s)),
                              trailing: Text(
                                '${_n(t.present)} / ${_n(t.workDays)}',
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                              ),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => PersonMonthScreen(employee: r.employee, month: month),
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
              Card(
                margin: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                child: ListTile(
                  key: const Key('openMonthGrid'),
                  leading: const Icon(Icons.grid_on_rounded),
                  title: Text(s.seeEveryoneGrid, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(s.gridHint),
                  trailing: Text(
                    s.gridLabel,
                    style: const TextStyle(color: AppColors.mintDark, fontWeight: FontWeight.w800),
                  ),
                  onTap: () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute<void>(builder: (_) => MonthGridScreen(month: month))),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static const _head = TextStyle(fontSize: 12.5, color: AppColors.muted, fontWeight: FontWeight.w700);
}

/// One person's month: legend on top, a normal calendar, totals in words.
class PersonMonthScreen extends ConsumerStatefulWidget {
  const PersonMonthScreen({super.key, required this.employee, required this.month});
  final EmployeeRef employee;
  final DateTime month;

  @override
  ConsumerState<PersonMonthScreen> createState() => _PersonMonthScreenState();
}

class _PersonMonthScreenState extends ConsumerState<PersonMonthScreen> {
  late DateTime _month = widget.month;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final q = (month: Dates.toApiMonth(_month), employeeId: widget.employee.id);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.employee.name),
            Text(
              Dates.monthTitle(_month, s.languageCode),
              style: const TextStyle(fontSize: 13, color: AppColors.muted),
            ),
          ],
        ),
      ),
      body: AsyncBody<MonthGrid>(
        value: ref.watch(employeeMonthProvider(q)),
        onRetry: () => ref.invalidate(employeeMonthProvider(q)),
        data: (g) {
          final row = g.rows.where((r) => r.employee.id == widget.employee.id).firstOrNull;
          final t = MonthTally(row?.totals ?? const {});
          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
            children: [
              MonthSwitcher(month: _month, onChanged: (m) => setState(() => _month = m)),
              const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: StatusLegend()),
              AttendanceCalendar(
                month: _month,
                days: row?.days ?? const {},
                onDay: (d) => editDay(context, ref, widget.employee.id, d),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  s.personMonthHint,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.muted, fontSize: 13),
                ),
              ),
              const SizedBox(height: 10),
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  key: const Key('personMonthTotals'),
                  title: Text(
                    s.daysPresentOf(t.present, t.workDays),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(t.line(s)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Opens one person's day from a calendar: the same "what happened?" sheet as Home.
Future<void> editDay(BuildContext context, WidgetRef ref, String employeeId, String date) async {
  final s = context.s;
  try {
    final rows = await ref.read(dayAttendanceProvider(date).future);
    final row = rows.where((r) => r.employee.id == employeeId).firstOrNull;
    if (row == null || !context.mounted) return;
    final choice = await showStatusQuickSheet(
      context,
      row: row,
      date: date,
      onDetails: () => showAttendanceDetail(context, row: row, date: date),
    );
    if (choice == null || !context.mounted) return;
    await ref
        .read(attendanceApiProvider)
        .overrideStatus(
          employeeId: employeeId,
          date: date,
          status: choice.status,
          leaveType: choice.leaveType,
          reason: choice.reason,
        );
    invalidateAttendance(ref);
    if (context.mounted) showSnack(context, s.markedAs(row.employee.name, s.statusShort(choice.status)));
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

/// Everyone, day by day: good for checking before salary.
class MonthGridScreen extends StatelessWidget {
  const MonthGridScreen({super.key, required this.month});
  final DateTime month;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Scaffold(
      appBar: AppBar(title: Text('${s.seeEveryoneGrid} · ${Dates.monthTitle(month, s.languageCode)}')),
      body: Column(
        children: [
          const Padding(padding: EdgeInsets.fromLTRB(16, 4, 16, 4), child: StatusLegend()),
          Expanded(child: MonthGridView(month: Dates.toApiMonth(month))),
        ],
      ),
    );
  }
}
