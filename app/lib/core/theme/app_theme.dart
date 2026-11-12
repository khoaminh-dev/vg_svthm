import 'package:flutter/material.dart';

import 'app_spacing.dart';

abstract final class AppTheme {
  static const _seed = Color(0xFF1E88E5);

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
    final border = OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.radius));

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      inputDecorationTheme: InputDecorationTheme(
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(borderSide: BorderSide(color: scheme.primary, width: 2)),
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radius)),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }
}
