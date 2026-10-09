import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n/strings.dart';
import '../theme/app_theme.dart';
import '../utils/dates.dart';
import '../utils/money.dart';

/// `‹ October 2026 ›` month switcher.
class MonthSwitcher extends StatelessWidget {
  const MonthSwitcher({super.key, required this.month, required this.onChanged, this.allowFuture = false});
  final DateTime month;
  final ValueChanged<DateTime> onChanged;
  final bool allowFuture;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isCurrent = month.year == now.year && month.month == now.month;
    return _Switcher(
      label: Dates.monthTitle(month, context.s.languageCode),
      onPrev: () => onChanged(Dates.addMonths(month, -1)),
      onNext: (!allowFuture && isCurrent) ? null : () => onChanged(Dates.addMonths(month, 1)),
    );
  }
}

/// `‹ आज · शुक्र, 9 अक्टू ›` day switcher with a calendar picker in the middle.
class DateSwitcher extends StatelessWidget {
  const DateSwitcher({super.key, required this.date, required this.onChanged});
  final DateTime date;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final today = Dates.today();
    final isToday = Dates.isSameDay(date, today);
    final isYesterday = Dates.isSameDay(date, today.subtract(const Duration(days: 1)));
    final day = Dates.weekdayShort(date, s.languageCode);
    final label = isToday
        ? '${s.today} · $day'
        : isYesterday
        ? '${s.yesterday} · $day'
        : day;
    return _Switcher(
      label: label,
      icon: Icons.calendar_month_rounded,
      onPrev: () => onChanged(date.subtract(const Duration(days: 1))),
      onNext: isToday ? null : () => onChanged(date.add(const Duration(days: 1))),
      onLabel: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: DateTime(today.year - 2),
          lastDate: today,
        );
        if (picked != null) onChanged(picked);
      },
    );
  }
}

class _Switcher extends StatelessWidget {
  const _Switcher({required this.label, required this.onPrev, required this.onNext, this.onLabel, this.icon});
  final String label;
  final VoidCallback onPrev;
  final VoidCallback? onNext;
  final VoidCallback? onLabel;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final loc = MaterialLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Row(
        children: [
          IconButton(
            tooltip: loc.previousPageTooltip,
            icon: const Icon(Icons.chevron_left_rounded, size: 30),
            onPressed: onPrev,
          ),
          Expanded(
            child: Center(
              child: Material(
                color: Colors.white,
                shape: const StadiumBorder(side: BorderSide(color: AppColors.line, width: 1.5)),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: onLabel,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null) ...[
                          Icon(icon, size: 18, color: AppColors.mintDark),
                          const SizedBox(width: 6),
                        ],
                        Flexible(
                          child: Text(
                            label,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: loc.nextPageTooltip,
            icon: const Icon(Icons.chevron_right_rounded, size: 30),
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}

/// Rupee amount input. Validates into paise via [Money.parseRupees].
class AmountField extends StatelessWidget {
  const AmountField({super.key, required this.controller, this.label, this.allowZero = false, this.autofocus = false});
  final TextEditingController controller;
  final String? label;
  final bool allowZero;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return TextFormField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      decoration: InputDecoration(labelText: label ?? s.amount, prefixText: '₹ '),
      validator: (v) {
        final p = Money.parseRupees(v ?? '');
        if (p == null || (!allowZero && p <= 0)) return s.invalidAmount;
        return null;
      },
    );
  }
}

/// A tappable field that opens a time picker; value is `HH:mm`.
class TimeField extends StatelessWidget {
  const TimeField({super.key, required this.label, required this.value, required this.onChanged});
  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final parts = value.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts.first) ?? 9,
      minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
    );
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        final t = await showTimePicker(context: context, initialTime: initial);
        if (t != null) onChanged(Dates.toHhmm(t.hour, t.minute));
      },
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.access_time_rounded)),
        child: Text(Dates.hhmmToDisplay(value, context.s.languageCode), style: Theme.of(context).textTheme.titleMedium),
      ),
    );
  }
}

/// A tappable field that opens a date picker; value is a [DateTime].
class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
  });
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final DateTime? firstDate;
  final DateTime? lastDate;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        final d = await showDatePicker(
          context: context,
          initialDate: value ?? now,
          firstDate: firstDate ?? DateTime(now.year - 5),
          lastDate: lastDate ?? DateTime(now.year + 2),
        );
        if (d != null) onChanged(d);
      },
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.calendar_today_rounded)),
        child: Text(
          value == null ? '—' : Dates.pretty(value!, context.s.languageCode),
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
    );
  }
}

/// Weekday multi-select chips (0 = Sunday).
class WeekdayChips extends StatelessWidget {
  const WeekdayChips({super.key, required this.selected, required this.onChanged});
  final List<int> selected;
  final ValueChanged<List<int>> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var d = 0; d < 7; d++)
          FilterChip(
            label: Text(s.weekdayShort(d)),
            selected: selected.contains(d),
            onSelected: (on) {
              final next = [...selected]..remove(d);
              if (on) next.add(d);
              next.sort();
              onChanged(next);
            },
          ),
      ],
    );
  }
}
