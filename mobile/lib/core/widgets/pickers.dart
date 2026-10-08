import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n/strings.dart';
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left_rounded, size: 32),
          onPressed: () => onChanged(Dates.addMonths(month, -1)),
        ),
        Text(Dates.monthTitle(month, context.s.languageCode), style: Theme.of(context).textTheme.titleMedium),
        IconButton(
          icon: const Icon(Icons.chevron_right_rounded, size: 32),
          onPressed: (!allowFuture && isCurrent) ? null : () => onChanged(Dates.addMonths(month, 1)),
        ),
      ],
    );
  }
}

/// `‹ Wed, 14 Oct ›` day switcher with a calendar picker in the middle.
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
    final label = isToday
        ? '${s.today} · ${Dates.weekdayShort(date, s.languageCode)}'
        : isYesterday
        ? '${s.yesterday} · ${Dates.weekdayShort(date, s.languageCode)}'
        : Dates.weekdayShort(date, s.languageCode);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left_rounded, size: 32),
          onPressed: () => onChanged(date.subtract(const Duration(days: 1))),
        ),
        TextButton.icon(
          icon: const Icon(Icons.calendar_month_rounded),
          label: Text(label),
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: date,
              firstDate: DateTime(today.year - 2),
              lastDate: today,
            );
            if (picked != null) onChanged(picked);
          },
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right_rounded, size: 32),
          onPressed: isToday ? null : () => onChanged(date.add(const Duration(days: 1))),
        ),
      ],
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
