import 'package:flutter/material.dart';

/// Maya's look: a deep night background with a violet / pink / cyan glow.
class MayaColors {
  static const bg = Color(0xFF09090F);
  static const bgTop = Color(0xFF1A1033);
  static const surface = Color(0xFF15151F);
  static const surfaceHigh = Color(0xFF1E1E2B);
  static const border = Color(0x1FFFFFFF);
  static const violet = Color(0xFF8B5CF6);
  static const pink = Color(0xFFEC4899);
  static const cyan = Color(0xFF22D3EE);
  static const amber = Color(0xFFFBBF24);
  static const text = Color(0xFFF4F4F8);
  static const textDim = Color(0xFFA1A1B5);
  static const danger = Color(0xFFF43F5E);

  static const brand = LinearGradient(
    colors: [violet, pink],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

ThemeData mayaTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: MayaColors.violet,
    brightness: Brightness.dark,
  ).copyWith(
    primary: MayaColors.violet,
    onPrimary: Colors.white,
    secondary: MayaColors.pink,
    tertiary: MayaColors.cyan,
    surface: MayaColors.surface,
    onSurface: MayaColors.text,
    surfaceContainerHighest: MayaColors.surfaceHigh,
    error: MayaColors.danger,
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: Brightness.dark);
  return base.copyWith(
    scaffoldBackgroundColor: MayaColors.bg,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      foregroundColor: MayaColors.text,
      centerTitle: false,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: MayaColors.surfaceHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: MayaColors.surfaceHigh,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      color: MayaColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: MayaColors.border),
      ),
    ),
    listTileTheme: const ListTileThemeData(iconColor: MayaColors.textDim),
    dividerTheme: const DividerThemeData(color: MayaColors.border, space: 1),
    textTheme: base.textTheme.copyWith(
      titleMedium: base.textTheme.titleMedium?.copyWith(color: MayaColors.violet, fontWeight: FontWeight.w600),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? MayaColors.violet : MayaColors.surface,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : MayaColors.textDim,
        ),
        side: const WidgetStatePropertyAll(BorderSide(color: MayaColors.border)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: MayaColors.violet,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: MayaColors.text,
        side: const BorderSide(color: MayaColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : null),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? MayaColors.violet : null),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: MayaColors.surfaceHigh,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      hintStyle: const TextStyle(color: MayaColors.textDim),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: MayaColors.surfaceHigh,
      contentTextStyle: const TextStyle(color: MayaColors.text),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}
