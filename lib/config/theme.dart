import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Neutral Pip design tokens: premium dark-first fintech palette.
///
/// Amber is the only brand color. Green (bull) and red (bear) are strictly
/// semantic: buy/sell signals, positive/negative delta, risk, and errors.
abstract final class AppColors {
  // Brand
  static const Color amber = Color(0xFFF5B800); // Primary accent
  static const Color amberStrong = Color(0xFFFFD54A); // Secondary accent
  static const Color amberDim = Color(0xFFB8920A);
  static const Color onAmber = Color(0xFF1C1300);

  // Semantic (buy / sell / risk / info only)
  static const Color bull = Color(0xFF22C55E); // Success
  static const Color bullDim = Color(0xFF15803D);
  static const Color bear = Color(0xFFEF4444); // Danger
  static const Color bearDim = Color(0xFFB91C1C);
  static const Color warning = Color(0xFFF59E0B);
  static const Color info = Color(0xFF3B82F6);

  // Dark surfaces (default) — true/near-black base, cards lift by tone
  // only (no visible strokes), so the app reads like a premium dark
  // fintech rather than a navy-tinted dashboard.
  static const Color bgDark = Color(0xFF000000); // True black background
  static const Color secondaryBgDark = Color(
    0xFF0A0A0C,
  ); // Secondary background
  static const Color surfaceDark = Color(0xFF131316); // Card background
  static const Color surfaceElevatedDark = Color(0xFF1C1C20);
  static const Color borderDark = Color(0xFF232327); // Very subtle
  static const Color textPrimaryDark = Color(0xFFFFFFFF);
  static const Color textSecondaryDark = Color(0xFF9CA3AF);
  static const Color textMutedDark = Color(0xFF6B7280);

  // Light surfaces (opt-in)
  static const Color bgLight = Color(0xFFF6F7FB);
  static const Color secondaryBgLight = Color(0xFFEEF1F7);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceElevatedLight = Color(0xFFF1F3F9);
  static const Color borderLight = Color(0xFFE3E8F0);
  static const Color textPrimaryLight = Color(0xFF0B0F19);
  static const Color textSecondaryLight = Color(0xFF5B6472);
  static const Color textMutedLight = Color(0xFF9AA3B0);
}

/// Shared geometry, spacing, type scale, and shadows.
abstract final class AppTokens {
  // Radius: large, premium rounded corners
  static const double radiusCard = 22;
  static const double radiusCardLg = 24;
  static const double radiusControl = 14;
  static const double radiusChip = 999;
  static const double radiusPill = 999;

  // Border
  static const double borderWidth = 1;

  // Spacing (8px grid)
  static const double spaceXxs = 2;
  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 12;
  static const double spaceLg = 16;
  static const double spaceXl = 24;
  static const double spaceXxl = 32;
  static const double space3xl = 40;

  // Type scale
  static const double displaySize = 40;
  static const double headlineSize = 28;
  static const double titleSize = 18;
  static const double bodySize = 14;
  static const double captionSize = 12;
  static const double fontSizeTiny = 10;

  // Fonts
  static const String fontFamily = 'Space Grotesk';
  static const String fontBody = 'Inter';
}

/// Soft, premium shadows. Dark surfaces use deep, low-alpha shadows so
/// cards float without harsh outlines.
abstract final class AppShadows {
  static List<BoxShadow> get card => const [
    BoxShadow(color: Color(0x33000000), blurRadius: 28, offset: Offset(0, 10)),
    BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 2)),
  ];

  static List<BoxShadow> get glow => const [
    BoxShadow(color: Color(0x33F5B800), blurRadius: 24, offset: Offset(0, 0)),
  ];
}

/// Semantic color shortcuts for screens: `context.bull`, `context.bear`.
extension NeutralPipColors on BuildContext {
  Color get bull => AppColors.bull;
  Color get bear => AppColors.bear;
  Color get amber => AppColors.amber;
  Color get warning => AppColors.warning;
  Color get info => AppColors.info;
}

