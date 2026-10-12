import 'package:flutter/material.dart';

import '../i18n/strings.dart';
import '../theme/app_theme.dart';
import '../utils/dates.dart';

/// Legend always on top: symbol and word for every status (no "L" vs "LV").
class StatusLegend extends StatelessWidget {
  const StatusLegend({super.key});

  static const statuses = ['present', 'late', 'absent', 'half_day', 'leave', 'week_off'];

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Wrap(
      key: const Key('statusLegend'),
      spacing: 10,
      runSpacing: 6,
      children: [
        for (final st in statuses)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(StatusStyle.of(st).icon, size: 15, color: StatusStyle.of(st).fg),
              const SizedBox(width: 3),
              Text(
                st == 'week_off' ? s.offShort : s.statusShort(st),
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ],
          ),
      ],
    );
  }
}

/// A normal Monday-first month calendar: each day shows its date and a status
/// symbol on a tint. Tap a day to open it.
class AttendanceCalendar extends StatelessWidget {
  const AttendanceCalendar({super.key, required this.month, required this.days, this.onDay});
  final DateTime month;

  /// `YYYY-MM-DD` → display status (null / missing = not counted yet).
  final Map<String, String?> days;
  final ValueChanged<String>? onDay;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final first = DateTime(month.year, month.month);
    final lead = first.weekday - 1; // Monday = 0
    final count = Dates.daysInMonth(month);
    final today = Dates.today();
    final weekdays = [for (var i = 0; i < 7; i++) Dates.weekdayOnly(DateTime(2024, 1, 1 + i), s.languageCode)];
    return Column(
      children: [
        Row(
          children: [
            for (final w in weekdays)
              Expanded(
                child: Center(
                  child: Text(
                    w,
                    style: const TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          children: [
            for (var i = 0; i < lead; i++) const SizedBox.shrink(),
            for (var d = 1; d <= count; d++)
              Builder(
                builder: (_) {
                  final date = DateTime(month.year, month.month, d);
                  final key = Dates.toApiDate(date);
                  final st = days[key];
                  final future = date.isAfter(today);
                  final style = StatusStyle.of(st);
                  final shown = st != null && st != 'not_marked' && !future;
                  return Semantics(
                    button: onDay != null && !future,
                    label: '$d · ${s.statusLabel(st)}',
                    excludeSemantics: true,
                    child: Material(
                      color: shown ? style.bg : (future ? Colors.transparent : Colors.white),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: Dates.isSameDay(date, today)
                            ? const BorderSide(color: AppColors.mint, width: 2)
                            : BorderSide(color: future ? AppColors.lineSoft : AppColors.line),
                      ),
                      child: InkWell(
                        key: Key('calDay_$key'),
                        borderRadius: BorderRadius.circular(10),
                        onTap: onDay == null || future ? null : () => onDay!(key),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '$d',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: future ? AppColors.muted : AppColors.ink,
                              ),
                            ),
                            if (shown) Icon(style.icon, size: 14, color: style.fg),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ],
    );
  }
}
