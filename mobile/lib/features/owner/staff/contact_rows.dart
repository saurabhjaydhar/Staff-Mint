import '../../../core/utils/phone.dart';

/// One row of the contacts picker: a person with a mobile number we can invite,
/// or (when [phone] is null) a contact we show greyed out so nobody seems "missing".
class ContactRow {
  const ContactRow({required this.name, required this.phone, required this.shown});
  final String name;

  /// Normalised mobile (10-digit Indian, or +E.164), or null if the contact has none.
  final String? phone;

  /// The number as saved in the phone, for display.
  final String shown;

  bool get canAdd => phone != null;
}

/// Builds picker rows from phone contacts, given as (name, [(number, normalizedNumber)]).
///
/// - Every contact with at least one number is listed.
/// - For each contact the best number wins: an Indian mobile, else a foreign mobile.
///   Both the saved number and the phone's own normalised copy are tried, because
///   the normalised copy is sometimes missing or computed for the wrong country.
/// - Mobiles appear once even if saved under two names; contacts without a mobile
///   (landlines, short codes) come last and can't be ticked.
List<ContactRow> buildContactRows(Iterable<(String, List<(String, String?)>)> contacts) {
  final seen = <String>{};
  final ok = <ContactRow>[];
  final noMobile = <ContactRow>[];
  for (final (rawName, phones) in contacts) {
    if (phones.isEmpty) continue;
    String? best;
    String shown = phones.first.$1;
    for (final (number, normalized) in phones) {
      for (final candidate in [number, ?normalized]) {
        final n = Phones.normalize(candidate);
        if (n == null) continue;
        final indian = !n.startsWith('+');
        if (best == null || (indian && best.startsWith('+'))) {
          best = n;
          shown = number;
        }
      }
      if (best != null && !best.startsWith('+')) break;
    }
    final name = rawName.trim().isEmpty ? shown : rawName.trim();
    if (best == null) {
      noMobile.add(ContactRow(name: name, phone: null, shown: shown));
    } else if (seen.add(best)) {
      ok.add(ContactRow(name: name, phone: best, shown: shown));
    }
  }
  int byName(ContactRow a, ContactRow b) => a.name.toLowerCase().compareTo(b.name.toLowerCase());
  return [...ok..sort(byName), ...noMobile..sort(byName)];
}
