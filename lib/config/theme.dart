import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Neutral Pip design tokens: dark-first trading co-pilot palette.
///
/// Amber is the only brand color. Green (bull) and red (bear) are strictly
/// semantic: buy/sell signals, positive/negative delta, risk, and errors.
abstract final class AppColors {
  // Brand
  static const Color amber = Color(0xFFF0B90B);
  static const Color amberStrong = Color(0xFFFFC940);
  static const Color amberDim = Color(0xFFB8920A);
  static const Color onAmber = Color(0xFF1A1200);

  // Semantic (buy / sell / risk only)
  static const Color bull = Color(0xFF16C784);
  static const Color bullDim = Color(0xFF0E8F5E);
  static const Color bear = Color(0xFFEA3943);
  static const Color bearDim = Color(0xFFB3242C);

  // Dark surfaces (default)
  static const Color bgDark = Color(0xFF0A0E17);
  static const Color surfaceDark = Color(0xFF121826);
  static const Color surfaceElevatedDark = Color(0xFF1A2233);
  static const Color borderDark = Color(0xFF232D42);
  static const Color textPrimaryDark = Color(0xFFE6EDF3);
  static const Color textSecondaryDark = Color(0xFF8B949E);
  static const Color textMutedDark = Color(0xFF5C6773);

  // Light surfaces (opt-in)
  static const Color bgLight = Color(0xFFF7F8FA);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceElevatedLight = Color(0xFFF1F3F7);
  static const Color borderLight = Color(0xFFE2E8F0);
  static const Color textPrimaryLight = Color(0xFF14181F);
  static const Color textSecondaryLight = Color(0xFF5B6472);
  static const Color textMutedLight = Color(0xFF9AA3B0);
}

/// Shared geometry, spacing, and type scale.
abstract final class AppTokens {
  // Radius
  static const double radiusCard = 10;
  static const double radiusChip = 6;
  static const double radiusControl = 10;
  static const double radiusPill = 999;

  // Border
  static const double borderWidth = 1;

  // Spacing
  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 12;
  static const double spaceLg = 16;
  static const double spaceXl = 24;
  static const double spaceXxl = 32;

  // Type scale
  static const double displaySize = 38;
  static const double titleSize = 18;
  static const double bodySize = 14;
  static const double captionSize = 12;
  static const double fontSizeTiny = 10;

  // Fonts
  static const String fontFamily = 'JetBrains Mono';
}

/// Semantic color shortcuts for screens: `context.bull`, `context.bear`.
extension NeutralPipColors on BuildContext {
  Color get bull => AppColors.bull;
  Color get bear => AppColors.bear;
  Color get amber => AppColors.amber;
}

/// Dark-first ThemeData factories. `AppTheme.dark` is the default look;
/// `AppTheme.light` is the opt-in alternative.
abstract final class AppTheme {
  static ThemeData get dark => _build(Brightness.dark);
  static ThemeData get light => _build(Brightness.light);

