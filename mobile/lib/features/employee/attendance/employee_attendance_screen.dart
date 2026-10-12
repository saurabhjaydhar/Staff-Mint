import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/providers.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/attendance_calendar.dart';
import '../../../core/widgets/bilingual.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/pickers.dart';
import '../../owner/attendance/month_summary.dart' show MonthTally;
import '../employee_providers.dart';
import '../punch/punch_providers.dart';

/// My attendance: legend on top, a normal calendar, totals in words. Tap a
/// day to see it; a missed day has "I was there — ask owner to fix".
class EmployeeAttendanceScreen extends ConsumerStatefulWidget {
  const EmployeeAttendanceScreen({super.key});

  @override
  ConsumerState<EmployeeAttendanceScreen> createState() => _EmployeeAttendanceScreenState();
}

class _EmployeeAttendanceScreenState extends ConsumerState<EmployeeAttendanceScreen> {
  DateTime _month = Dates.firstOfMonth(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final key = Dates.toApiMonth(_month);
    final grid = ref.watch(myMonthProvider(key));
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(subtitle: Dates.monthTitle(_month, s.languageCode), title: s.myAttendance),
            MonthSwitcher(month: _month, onChanged: (m) => setState(() => _month = m)),
            Expanded(
              child: AsyncBody<MonthGrid>(
                value: grid,
                onRetry: () => ref.invalidate(myMonthProvider(key)),
                data: (g) {
                  final row = g.rows.firstOrNull;
                  final days = row?.days ?? const <String, String>{};
                  final t = MonthTally(row?.totals ?? const {});
                  return RefreshableList(
                    onRefresh: () => ref.refresh(myMonthProvider(key).future),
                    padding: const EdgeInsets.only(bottom: 32),
                    children: [
                      const Padding(padding: EdgeInsets.fromLTRB(16, 4, 16, 8), child: StatusLegend()),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 14),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: AppColors.line, width: 1.5),
                        ),
                        child: AttendanceCalendar(month: _month, days: days, onDay: (d) => _openDay(d, days[d])),
                      ),
                      if (row != null)
                        Card(
                          margin: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                          child: ListTile(
                            key: const Key('myMonthTotals'),
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
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openDay(String date, String? status) async {
    final isToday = date == Dates.toApiDate(DateTime.now());
    final record = isToday ? ref.read(employeeTodayProvider).value?.info.record : null;
    final missed = status == null || status == 'absent' || status == 'not_marked';
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (ctx) => _DaySheet(date: date, status: status, record: record, canAskFix: missed && !isToday),
    );
  }
}

class _DaySheet extends ConsumerStatefulWidget {
  const _DaySheet({required this.date, required this.status, required this.record, required this.canAskFix});
  final String date;
  final String? status;
  final Attendance? record;
  final bool canAskFix;

  @override
  ConsumerState<_DaySheet> createState() => _DaySheetState();
}

class _DaySheetState extends ConsumerState<_DaySheet> {
  final _note = TextEditingController();
  bool _asking = false;
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final s = context.s;
    setState(() => _busy = true);
    try {
      final sent = await ref
          .read(attendanceApiProvider)
          .requestFix(widget.date, note: _note.text.trim().isEmpty ? null : _note.text.trim());
      if (!mounted) return;
      Navigator.pop(context);
      showSnack(context, sent ? s.askSent : s.askAlreadySent);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final lang = s.languageCode;
    final r = widget.record;
    final firstIn = r?.firstIn;
    final lastOut = r?.lastOut;
    final st = StatusStyle.of(widget.status);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(st.icon, color: st.fg),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${Dates.prettyApiDate(widget.date, lang)} · ${s.statusLabel(widget.status)}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (firstIn != null)
            Text(
              s.dayInOut(
                Dates.time(firstIn.clientTime, lang),
                lastOut == null ? null : Dates.time(lastOut.clientTime, lang),
              ),
              key: const Key('dayInOut'),
            ),
          if (widget.canAskFix) ...[
            Text(s.noCheckInThatDay, style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 10),
            if (!_asking)
              OutlinedButton.icon(
                key: const Key('askFix'),
                onPressed: () => setState(() => _asking = true),
                icon: const Icon(Icons.flag_outlined),
                label: Text(s.iWasThere),
              )
            else ...[
              TextField(
                key: const Key('askFixNote'),
                controller: _note,
                autofocus: true,
                maxLength: 300,
                decoration: InputDecoration(labelText: s.fixNoteHint),
              ),
              FilledButton(key: const Key('askFixSend'), onPressed: _busy ? null : _send, child: Text(s.sendToOwner)),
            ],
          ],
        ],
      ),
    );
  }
}
