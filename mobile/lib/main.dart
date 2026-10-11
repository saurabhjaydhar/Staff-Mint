import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/config/env.dart';
import 'core/push/push_service.dart';
import 'core/storage/providers.dart';
import 'features/employee/punch/punch_providers.dart';
import 'features/employee/punch/punch_queue.dart';

Future<void> main() async {
  if (Env.apiBaseUrl.isEmpty) {
    throw StateError('API_BASE_URL is not set. Run with --dart-define-from-file=config/local.json or config/production.json.');
  }
  WidgetsFlutterBinding.ensureInitialized();
  if (kDebugMode) debugPrint('[api] base URL: ${Env.apiBaseUrl}');

  await initializeDateFormatting();
  await Hive.initFlutter();
  final punchBox = await Hive.openBox<dynamic>(HivePunchQueueStore.boxName);
  final cacheBox = await Hive.openBox<dynamic>('cache');
  final prefs = await SharedPreferences.getInstance();

  // Push is optional: a placeholder Firebase config must never crash the app.
  final push = PushService();
  await push.init();

  runApp(
    ProviderScope(
      // Errors are shown with a retry button; no silent automatic retries.
      retry: (_, _) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        punchQueueBoxProvider.overrideWithValue(punchBox),
        cacheBoxProvider.overrideWithValue(cacheBox),
        pushServiceProvider.overrideWithValue(push),
      ],
      child: const StaffMintApp(),
    ),
  );
}