  static ThemeData _build(Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;

    final Color bg =
        isDark ? AppColors.bgDark : AppColors.bgLight;
    final Color surface =
        isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final Color elevated = isDark
        ? AppColors.surfaceElevatedDark
        : AppColors.surfaceElevatedLight;
    final Color border =
        isDark ? AppColors.borderDark : AppColors.borderLight;
    final Color textPrimary = isDark
        ? AppColors.textPrimaryDark
        : AppColors.textPrimaryLight;
    final Color textSecondary = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondaryLight;
    final Color textMuted = isDark
        ? AppColors.textMutedDark
        : AppColors.textMutedLight;

    final ColorScheme colorScheme = isDark
        ? const ColorScheme.dark(
            primary: AppColors.amber,
            onPrimary: AppColors.onAmber,
            primaryContainer: AppColors.amberDim,
            onPrimaryContainer: AppColors.onAmber,
            secondary: Color(0xFF64748B),
            onSecondary: Colors.white,
            secondaryContainer: Color(0xFF1E293B),
            onSecondaryContainer: AppColors.textSecondaryDark,
            surface: AppColors.surfaceDark,
            onSurface: AppColors.textPrimaryDark,
            onSurfaceVariant: AppColors.textSecondaryDark,
            surfaceContainerLowest: AppColors.bgDark,
            surfaceContainerLow: Color(0xFF10161F),
            surfaceContainer: Color(0xFF131A28),
            surfaceContainerHigh: Color(0xFF161E2D),
            surfaceContainerHighest: AppColors.surfaceElevatedDark,
            outline: AppColors.borderDark,
            outlineVariant: Color(0xFF1C2538),
            error: AppColors.bear,
            onError: Colors.white,
            errorContainer: Color(0xFF3B1D20),
            onErrorContainer: Color(0xFFFFB3B8),
          )
        : const ColorScheme.light(
            primary: AppColors.amber,
            onPrimary: AppColors.onAmber,
            primaryContainer: AppColors.amberDim,
            onPrimaryContainer: AppColors.onAmber,
            secondary: Color(0xFF64748B),
            onSecondary: Colors.white,
            secondaryContainer: Color(0xFFE2E8F0),
            onSecondaryContainer: AppColors.textSecondaryLight,
            surface: AppColors.surfaceLight,
            onSurface: AppColors.textPrimaryLight,
            onSurfaceVariant: AppColors.textSecondaryLight,
            surfaceContainerLowest: Colors.white,
            surfaceContainerLow: Color(0xFFF4F6F9),
            surfaceContainer: Color(0xFFEFF2F6),
            surfaceContainerHigh: Color(0xFFEBEEF3),
            surfaceContainerHighest: AppColors.surfaceElevatedLight,
            outline: AppColors.borderLight,
            outlineVariant: Color(0xFFD6DDE6),
            error: AppColors.bear,
            onError: Colors.white,
            errorContainer: Color(0xFFFBE4E6),
            onErrorContainer: Color(0xFF8B1D24),
          );

    final ThemeData base =
        isDark ? ThemeData.dark() : ThemeData.light();
    final TextTheme textTheme =
        GoogleFonts.jetBrainsMonoTextTheme(base.textTheme);

    return ThemeData(
      brightness: isDark,
      useMaterial3: true,
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      colorScheme: colorScheme,
      textTheme: textTheme,
      splashColor: AppColors.amber.withOpacity(0.08),
      highlightColor: AppColors.amber.withOpacity(0.05),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: bg,
        foregroundColor: textPrimary,
        iconTheme: IconThemeData(color: textPrimary),
        titleTextStyle: GoogleFonts.jetBrainsMono(
          fontSize: AppTokens.titleSize,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness:
              isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness:
              isDark ? Brightness.dark : Brightness.light,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusCard),
          side: BorderSide(color: border, width: AppTokens.borderWidth),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: border,
        thickness: AppTokens.borderWidth,
        space: AppTokens.spaceLg,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: elevated,
        selectedColor: AppColors.amber.withOpacity(0.18),
        side: BorderSide(color: border, width: AppTokens.borderWidth),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusChip),
        ),
        labelStyle: GoogleFonts.jetBrainsMono(
          fontSize: AppTokens.captionSize,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        secondaryLabelStyle: GoogleFonts.jetBrainsMono(
          fontSize: AppTokens.captionSize,
          color: textSecondary,
        ),
        checkmarkColor: AppColors.amber,
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spaceSm,
          vertical: 4,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: elevated,
        hintStyle: GoogleFonts.jetBrainsMono(
          fontSize: AppTokens.bodySize,
          color: textSecondary,
        ),
        labelStyle: GoogleFonts.jetBrainsMono(
          fontSize: AppTokens.bodySize,
          color: textSecondary,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spaceLg,
          vertical: AppTokens.spaceMd,
        ),
        border: OutlineInputBorder(
          borderRadius:
              BorderRadius.circular(AppTokens.radiusControl),
          borderSide: BorderSide(color: border, width: AppTokens.borderWidth),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius:
              BorderRadius.circular(AppTokens.radiusControl),
          borderSide: BorderSide(color: border, width: AppTokens.borderWidth),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius:
              BorderRadius.circular(AppTokens.radiusControl),
          borderSide: const BorderSide(color: AppColors.amber, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.amber,
          foregroundColor: AppColors.onAmber,
          disabledBackgroundColor: AppColors.amberDim,
          disabledForegroundColor: AppColors.onAmber.withOpacity(0.5),
          textStyle: GoogleFonts.jetBrainsMono(
            fontSize: AppTokens.bodySize,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusControl),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.spaceLg,
            vertical: AppTokens.spaceMd,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: elevated,
          foregroundColor: textPrimary,
          disabledBackgroundColor: elevated.withOpacity(0.5),
          disabledForegroundColor: textSecondary,
          textStyle: GoogleFonts.jetBrainsMono(
            fontSize: AppTokens.bodySize,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusControl),
          ),
          side: BorderSide(color: border, width: AppTokens.borderWidth),
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.spaceLg,
            vertical: AppTokens.spaceMd,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          disabledForegroundColor: textSecondary,
          textStyle: GoogleFonts.jetBrainsMono(
            fontSize: AppTokens.bodySize,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusControl),
          ),
          side: BorderSide(color: border, width: AppTokens.borderWidth),
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.spaceLg,
            vertical: AppTokens.spaceMd,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: elevated,
        contentTextStyle: GoogleFonts.jetBrainsMono(
          fontSize: AppTokens.captionSize,
          color: textPrimary,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusCard),
          side: BorderSide(color: border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusCard),
          side: BorderSide(color: border),
        ),
        titleTextStyle: GoogleFonts.jetBrainsMono(
          fontSize: AppTokens.titleSize,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
        contentTextStyle: GoogleFonts.jetBrainsMono(
          fontSize: AppTokens.bodySize,
          color: textSecondary,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppTokens.radiusCard),
          ),
        ),
      ),
      listTileTheme: ListTileThemeData(
        textColor: textPrimary,
        iconColor: textSecondary,
        titleTextStyle: GoogleFonts.jetBrainsMono(
          fontSize: AppTokens.bodySize,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        subtitleTextStyle: GoogleFonts.jetBrainsMono(
          fontSize: AppTokens.captionSize,
          color: textSecondary,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.amber
              : textMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.amber.withOpacity(0.3)
              : border,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: AppColors.amber,
        linearTrackColor: border,
      ),
    );
  }
}
