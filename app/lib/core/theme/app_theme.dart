import 'package:flutter/material.dart';

import 'app_spacing.dart';

/// Bảng màu lấy từ logo Viegrand: xanh navy + xanh da trời + ngọc, nền trắng lạnh.
abstract final class AppColors {
  /// Xanh navy của chữ thập trong logo. Dùng cho nút chính; chữ trắng trên nền này đạt ≈ 8:1.
  static const navy = Color(0xFF0048A8);

  /// Navy đậm: chữ tiêu đề, nền tối.
  static const navyDeep = Color(0xFF0B2447);

  /// Xanh da trời: điểm nhấn thân thiện, quả cầu Vy.
  static const sky = Color(0xFF4FB3F0);

  /// Ngọc của logo.
  static const aqua = Color(0xFF58E0E0);

  /// Điểm nhấn ấm, dùng tiết kiệm (cảnh báo mềm, nhấn).
  static const warm = Color(0xFFE0785F);

  /// Nền trắng lạnh hơi ngả xanh; thẻ nằm trên nền là trắng thuần.
  static const background = Color(0xFFF5F8FC);

  static const textMuted = Color(0xFF5B6B82);
  static const border = Color(0xFFDDE5F0);

  /// Mức chỉ số sức khoẻ (huyết áp...). Luôn kèm chữ/icon, không dùng màu đơn lẻ.
  static const levelGood = Color(0xFF2D8B72);
  static const levelWatch = Color(0xFFD9A441);
  static const levelHigh = Color(0xFFE0785F);
  static const levelDanger = Color(0xFFC94A4A);
}

abstract final class AppTheme {
  // Giữ tên cũ cho mã đang dùng.
  static const primary = AppColors.navy;
  static const secondary = AppColors.aqua;
  static const accent = AppColors.warm;
  static const warmSurface = AppColors.background;

  /// Be Vietnam Pro (OFL), thiết kế cho tiếng Việt; tệp nằm trong `assets/fonts`.
  static const String fontFamily = 'BeVietnamPro';

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final base = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
      secondary: AppColors.sky,
      tertiary: AppColors.warm,
    );
    final light = brightness == Brightness.light;
    final scheme = light
        ? base.copyWith(
            primary: AppColors.navy,
            onPrimary: Colors.white,
            primaryContainer: const Color(0xFFDCEBFF),
            onPrimaryContainer: AppColors.navyDeep,
            secondary: const Color(0xFF1C86C9),
            onSecondary: Colors.white,
            secondaryContainer: const Color(0xFFE2F3FD),
            onSecondaryContainer: AppColors.navyDeep,
            tertiary: AppColors.warm,
            surface: AppColors.background,
            surfaceContainerLowest: Colors.white,
            surfaceContainerLow: const Color(0xFFF0F5FB),
            surfaceContainer: const Color(0xFFEAF1F9),
            surfaceContainerHighest: const Color(0xFFE1EAF4),
            onSurface: AppColors.navyDeep,
            onSurfaceVariant: AppColors.textMuted,
            outline: const Color(0xFF8A98AD),
            outlineVariant: AppColors.border,
          )
        : base;

    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      borderSide: BorderSide(color: scheme.outlineVariant),
    );
    final textTheme = ThemeData(brightness: brightness).textTheme
        .apply(
          bodyColor: scheme.onSurface,
          displayColor: scheme.onSurface,
          fontFamily: fontFamily,
        );

    return ThemeData(
      useMaterial3: true,
      fontFamily: fontFamily,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: textTheme.copyWith(
        headlineLarge: textTheme.headlineLarge?.copyWith(
          fontSize: 32,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.8,
          height: 1.2,
        ),
        headlineMedium: textTheme.headlineMedium?.copyWith(
          fontSize: 28,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.6,
          height: 1.2,
        ),
        headlineSmall: textTheme.headlineSmall?.copyWith(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        titleLarge: textTheme.titleLarge?.copyWith(
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: textTheme.titleMedium?.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        titleSmall: textTheme.titleSmall?.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: textTheme.bodyLarge?.copyWith(fontSize: 18, height: 1.45),
        bodyMedium: textTheme.bodyMedium?.copyWith(fontSize: 16, height: 1.45),
        bodySmall: textTheme.bodySmall?.copyWith(fontSize: 14, height: 1.4),
        labelLarge: textTheme.labelLarge?.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
        labelMedium: textTheme.labelMedium?.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLowest,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLowest,
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: border.copyWith(
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: border.copyWith(
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md + 2,
          vertical: 18,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(AppSpacing.tapTarget),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          shape: const StadiumBorder(),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(AppSpacing.tapTarget),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          side: BorderSide(color: scheme.outlineVariant, width: 1.5),
          shape: const StadiumBorder(),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(AppSpacing.tapTarget, 48),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          shape: const StadiumBorder(),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide(color: scheme.outlineVariant),
        labelStyle: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 3,
        highlightElevation: 6,
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: const StadiumBorder(),
        extendedTextStyle: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppSpacing.radiusXl),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.8),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radius + 4),
        ),
      ),
    );
  }
}
