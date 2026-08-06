import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'dart:developer';
import 'config/feature_flags.dart';
import 'config/theme.dart';
import 'screens/app_shell.dart';
import 'screens/onboarding_screen.dart';
import 'screens/splash_screen.dart';
import 'overlay_main.dart';

@pragma("vm:entry-point")
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        canvasColor: Colors.transparent,
        scaffoldBackgroundColor: Colors.transparent,
        cardColor: AppColors.surfaceDark,
        dialogBackgroundColor: Colors.transparent,
        primaryColor: AppColors.amber,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.amber,
          onPrimary: AppColors.onAmber,
          secondary: Color(0xFF64748B),
          onSecondary: Colors.white,
          surface: AppColors.surfaceDark,
          onSurface: AppColors.textPrimaryDark,
          onSurfaceVariant: AppColors.textSecondaryDark,
          surfaceContainerHighest: AppColors.surfaceElevatedDark,
          outline: AppColors.borderDark,
          outlineVariant: Color(0xFF1C2538),
          error: AppColors.bear,
          onError: Colors.white,
        ),
        textTheme: AppTheme.darkTextTheme,
      ),
      builder: (context, child) {
        return Container(color: Colors.transparent, child: child);
      },
      home: const OverlayApp(),
    ),
  );
}

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.dark);

void Function(String task)? onOverlayTask;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (FeatureFlags.floatingOverlayEnabled) {
    FlutterOverlayWindow.overlayListener.listen((event) {
      log("Main app received from overlay: $event");
      if (event is String && event.trim().isNotEmpty) {
        if (onOverlayTask != null) {
          onOverlayTask!(event.trim());
        } else {
          log("Warning: overlay task received but no handler registered yet");
        }
      }
    });
  }

  final prefs = await SharedPreferences.getInstance();
  final themeStr = prefs.getString('themeMode');
  themeNotifier.value = themeStr == 'light' ? ThemeMode.light : ThemeMode.dark;

  final onboardingCompleted = prefs.getBool('onboarding_completed') ?? false;

  runApp(NeutralPipApp(onboardingCompleted: onboardingCompleted));
}

class NeutralPipApp extends StatelessWidget {
  final bool onboardingCompleted;
  const NeutralPipApp({super.key, required this.onboardingCompleted});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, ThemeMode currentMode, child) {
        return MaterialApp(
          title: 'Neutral Pip',
          debugShowCheckedModeBanner: false,
          themeMode: currentMode,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          home: SplashScreen(
            next: onboardingCompleted
                ? const AppShell()
                : const OnboardingScreen(),
          ),
        );
      },
    );
  }
}
