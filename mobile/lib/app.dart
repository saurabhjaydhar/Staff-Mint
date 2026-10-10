import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/i18n/locale_provider.dart';
import 'core/i18n/strings.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/auth_controller.dart';

/// App-wide snackbars that are not tied to one screen (account changes).
final appMessengerKey = GlobalKey<ScaffoldMessengerState>();

class StaffMintApp extends ConsumerWidget {
  const StaffMintApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final lang = ref.watch(localeProvider);
    // "Your access to Gupta Sweets has ended" / "Your role is now Manager", once.
    ref.listen(authControllerProvider.select((s) => s.notice), (_, change) {
      if (change == null) return;
      final s = S.forCode(lang);
      final text = change.ended
          ? s.accessEnded(change.companyName)
          : s.roleChangedTo(s.roleLabel(change.role ?? 'employee'));
      appMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(text), duration: const Duration(seconds: 6), behavior: SnackBarBehavior.floating),
      );
      ref.read(authControllerProvider.notifier).clearNotice();
    });
    return MaterialApp.router(
      title: 'StaffMint',
      scaffoldMessengerKey: appMessengerKey,
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
