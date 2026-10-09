import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/pickers.dart';
import '../employee_providers.dart';

/// Own attendance calendar for a month.
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
      appBar: AppBar(title: Text(s.myAttendance)),
      body: Column(
        children: [
          MonthSwitcher(month: _month, onChanged: (m) => setState(() => _month = m)),
          Expanded(
            child: AsyncBody<MonthGrid>(
              value: grid,
              onRetry: () => ref.invalidate(myMonthProvider(key)),
              data: (g) {
                final row = g.rows.firstOrNull;
                final days = row?.days ?? const <String, String>{};
                return RefreshableList(
                  onRefresh: () => ref.refresh(myMonthProvider(key).future),
                  padding: const EdgeInsets.only(bottom: 32),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: _Calendar(month: _month, days: days),
                    ),
                    if (row != null && row.totals.isNotEmpty) ...[
                      SectionHeader(s.totals),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final e in row.totals.entries)
                              Chip(
                                backgroundColor: AppColors.forStatus(_statusKey(e.key)).withValues(alpha: 0.15),
                                side: BorderSide.none,
                                label: Text('${s.statusLabel(_statusKey(e.key))}: ${e.value}'),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Calendar extends StatelessWidget {
  const _Calendar({required this.month, required this.days});
  final DateTime month;
  final Map<String, String> days;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final first = DateTime(month.year, month.month);
    final leading = first.weekday % 7; // Sunday = 0
    final count = Dates.daysInMonth(month);
    final today = Dates.today();
    final cells = <Widget>[
      for (var d = 0; d < 7; d++)
        Center(
          child: Text(
            s.weekdayShort(d),
            style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.black54),
          ),
        ),
      for (var i = 0; i < leading; i++) const SizedBox.shrink(),
      for (var day = 1; day <= count; day++)
        Builder(
          builder: (_) {
            final date = DateTime(month.year, month.month, day);
            final status = days[Dates.toApiDate(date)];
            final color = status == null ? Colors.transparent : AppColors.forStatus(status);
            final isToday = Dates.isSameDay(date, today);
            return Container(
              margin: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: status == null ? 0 : 0.22),
                borderRadius: BorderRadius.circular(10),
                border: isToday ? Border.all(color: AppColors.mintDark, width: 2) : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('$day', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  if (status != null && status != 'not_marked')
                    Text(
                      s.statusCode(status),
                      style: TextStyle(fontSize: 11, color: Color.lerp(color, Colors.black, 0.4)),
                    ),
                ],
              ),
            );
          },
        ),
    ];
    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 0.85,
      children: cells,
    );
  }
}

/// Month totals use camelCase keys (`halfDay`, `weekOff`, `notMarked`); statuses use snake_case.
String _statusKey(String key) => key.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');
