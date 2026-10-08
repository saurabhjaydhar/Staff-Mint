import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/pickers.dart';
import '../providers/owner_providers.dart';
import 'attendance_detail_sheet.dart';
import 'month_grid.dart';

class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});

  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  bool _monthMode = false;
  DateTime _date = Dates.today();
  DateTime _month = Dates.firstOfMonth(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.navAttendance),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: false, label: Text(s.dayView)),
                ButtonSegment(value: true, label: Text(s.monthView)),
              ],
              selected: {_monthMode},
              showSelectedIcon: false,
              onSelectionChanged: (v) => setState(() => _monthMode = v.first),
            ),
          ),
        ],
      ),
      body: _monthMode
          ? Column(
              children: [
                MonthSwitcher(month: _month, onChanged: (m) => setState(() => _month = m)),
                Expanded(child: MonthGridView(month: Dates.toApiMonth(_month))),
              ],
            )
          : Column(
              children: [
                DateSwitcher(date: _date, onChanged: (d) => setState(() => _date = d)),
                Expanded(child: _DayList(date: Dates.toApiDate(_date))),
              ],
            ),
    );
  }
}

class _DayList extends ConsumerWidget {
  const _DayList({required this.date});
  final String date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final rows = ref.watch(dayAttendanceProvider(date));
    return AsyncBody<List<DayRow>>(
      value: rows,
      onRetry: () => ref.invalidate(dayAttendanceProvider(date)),
      data: (list) => RefreshableList(
        onRefresh: () => ref.refresh(dayAttendanceProvider(date).future),
        children: [
          if (list.isEmpty) EmptyView(message: s.noAttendanceRows, icon: Icons.event_busy_outlined),
          for (final r in list) _DayRowTile(row: r, date: date),
        ],
      ),
    );
  }
}

class _DayRowTile extends StatelessWidget {
  const _DayRowTile({required this.row, required this.date});
  final DayRow row;
  final String date;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final rec = row.record;
    final inP = rec?.firstIn;
    final outP = rec?.lastOut;
    final times = [
      if (inP != null) '${s.checkInLabel} ${Dates.time(inP.clientTime, s.languageCode)}',
      if (outP != null) '${s.checkOutLabel} ${Dates.time(outP.clientTime, s.languageCode)}',
    ].join(' · ');
    final hasFlags = (rec?.flags.isNotEmpty ?? false) || (rec?.punches.any((p) => p.flags.isNotEmpty) ?? false);
    final pendingApproval = rec?.punches.any((p) => p.isPendingApproval) ?? false;
    return Card(
      child: ListTile(
        leading: InitialsAvatar(row.employee.name),
        title: Text(row.employee.name),
        subtitle: Text(
          [
            if (times.isNotEmpty) times,
            if ((rec?.lateMinutes ?? 0) > 0) s.lateBy(rec!.lateMinutes),
            if (rec?.overridden ?? false) s.overriddenTag,
          ].join('\n').ifEmpty(row.employee.designation ?? ''),
        ),
        isThreeLine: times.isNotEmpty && ((rec?.lateMinutes ?? 0) > 0 || (rec?.overridden ?? false)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (pendingApproval) const Icon(Icons.hourglass_top_rounded, color: AppColors.late, size: 20),
            if (hasFlags) const Icon(Icons.flag_rounded, color: AppColors.late, size: 20),
            const SizedBox(width: 4),
            StatusChip(status: row.displayStatus, dense: true),
          ],
        ),
        onTap: () => showAttendanceDetail(context, row: row, date: date),
      ),
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
