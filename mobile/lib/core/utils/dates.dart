import 'package:intl/intl.dart';

/// Date helpers matching the API formats: `YYYY-MM-DD`, `YYYY-MM`, `HH:mm`.
class Dates {
  Dates._();

  // API formats are locale-independent.
  static final DateFormat _day = DateFormat('yyyy-MM-dd', 'en_US');
  static final DateFormat _month = DateFormat('yyyy-MM', 'en_US');

  static String toApiDate(DateTime d) => _day.format(d);
  static String toApiMonth(DateTime d) => _month.format(d);

  static DateTime parseDate(String s) => DateTime.tryParse(s) ?? DateTime.now();

  static DateTime parseMonth(String s) {
    final parts = s.split('-');
    if (parts.length >= 2) {
      return DateTime(int.tryParse(parts[0]) ?? DateTime.now().year, int.tryParse(parts[1]) ?? 1);
    }
    return DateTime.now();
  }

  static DateTime today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  static DateTime firstOfMonth(DateTime d) => DateTime(d.year, d.month);

  static DateTime addMonths(DateTime d, int months) => DateTime(d.year, d.month + months);

  static int daysInMonth(DateTime d) => DateTime(d.year, d.month + 1, 0).day;

  static bool isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  /// `14 Oct` (or Hindi month names when [locale] is `hi`).
  static String dayMonth(DateTime d, [String locale = 'en']) => _fmt('d MMM', locale).format(d);

  /// `14 Oct 2026` (or Hindi month names when [locale] is `hi`).
  static String pretty(DateTime d, [String locale = 'en']) => _fmt('d MMM yyyy', locale).format(d);

  static String prettyApiDate(String s, [String locale = 'en']) {
    final d = DateTime.tryParse(s);
    return d == null ? s : pretty(d, locale);
  }

  /// `Wed, 14 Oct`.
  static String weekdayShort(DateTime d, [String locale = 'en']) => _fmt('EEE, d MMM', locale).format(d);

  /// "Sat" / "शनि".
  static String weekdayOnly(DateTime d, [String locale = 'en']) => _fmt('EEE', locale).format(d);

  /// `October` from an API month (`2026-10`).
  static String monthOnly(String apiMonth, [String locale = 'en']) => _fmt('MMMM', locale).format(parseMonth(apiMonth));

  /// "Sunday, Monday" / "रविवार, सोमवार" for weekday numbers (0 = Sunday).
  static String weekdayNames(List<int> days, [String locale = 'en']) {
    final fmt = _fmt('EEEE', locale);
    // 11 Oct 2026 is a Sunday.
    return days.map((d) => fmt.format(DateTime(2026, 10, 11 + d))).join(', ');
  }

  /// `October 2026`.
  static String monthTitle(DateTime d, [String locale = 'en']) => _fmt('MMMM yyyy', locale).format(d);

  /// Local time of an instant: `9:05 AM`.
  static String time(DateTime instant, [String locale = 'en']) => _fmt('h:mm a', locale).format(instant.toLocal());

  /// Compact clock for ledger margins: `8:56` (12-hour, no AM/PM).
  static String clock(DateTime instant) => DateFormat('h:mm', 'en_US').format(instant.toLocal());

  /// Minutes since midnight for `HH:mm`, or null.
  static int? hhmmToMinutes(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    return h == null || m == null ? null : h * 60 + m;
  }

  /// `09:00` → `9:00 AM`.
  static String hhmmToDisplay(String hhmm, [String locale = 'en']) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return hhmm;
    final dt = DateTime(2000, 1, 1, int.tryParse(parts[0]) ?? 0, int.tryParse(parts[1]) ?? 0);
    return _fmt('h:mm a', locale).format(dt);
  }

  static String toHhmm(int hour, int minute) =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  static String durationHm(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  /// Display formatter. Falls back to built-in `en_US` data when locale data
  /// has not been initialised (e.g. in tests) instead of throwing.
  static DateFormat _fmt(String pattern, String locale) {
    try {
      return DateFormat(pattern, locale == 'hi' ? 'hi' : 'en');
    } catch (_) {
      return DateFormat(pattern, 'en_US');
    }
  }
}
