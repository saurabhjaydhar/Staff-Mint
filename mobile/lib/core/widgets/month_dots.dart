import 'package:flutter/material.dart';

import '../i18n/strings.dart';
import '../theme/app_theme.dart';
import '../utils/dates.dart';

/// Month strip of small day squares (tint + one-letter code, so colour is
/// never the only signal), from day 1 to today.
class MonthDots extends StatelessWidget {
  const MonthDots({super.key, required this.month, required this.days, required this.title, this.trailing});
  final DateTime month;
  final Map<String, String> days;
  final String title;
  final String? trailing;

  static Color _tint(String? status) {
    switch (status) {
      case 'present':
      case 'checked_in':
        return const Color(0xFFBDE8D1);
      case 'late':
        return const Color(0xFFF8DB9C);
      case 'absent':
        return const Color(0xFFF3B9B4);
      case 'half_day':
        return const Color(0xFFFAD2B0);
      case 'leave':
        return const Color(0xFFD5D2FF);
      default:
        return const Color(0xFFE6E1D5);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final today = Dates.today();
    final isCurrent = month.year == today.year && month.month == today.month;
    final last = isCurrent ? today.day : Dates.daysInMonth(month);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              ),
              if (trailing != null)
                Text(
                  trailing!,
                  key: const Key('monthEarned'),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.mint),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (var d = 1; d <= last; d++)
                Builder(
                  builder: (_) {
                    final date = DateTime(month.year, month.month, d);
                    final st = days[Dates.toApiDate(date)];
                    final isToday = Dates.isSameDay(date, today);
                    final empty = isToday && (st == null || st == 'not_marked');
                    return Tooltip(
                      message: '$d · ${s.statusLabel(st)}',
                      child: Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: empty ? Colors.white : _tint(st),
                          borderRadius: BorderRadius.circular(6),
                          border: isToday ? Border.all(color: AppColors.mint, width: 2) : null,
                        ),
                        child: Text(
                          empty ? '$d' : s.statusCode(st),
                          style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: AppColors.ink),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}
