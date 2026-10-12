import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:staffmint/core/i18n/locale_provider.dart';
import 'package:staffmint/core/i18n/strings.dart';
import 'package:staffmint/core/storage/providers.dart';
import 'package:staffmint/core/utils/dates.dart';

void main() {
  Future<ProviderContainer> container(Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues(prefs);
    final p = await SharedPreferences.getInstance();
    final c = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(p)]);
    addTearDown(c.dispose);
    return c;
  }

  test('default language for a fresh install is Hindi', () async {
    final c = await container({});
    expect(c.read(localeProvider), 'hi');
  });

  test('a saved choice wins and switching persists', () async {
    final c = await container({'sm_language': 'en'});
    expect(c.read(localeProvider), 'en');
    await c.read(localeProvider.notifier).toggle();
    expect(c.read(localeProvider), 'hi');
    expect((await SharedPreferences.getInstance()).getString('sm_language'), 'hi');
  });

  test('Hindi mode shows Hindi only: no English hint under Hindi words', () {
    expect(S.hi.presentBi.joined, 'हाज़िर');
    expect(S.hi.presentBi.hint, isNull);
    expect(S.en.presentBi.joined, 'Present');
    expect(S.en.presentBi.hint, isNull);
  });

  setUpAll(() => initializeDateFormatting('hi'));

  test('Hindi dates use full names and times read the way people say them', () {
    final d = DateTime(2026, 10, 12, 9, 5);
    expect(Dates.weekdayShort(d, 'hi'), 'सोमवार, 12 अक्टूबर');
    expect(Dates.dayMonth(d, 'hi'), '12 अक्टूबर');
    expect(Dates.hhmmToDisplay('09:05', 'hi'), 'सुबह 9:05');
    expect(Dates.hhmmToDisplay('18:30', 'hi'), 'शाम 6:30');
    expect(Dates.hhmmToDisplay('21:00', 'hi'), 'रात 9:00');
    expect(Dates.hhmmToDisplay('09:05'), '9:05 AM');
    expect(Dates.weekdayShort(d), 'Mon, 12 Oct');
  });

  test('Hindi strings use everyday words and no stray English', () {
    final src = File('lib/core/i18n/strings.dart').readAsStringSync();
    final hindi = RegExp(
      r"""_[tb]\(\s*(?:'(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*")\s*,\s*('(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*")""",
    );
    // Brand and official names stay in English letters.
    const allowed = {
      ...[
        'WhatsApp',
        'UPI',
        'PF',
        'ESI',
        'ESIC',
        'OTP',
        'PAN',
        'IFSC',
        'UAN',
        'PIN',
        'HRA',
        'GST',
        'GSTIN',
        'CA',
        'GPS',
      ],
      ...['PDF', 'ITR', 'Excel', 'SalaryBox', 'StaffMint', 'Mint', 'English', 'Hinglish', 'Growth', 'En', 'ID', 'SMS'],
      // Examples of input (UPI id, IFSC, a link).
      ...['SBIN', 'name', 'okaxis', 'https', 'app', 'staffmint', 'import', 'Import'],
    };
    const formal = [
      'वेतन',
      'कर्मचारी',
      'पंच',
      'सवेतन',
      'नियोक्ता',
      'भुगतान',
      'वैकल्पिक',
      'निष्क्रिय',
      'डिफ़ॉल्ट',
      'अग्रिम',
    ];
    final bad = <String>[];
    for (final m in hindi.allMatches(src)) {
      final hi = m.group(1)!.replaceAll(RegExp(r'\$\{[^}]*\}|\$\w+|\\[nt]'), '');
      for (final w in RegExp(r"[A-Za-z]+(?:'[A-Za-z]+)?").allMatches(hi)) {
        if (!allowed.contains(w.group(0))) bad.add('${w.group(0)} in $hi');
      }
      for (final f in formal) {
        if (hi.contains(f)) bad.add('$f in $hi');
      }
    }
    expect(bad, isEmpty);
  });
}
