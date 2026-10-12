/// Indian phone helpers. The server normalises too; the client only
/// validates and cleans contacts-picker input.
class Phones {
  Phones._();

  /// Returns a 10-digit Indian mobile, or an E.164 number for other
  /// countries, or null if it does not look like a phone number.
  static String? normalize(String raw) {
    var digits = raw.trim().replaceAll(RegExp(r'[^0-9+]'), '');
    if (digits.isEmpty) return null;
    // International form: "+91…", or "0091…" as some phones save it.
    var intl = false;
    if (digits.startsWith('+')) {
      intl = true;
      digits = digits.substring(1).replaceAll('+', '');
    } else {
      digits = digits.replaceAll('+', '');
      if (digits.startsWith('00')) {
        intl = true;
        digits = digits.substring(2);
      }
    }
    if (intl) {
      if (digits.startsWith('91')) {
        var nsn = digits.substring(2);
        if (nsn.length == 11 && nsn.startsWith('0')) nsn = nsn.substring(1); // "+91 0 98765 43210"
        return _validIndian(nsn);
      }
      return digits.length >= 8 && digits.length <= 15 ? '+$digits' : null;
    }
    if (digits.length == 12 && digits.startsWith('91')) {
      digits = digits.substring(2);
    } else if (digits.length == 11 && digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    return _validIndian(digits);
  }

  static String? _validIndian(String d) => RegExp(r'^[6-9][0-9]{9}$').hasMatch(d) ? d : null;

  static bool isValid(String raw) => normalize(raw) != null;

  /// Digits for a `wa.me/<digits>` link: `9876543210` → `919876543210`.
  static String? waDigits(String phone) {
    final n = normalize(phone);
    if (n == null) return null;
    return n.startsWith('+') ? n.substring(1) : '91$n';
  }

  /// `9876543210` → `+91 98765 43210`.
  static String display(String phone) {
    final n = normalize(phone);
    if (n == null || n.startsWith('+')) return phone;
    return '+91 ${n.substring(0, 5)} ${n.substring(5)}';
  }
}
