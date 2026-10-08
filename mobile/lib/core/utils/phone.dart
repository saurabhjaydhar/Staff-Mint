/// Indian phone helpers. The server normalises too; the client only
/// validates and cleans contacts-picker input.
class Phones {
  Phones._();

  /// Returns a 10-digit Indian mobile, or an E.164 number for other
  /// countries, or null if it does not look like a phone number.
  static String? normalize(String raw) {
    var digits = raw.replaceAll(RegExp(r'[^0-9+]'), '');
    if (digits.isEmpty) return null;
    if (digits.startsWith('+')) {
      final rest = digits.substring(1).replaceAll('+', '');
      if (rest.startsWith('91') && rest.length == 12) {
        return _validIndian(rest.substring(2));
      }
      return rest.length >= 8 && rest.length <= 15 ? '+$rest' : null;
    }
    digits = digits.replaceAll('+', '');
    if (digits.length == 12 && digits.startsWith('91')) {
      digits = digits.substring(2);
    } else if (digits.length == 11 && digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    return _validIndian(digits);
  }

  static String? _validIndian(String d) => RegExp(r'^[6-9][0-9]{9}$').hasMatch(d) ? d : null;

  static bool isValid(String raw) => normalize(raw) != null;

  /// `9876543210` → `+91 98765 43210`.
  static String display(String phone) {
    final n = normalize(phone);
    if (n == null || n.startsWith('+')) return phone;
    return '+91 ${n.substring(0, 5)} ${n.substring(5)}';
  }
}