/// Typography helpers: Space Grotesk for headings, Inter for body.
abstract final class AppFonts {
  static TextStyle heading({
    double size = AppTokens.headlineSize,
    FontWeight weight = FontWeight.w700,
    Color? color,
    double? letterSpacing = -0.5,
    double? height,
  }) {
    return GoogleFonts.spaceGrotesk(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  static TextStyle body({
    double size = AppTokens.bodySize,
    FontWeight weight = FontWeight.w400,
    Color? color,
    double height = 1.45,
    double? letterSpacing,
  }) {
    return GoogleFonts.inter(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }
}

/// Dark-first ThemeData factories. `AppTheme.dark` is the default look;
/// `AppTheme.light` is the opt-in alternative.
abstract final class AppTheme {
  static ThemeData get dark => _build(Brightness.dark);
  static ThemeData get light => _build(Brightness.light);

  /// Typography for alternate entry points (e.g. the overlay engine).
  static TextTheme get darkTextTheme =>
      _textTheme(ThemeData.dark().textTheme, true);

  static TextTheme _textTheme(TextTheme base, bool isDark) {
    final primary = isDark
        ? AppColors.textPrimaryDark
        : AppColors.textPrimaryLight;
    final secondary = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondaryLight;
    final muted = isDark ? AppColors.textMutedDark : AppColors.textMutedLight;

    return TextTheme(
      displayLarge: AppFonts.heading(size: 57, color: primary),
      displayMedium: AppFonts.heading(size: 45, color: primary),
      displaySmall: AppFonts.heading(size: 36, color: primary),
      headlineLarge: AppFonts.heading(size: 32, color: primary),
      headlineMedium: AppFonts.heading(size: 28, color: primary),
      headlineSmall: AppFonts.heading(size: 24, color: primary),
      titleLarge: AppFonts.heading(
        size: 20,
        weight: FontWeight.w600,
        color: primary,
      ),
      titleMedium: AppFonts.heading(
        size: 17,
        weight: FontWeight.w600,
        color: primary,
      ),
      titleSmall: AppFonts.heading(
        size: 14,
        weight: FontWeight.w600,
        color: primary,
      ),
      bodyLarge: AppFonts.body(size: 16, color: primary),
      bodyMedium: AppFonts.body(size: 14, color: primary),
      bodySmall: AppFonts.body(size: 12, color: secondary),
      labelLarge: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: primary,
        letterSpacing: 0.1,
      ),
      labelMedium: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: secondary,
        letterSpacing: 0.2,
      ),
      labelSmall: GoogleFonts.inter(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: muted,
        letterSpacing: 0.4,
      ),
    );
  }

  static ThemeData _build(Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;

    final Color bg = isDark ? AppColors.bgDark : AppColors.bgLight;
    final Color surface = isDark
        ? AppColors.surfaceDark
        : AppColors.surfaceLight;
    final Color elevated = isDark
        ? AppColors.surfaceElevatedDark
        : AppColors.surfaceElevatedLight;
    final Color border = isDark ? AppColors.borderDark : AppColors.borderLight;
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
            secondary: Color(0xFF9CA3AF),
            onSecondary: Color(0xFF0B0F19),
            secondaryContainer: Color(0xFF1D2740),
            onSecondaryContainer: AppColors.textPrimaryDark,
            surface: AppColors.surfaceDark,
            onSurface: AppColors.textPrimaryDark,
            onSurfaceVariant: AppColors.textSecondaryDark,
            surfaceContainerLowest: AppColors.bgDark,
            surfaceContainerLow: AppColors.secondaryBgDark,
            surfaceContainer: Color(0xFF101012),
            surfaceContainerHigh: Color(0xFF16161A),
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
            secondary: Color(0xFF5B6472),
            onSecondary: Colors.white,
            secondaryContainer: Color(0xFFE8ECF4),
            onSecondaryContainer: AppColors.textPrimaryLight,
            surface: AppColors.surfaceLight,
            onSurface: AppColors.textPrimaryLight,
            onSurfaceVariant: AppColors.textSecondaryLight,
            surfaceContainerLowest: Colors.white,
            surfaceContainerLow: Color(0xFFF4F6FA),
            surfaceContainer: Color(0xFFEFF2F7),
            surfaceContainerHigh: Color(0xFFEBEEF4),
            surfaceContainerHighest: AppColors.surfaceElevatedLight,
            outline: AppColors.borderLight,
            outlineVariant: Color(0xFFD6DDE6),
            error: AppColors.bear,
            onError: Colors.white,
            errorContainer: Color(0xFFFBE4E6),
            onErrorContainer: Color(0xFF8B1D24),
          );

    final ThemeData base = isDark ? ThemeData.dark() : ThemeData.light();
    final TextTheme textTheme = _textTheme(base.textTheme, isDark);

    return ThemeData(
      brightness: isDark ? Brightness.dark : Brightness.light,
      useMaterial3: true,
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      colorScheme: colorScheme,
      textTheme: textTheme,
      splashColor: AppColors.amber.withValues(alpha: 0.08),
      highlightColor: AppColors.amber.withValues(alpha: 0.05),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: bg,
        foregroundColor: textPrimary,
        iconTheme: IconThemeData(color: textPrimary),
        titleTextStyle: AppFonts.heading(
          size: AppTokens.titleSize,
          weight: FontWeight.w700,
          color: textPrimary,
          letterSpacing: -0.3,
        ),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusCard),
          side: BorderSide(color: border.withValues(alpha: 0.35)),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: border,
        thickness: AppTokens.borderWidth,
        space: AppTokens.spaceLg,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: elevated,
        selectedColor: AppColors.amber.withValues(alpha: 0.18),
        side: BorderSide(color: border, width: AppTokens.borderWidth),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusChip),
        ),
        labelStyle: AppFonts.body(
          size: AppTokens.captionSize,
          weight: FontWeight.w600,
          color: textPrimary,
        ),
        secondaryLabelStyle: AppFonts.body(
          size: AppTokens.captionSize,
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
        hintStyle: AppFonts.body(
          size: AppTokens.bodySize,
          color: textSecondary,
        ),
        labelStyle: AppFonts.body(
          size: AppTokens.bodySize,
          color: textSecondary,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spaceLg,
          vertical: AppTokens.spaceMd,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusControl),
          borderSide: BorderSide(color: border, width: AppTokens.borderWidth),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusControl),
          borderSide: BorderSide(color: border, width: AppTokens.borderWidth),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusControl),
          borderSide: const BorderSide(color: AppColors.amber, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.amber,
          foregroundColor: AppColors.onAmber,
          disabledBackgroundColor: AppColors.amberDim,
          disabledForegroundColor: AppColors.onAmber.withValues(alpha: 0.5),
          textStyle: AppFonts.heading(
            size: AppTokens.bodySize,
            weight: FontWeight.w700,
            color: AppColors.onAmber,
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
          disabledBackgroundColor: elevated.withValues(alpha: 0.5),
          disabledForegroundColor: textSecondary,
          textStyle: AppFonts.heading(
            size: AppTokens.bodySize,
            weight: FontWeight.w600,
            color: textPrimary,
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
          textStyle: AppFonts.heading(
            size: AppTokens.bodySize,
            weight: FontWeight.w600,
            color: textPrimary,
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
        contentTextStyle: AppFonts.body(
          size: AppTokens.captionSize,
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
        titleTextStyle: AppFonts.heading(
          size: AppTokens.titleSize,
          weight: FontWeight.w700,
          color: textPrimary,
        ),
        contentTextStyle: AppFonts.body(
          size: AppTokens.bodySize,
          color: textSecondary,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppTokens.radiusCardLg),
          ),
        ),
      ),
      listTileTheme: ListTileThemeData(
        textColor: textPrimary,
        iconColor: textSecondary,
        titleTextStyle: AppFonts.body(
          size: AppTokens.bodySize,
          weight: FontWeight.w600,
          color: textPrimary,
        ),
        subtitleTextStyle: AppFonts.body(
          size: AppTokens.captionSize,
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
              ? AppColors.amber.withValues(alpha: 0.3)
              : border,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: AppColors.amber,
        linearTrackColor: border,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: AppColors.amber.withValues(alpha: 0.18),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        labelTextStyle: WidgetStatePropertyAll(
          GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: textSecondary,
          ),
        ),
      ),
    );
  }
}
