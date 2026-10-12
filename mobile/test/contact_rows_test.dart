import 'package:flutter_test/flutter_test.dart';
import 'package:staffmint/features/owner/staff/contact_rows.dart';

void main() {
  test('every contact with a number is listed; mobiles first, the rest greyed out at the end', () {
    final rows = buildContactRows([
      ('Raju', [('0091 98765 43210', null)]),
      ('pooja', [('+91 098765 00003', '+910987650000')]), // wrong normalised copy: saved number still wins
      ('Shop landline', [('022 2345 6789', '+912223456789')]),
      ('Amit', [('022 2345 0000', null), ('98765 11111', null)]), // landline first, mobile second
      ('Raju again', [('+919876543210', '+919876543210')]), // same mobile under another name
      ('Dubai cousin', [('+971 50 123 4567', null)]),
      ('', [('98765 22222', null)]), // no name
      ('No number', []),
    ]);
    expect(rows.map((r) => r.name).toList(), ['98765 22222', 'Amit', 'Dubai cousin', 'pooja', 'Raju', 'Shop landline']);
    expect(rows.firstWhere((r) => r.name == 'Raju').phone, '9876543210');
    expect(rows.firstWhere((r) => r.name == 'pooja').phone, '9876500003');
    expect(rows.firstWhere((r) => r.name == 'Amit').phone, '9876511111');
    expect(rows.firstWhere((r) => r.name == 'Dubai cousin').phone, '+971501234567');
    final landline = rows.last;
    expect(landline.canAdd, isFalse);
    expect(landline.shown, '022 2345 6789');
  });

  test('a normalised copy rescues a number saved in an odd way', () {
    final rows = buildContactRows([
      ('Kavita', [('98765-0000-4', '+919876500004')]),
    ]);
    expect(rows.single.phone, '9876500004');
  });
}
