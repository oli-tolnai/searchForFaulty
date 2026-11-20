import 'package:material_ui/material_ui.dart';

abstract final class Ui {
  static const background = Color(0xff0f1115);
  static const panel = Color(0xff12151b);
  static const surface = Color(0xff171a21);
  static const image = Color(0xff1b1f27);
  static const border = Color(0xff262b35);
  static const muted = Color(0xff9aa3af);
  static const text = Color(0xffe8eaed);
  static const primary = Color(0xffa8e063);
  static const onPrimary = Color(0xff11160b);
  static const auction = Color(0xfff2c35b);
  static const auctionSurface = Color(0xff3a2f14);
  static const fixed = Color(0xff8cc4ff);
  static const fixedSurface = Color(0xff16304a);
  static const selected = Color(0xff2c3b1a);
  static const warningSurface = Color(0xff2e2614);
  static const danger = Color(0xfff28b82);
  static const radius = 16.0;
  static const fieldRadius = 12.0;
  static const touch = 44.0;
  static const desktop = 1100.0;
  static ThemeData get theme {
    const scheme = ColorScheme.dark(
      primary: primary,
      onPrimary: onPrimary,
      secondary: primary,
      onSecondary: onPrimary,
      surface: surface,
      onSurface: text,
      onSurfaceVariant: muted,
      outline: border,
      outlineVariant: border,
      tertiary: auction,
      error: danger,
      secondaryContainer: selected,
      errorContainer: warningSurface,
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Inter',
      scaffoldBackgroundColor: background,
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(fieldRadius),
    );
    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        headlineSmall: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: text,
        ),
        titleLarge: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: text,
        ),
        titleMedium: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: text,
        ),
        bodyMedium: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          color: text,
        ),
        bodySmall: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 12,
          color: muted,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        surfaceTintColor: background,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: const BorderSide(color: border),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(touch, touch)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(touch, touch),
          shape: shape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(touch, touch),
          shape: shape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(touch, touch)),
      ),
      chipTheme: base.chipTheme.copyWith(
        side: const BorderSide(color: border),
        selectedColor: selected,
        backgroundColor: surface,
        showCheckmark: false,
        labelStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 12,
          color: text,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        isDense: true,
        labelStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 12,
          color: muted,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(fieldRadius),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(fieldRadius),
          borderSide: const BorderSide(color: border),
        ),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: panel,
        indicatorColor: selected,
        height: 72,
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: panel,
        indicatorColor: selected,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: panel,
        showDragHandle: true,
      ),
    );
  }
}
