import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config/theme.dart';
import '../services/screen_automation_service.dart';

/// Polished step-by-step guide dialog. Used whenever a feature needs a
/// permission (or a setup step) the user hasn't completed yet: it explains
/// exactly how to grant it and offers a one-tap shortcut to the relevant
/// settings screen. The user can always dismiss it and continue later.
Future<void> showGuideDialog({
  required BuildContext context,
  required IconData icon,
  required String title,
  required String description,
  required List<String> steps,
  String? actionLabel,
  VoidCallback? onAction,
  String dismissLabel = 'Later',
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) {
      final scheme = Theme.of(dialogContext).colorScheme;
      final isDark = Theme.of(dialogContext).brightness == Brightness.dark;
      final surface = isDark ? AppColors.surfaceDark : AppColors.bgLight;

      return Dialog(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scheme.primary.withValues(alpha: 0.14),
                    ),
                    child: Icon(icon, color: scheme.primary, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      title,
                      style: AppFonts.heading(
                        size: 18,
                        weight: FontWeight.w700,
                        letterSpacing: -0.3,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                description,
                style: AppFonts.body(
                  size: 13.5,
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                ),
              ),
              const SizedBox(height: 18),
              for (var i = 0; i < steps.length; i++) ...[
                _GuideStep(index: i + 1, text: steps[i], isDark: isDark),
                if (i < steps.length - 1) const SizedBox(height: 12),
              ],
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: Text(
                      dismissLabel,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (actionLabel != null && onAction != null)
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(dialogContext);
                        onAction();
                      },
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                      ),
                      icon: const Icon(Icons.arrow_forward_rounded, size: 17),
                      label: Text(
                        actionLabel,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _GuideStep extends StatelessWidget {
  final int index;
  final String text;
  final bool isDark;

  const _GuideStep({
    required this.index,
    required this.text,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: scheme.primary,
          ),
          child: Text(
            '$index',
            style: TextStyle(
              color: AppColors.onAmber,
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              text,
              style: AppFonts.body(
                size: 13,
                height: 1.35,
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimaryLight,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Guide for enabling the Accessibility "Screen Control" service, which the
/// agent needs to read the screen and perform taps, scrolls, and typing.
Future<void> showAccessibilityGuide(
  BuildContext context,
  ScreenAutomationService service,
) {
  return showGuideDialog(
    context: context,
    icon: Icons.visibility_rounded,
    title: 'Enable Screen Control',
    description:
        'The AI needs screen control to read your screen and perform taps, '
        'scrolls, and typing across other apps. It takes about 30 seconds.',
    steps: const [
      'Tap "Open Accessibility Settings" below.',
      'If Android shows "Restricted setting", open App Info first, tap the '
          'three-dot menu, and choose "Allow restricted settings".',
      'Find "Neutral Pip Screen Control" in the list and toggle it on.',
      'Come back here and try again.',
    ],
    actionLabel: 'Open Accessibility Settings',
    onAction: () => service.openAccessibilitySettings(),
  );
}

/// Guide for configuring the fallback AI model. Shown when the user tries to
/// chat before any backend or model has been set up.
Future<void> showModelSetupGuide(
  BuildContext context, {
  required VoidCallback openSettings,
}) {
  return showGuideDialog(
    context: context,
    icon: Icons.smart_toy_rounded,
    title: 'Set Up Your AI Model',
    description:
        'Chat needs either a connected trading backend or a fallback AI '
        'model. It takes about a minute and works with any OpenAI-compatible '
        'provider.',
    steps: const [
      'Open Settings and scroll to the "Fallback AI" section.',
      'Pick a provider (DeepSeek, OpenRouter, NVIDIA, Groq...) or enter a '
          'custom endpoint.',
      'Paste your API key and set the model name — used as a fallback when '
          'no trading backend is connected.',
      'Tap Save to validate the connection, then come back and chat.',
    ],
    actionLabel: 'Open Settings',
    onAction: openSettings,
  );
}

/// Guide for granting microphone access, needed for voice input.
Future<void> showMicrophoneGuide(BuildContext context) {
  return showGuideDialog(
    context: context,
    icon: Icons.mic_rounded,
    title: 'Microphone Access Needed',
    description:
        'Voice commands need microphone access so Neutral Pip can hear you.',
    steps: const [
      'Tap "Open App Settings" below.',
      'Select "Permissions" and tap "Microphone".',
      'Choose "Allow only while using the app" (or "Allow").',
      'Come back and tap the mic to start speaking.',
    ],
    actionLabel: 'Open App Settings',
    onAction: () => openAppSettings(),
  );
}
