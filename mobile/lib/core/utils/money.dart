import 'package:intl/intl.dart';

/// Money helpers. The API always uses integer paise (₹1 = 100 paise).
class Money {
  Money._();

  static final NumberFormat _whole = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
  static final NumberFormat _decimal = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
  static final NumberFormat _plain = NumberFormat.decimalPattern('en_IN');

  /// `1200000` → `₹12,000`; `12345678` → `₹1,23,456.78`; `-50000` → `-₹500`.
  /// Paise are shown only when the amount is not a whole rupee
  /// (or when [alwaysShowPaise] is set).
  static String format(int paise, {bool alwaysShowPaise = false}) {
    final negative = paise < 0;
    final abs = paise.abs();
    final rupees = abs / 100;
    final f = (alwaysShowPaise || abs % 100 != 0) ? _decimal : _whole;
    final s = f.format(rupees);
    return negative ? '-$s' : s;
  }

  /// Signed variant for deductions: `-₹500` / `+₹500`.
  static String signed(int paise) => paise >= 0 ? '+${format(paise)}' : format(paise);

  /// Rupee amount without the symbol, Indian grouping: `12,000`.
  static String plainRupees(int paise) => _plain.format(paise ~/ 100);

  /// Parses owner input into paise. Accepts `12000`, `12,000`, `₹12,000/-`,
  /// `12000.50`, `12k`, `1.5 lakh`. Returns null for invalid/empty input.
  static int? parseRupees(String input) {
    var s = input.trim().toLowerCase();
    if (s.isEmpty) return null;
    s = s
        .replaceAll('₹', '')
        .replaceAll('rs.', '')
        .replaceAll('rs', '')
        .replaceAll('inr', '')
        .replaceAll('/-', '')
        .replaceAll(',', '')
        .replaceAll(' ', '');
    var multiplier = 1.0;
    if (s.endsWith('k')) {
      multiplier = 1000;
      s = s.substring(0, s.length - 1);
    } else if (s.endsWith('lakh') || s.endsWith('lac')) {
      multiplier = 100000;
      s = s.replaceAll(RegExp(r'(lakh|lac)$'), '');
    }
    final value = double.tryParse(s);
    if (value == null || value < 0 || value.isNaN || value.isInfinite) {
      return null;
    }
    return (value * multiplier * 100).round();
  }
}
