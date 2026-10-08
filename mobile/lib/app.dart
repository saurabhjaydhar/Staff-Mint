import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/i18n/locale_provider.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

class StaffMintApp extends ConsumerWidget {
  const StaffMintApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final lang = ref.watch(localeProvider);
    return MaterialApp.router(
      title: 'StaffMint',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routerConfig: router,
      locale: Locale(lang),
      supportedLocales: const [Locale('en'), Locale('hi')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        // Large readable text, but cap extreme system scaling so layouts hold.
        final mq = MediaQuery.of(context);
        final scale = mq.textScaler.clamp(minScaleFactor: 1.0, maxScaleFactor: 1.4);
        return MediaQuery(
          data: mq.copyWith(textScaler: scale),
          child: child!,
        );
      },
    );
  }
}
