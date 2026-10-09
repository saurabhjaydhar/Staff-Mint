import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:staffmint/core/i18n/locale_provider.dart';
import 'package:staffmint/core/i18n/strings.dart';
import 'package:staffmint/core/storage/providers.dart';

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

  test('Bi shows Hindi with an English hint only in Hindi', () {
    expect(S.hi.presentBi.joined, 'हाज़िर · Present');
    expect(S.en.presentBi.joined, 'Present');
    expect(S.en.presentBi.hint, isNull);
  });
}
