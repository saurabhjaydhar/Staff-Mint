import 'package:flutter/material.dart';

/// "Bahi-Khata Modern" tokens: warm paper, ink text, ledger lines, mint for
/// good, red for cuts. Light theme only (sunlight-proof, cheap to render).
class AppColors {
  AppColors._();

  // Base.
  static const ink = Color(0xFF1C1A17);
  static const paper = Color(0xFFFFFDF7);
  static const line = Color(0xFFEDE5D3);
  static const lineSoft = Color(0xFFF3EDDF);
  static const ruled = Color(0xFFF5EFE2);
  static const muted = Color(0xFF7B7262);
  static const mutedLight = Color(0xFFF1EEE6);
  static const margin = Color(0xFFF4C7C3);
  static const whyBg = Color(0xFFFBF8F0);

  // Accents.
  static const mint = Color(0xFF1E9E64);
  static const mintDark = Color(0xFF157A4C);
  static const mintLight = Color(0xFFE3F5EC);
  static const mintFaint = Color(0xFFF0FAF4);
  static const red = Color(0xFFD64545);
  static const redLight = Color(0xFFFCE9E7);
  static const amber = Color(0xFFE39A0B);
  static const amberDark = Color(0xFFA86E00);
  static const amberLight = Color(0xFFFFF2D6);
  static const amberBorder = Color(0xFFF6D58A);
  static const orange = Color(0xFFC2570C);
  static const orangeLight = Color(0xFFFFE9D6);
  static const indigo = Color(0xFF5146E0);
  static const indigoLight = Color(0xFFECEBFF);
  static const whatsapp = Color(0xFF25D366);

  // Chat.
  static const chatBg = Color(0xFFEFE7DB);
  static const chatDots = Color(0xFFE2D8C6);
  static const outBubble = Color(0xFFD7F8C8);
}

/// Colour + icon for an attendance status. Colour is never the only signal:
/// every pill also carries an icon and a word.
class StatusStyle {
  const StatusStyle(this.fg, this.bg, this.icon);
  final Color fg;
  final Color bg;
  final IconData icon;

  /// Pseudo-status for a row whose punch waits for the owner's approval.
  static const needsCheck = 'needs_check';

  static StatusStyle of(String? status) {
    switch (status) {
      case 'present':
        return const StatusStyle(AppColors.mint, AppColors.mintLight, Icons.check_rounded);
      case 'checked_in':
        return const StatusStyle(AppColors.mint, AppColors.mintLight, Icons.login_rounded);
      case 'late':
        return const StatusStyle(AppColors.amberDark, AppColors.amberLight, Icons.alarm_rounded);
      case 'absent':
        return const StatusStyle(AppColors.red, AppColors.redLight, Icons.close_rounded);
      case 'half_day':
        return const StatusStyle(AppColors.orange, AppColors.orangeLight, Icons.contrast_rounded);
      case 'leave':
        return const StatusStyle(AppColors.indigo, AppColors.indigoLight, Icons.beach_access_rounded);
      case 'holiday':
        return const StatusStyle(AppColors.muted, AppColors.mutedLight, Icons.celebration_rounded);
      case 'week_off':
        return const StatusStyle(AppColors.muted, AppColors.mutedLight, Icons.weekend_rounded);
      case needsCheck:
        return const StatusStyle(AppColors.ink, AppColors.mutedLight, Icons.location_on_rounded);
      default:
        return const StatusStyle(AppColors.muted, AppColors.mutedLight, Icons.remove_rounded);
    }
  }
}

class AppTheme {
  AppTheme._();

  static const font = 'Mukta';
  static const radius = BorderRadius.all(Radius.circular(16));

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(seedColor: AppColors.mint, brightness: Brightness.light).copyWith(
      primary: AppColors.mint,
      onPrimary: Colors.white,
      secondary: AppColors.ink,
      onSecondary: Colors.white,
      surface: AppColors.paper,
      onSurface: AppColors.ink,
      onSurfaceVariant: AppColors.muted,
      surfaceContainerHighest: AppColors.mutedLight,
      surfaceContainerLow: Colors.white,
      outline: AppColors.line,
      outlineVariant: AppColors.line,
      error: AppColors.red,
    );

