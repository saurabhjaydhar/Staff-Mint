import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/providers.dart';

/// Current UI language code (`en` or `hi`), persisted in preferences.
/// A fresh install starts in Hindi (most users prefer it); English is one tap away.
class LocaleController extends Notifier<String> {
  static const _key = 'sm_language';

  @override
  String build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final saved = prefs.getString(_key);
    return saved == 'en' ? 'en' : 'hi';
  }

  Future<void> setLanguage(String code) async {
    final normalized = code == 'hi' ? 'hi' : 'en';
    state = normalized;
    await ref.read(sharedPreferencesProvider).setString(_key, normalized);
  }

  Future<void> toggle() => setLanguage(state == 'hi' ? 'en' : 'hi');
}

final localeProvider = NotifierProvider<LocaleController, String>(LocaleController.new);
