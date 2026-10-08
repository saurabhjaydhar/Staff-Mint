import 'package:flutter/material.dart';

/// StaffMint brand: mint green, Material 3, large readable text.
class AppColors {
  AppColors._();
  static const mint = Color(0xFF2BB673);
  static const mintDark = Color(0xFF1E8E57);
  static const mintLight = Color(0xFFE6F7EE);
  static const present = Color(0xFF2BB673);
  static const late = Color(0xFFF59E0B);
  static const absent = Color(0xFFE5484D);
  static const halfDay = Color(0xFFF97316);
  static const leave = Color(0xFF6366F1);
  static const holiday = Color(0xFF0EA5E9);
  static const weekOff = Color(0xFF94A3B8);
  static const notMarked = Color(0xFFCBD5E1);
  static const checkedIn = Color(0xFF14B8A6);

  static Color forStatus(String? status) {
    switch (status) {
      case 'present':
        return present;
      case 'late':
        return late;
      case 'checked_in':
        return checkedIn;
      case 'absent':
        return absent;
      case 'half_day':
        return halfDay;
      case 'leave':
        return leave;
      case 'holiday':
        return holiday;
      case 'week_off':
        return weekOff;
      default:
        return notMarked;
    }
  }
}

class AppTheme {
  AppTheme._();

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.mint,
      brightness: Brightness.light,
    ).copyWith(primary: AppColors.mint, onPrimary: Colors.white);

    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    final text = base.textTheme.copyWith(
      bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 18),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: 16),
      bodySmall: base.textTheme.bodySmall?.copyWith(fontSize: 14),
      titleMedium: base.textTheme.titleMedium?.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
      titleLarge: base.textTheme.titleLarge?.copyWith(fontSize: 22, fontWeight: FontWeight.w700),
      labelLarge: base.textTheme.labelLarge?.copyWith(fontSize: 17, fontWeight: FontWeight.w600),
    );

    const radius = BorderRadius.all(Radius.circular(14));
    const minButton = Size(64, 52);

    return base.copyWith(
      textTheme: text,
      scaffoldBackgroundColor: const Color(0xFFF7F9F8),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(color: Colors.black87),
      ),
      cardTheme: const CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: Color(0xFFE3E8E5)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: minButton,
          shape: const RoundedRectangleBorder(borderRadius: radius),
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: minButton,
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
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(textStyle: text.labelLarge)),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: radius),
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: AppColors.mintLight,
        height: 70,
        labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.mint,
        foregroundColor: Colors.white,
      ),
      chipTheme: base.chipTheme.copyWith(labelStyle: const TextStyle(fontSize: 15)),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        minVerticalPadding: 10,
      ),
    );
  }
}