    final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: font);
    // Devanagari needs a little more line height than Latin to stay readable.
    TextStyle? t(TextStyle? s, double size, FontWeight w, [double height = 1.35]) =>
        s?.copyWith(fontSize: size, fontWeight: w, height: height, color: AppColors.ink);
    final bt = base.textTheme;
    final text = bt.copyWith(
      headlineMedium: t(bt.headlineMedium, 28, FontWeight.w800, 1.1),
      headlineSmall: t(bt.headlineSmall, 24, FontWeight.w800, 1.15),
      titleLarge: t(bt.titleLarge, 21, FontWeight.w800, 1.2),
      titleMedium: t(bt.titleMedium, 17, FontWeight.w700, 1.3),
      titleSmall: t(bt.titleSmall, 15, FontWeight.w700, 1.3),
      bodyLarge: t(bt.bodyLarge, 17, FontWeight.w400),
      bodyMedium: t(bt.bodyMedium, 15.5, FontWeight.w400),
      bodySmall: t(bt.bodySmall, 13.5, FontWeight.w400)?.copyWith(color: AppColors.muted),
      labelLarge: t(bt.labelLarge, 16.5, FontWeight.w800, 1.2),
      labelMedium: t(bt.labelMedium, 13.5, FontWeight.w700, 1.2),
    );

    const minButton = Size(64, 52);
    const lineSide = BorderSide(color: AppColors.line, width: 1.5);

    return base.copyWith(
      textTheme: text,
      scaffoldBackgroundColor: AppColors.paper,
      canvasColor: AppColors.paper,
      dividerColor: AppColors.line,
      dividerTheme: const DividerThemeData(color: AppColors.line, thickness: 1, space: 1),
      splashFactory: InkRipple.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.paper,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
        shape: const Border(bottom: BorderSide(color: AppColors.line)),
      ),
      cardTheme: const CardThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: radius, side: lineSide),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: minButton,
          backgroundColor: AppColors.mint,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.line,
          shape: const RoundedRectangleBorder(borderRadius: radius),
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: minButton,
          foregroundColor: AppColors.ink,
          side: const BorderSide(color: AppColors.ink, width: 1.5),
          shape: const RoundedRectangleBorder(borderRadius: radius),
          textStyle: text.labelLarge,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: minButton,
          shape: const RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.mintDark,
          minimumSize: const Size(48, 48),
          textStyle: text.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(minimumSize: const Size(48, 48))),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        labelStyle: const TextStyle(color: AppColors.muted),
        hintStyle: const TextStyle(color: AppColors.muted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: const OutlineInputBorder(borderRadius: radius, borderSide: lineSide),
        enabledBorder: const OutlineInputBorder(borderRadius: radius, borderSide: lineSide),
        focusedBorder: const OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: AppColors.mint, width: 2),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: AppColors.red, width: 1.5),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: Colors.white,
        selectedColor: AppColors.mintLight,
        side: lineSide,
        shape: const StadiumBorder(),
        labelStyle: const TextStyle(fontFamily: font, fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink),
        checkmarkColor: AppColors.mintDark,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: Colors.white,
          selectedBackgroundColor: AppColors.ink,
          selectedForegroundColor: Colors.white,
          foregroundColor: AppColors.ink,
          side: const BorderSide(color: AppColors.ink, width: 1.5),
          minimumSize: const Size(48, 48),
          textStyle: const TextStyle(fontFamily: font, fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : null),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.mint : null),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.ink,
        unselectedLabelColor: AppColors.muted,
        indicatorColor: AppColors.ink,
        dividerColor: AppColors.line,
        labelStyle: TextStyle(fontFamily: font, fontWeight: FontWeight.w800, fontSize: 15.5),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.paper,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: AppColors.line,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: AppColors.paper,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(22))),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.ink,
        actionTextColor: Color(0xFF7DE0AE),
        contentTextStyle: TextStyle(fontFamily: font, fontSize: 15.5, color: Colors.white, height: 1.3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.mint),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        minVerticalPadding: 10,
        iconColor: AppColors.ink,
        titleTextStyle: TextStyle(fontFamily: font, fontSize: 16.5, fontWeight: FontWeight.w600, color: AppColors.ink),
        subtitleTextStyle: TextStyle(fontFamily: font, fontSize: 14, color: AppColors.muted, height: 1.3),
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        shape: Border(),
        collapsedShape: Border(),
        iconColor: AppColors.ink,
        collapsedIconColor: AppColors.muted,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.mint,
        foregroundColor: Colors.white,
        elevation: 2,
      ),
    );
  }
}
