import 'package:flutter/material.dart';

import '../config/theme.dart';

/// Branded loading indicator: the app logo inside a spinning amber ring
/// with a soft glow. Replaces plain [CircularProgressIndicator]s so every
/// loading state shows the app logo.
class LogoLoader extends StatelessWidget {
  final double size;
  final double strokeWidth;
  final Color ringColor;
  final bool showGlow;

  const LogoLoader({
    super.key,
    this.size = 72,
    this.strokeWidth = 3,
    this.ringColor = AppColors.amber,
    this.showGlow = true,
  });

  @override
  Widget build(BuildContext context) {
    final logoSize = size * 0.52;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (showGlow)
            Container(
              width: size * 0.9,
              height: size * 0.9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    ringColor.withValues(alpha: 0.25),
                    ringColor.withValues(alpha: 0.08),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              strokeWidth: strokeWidth,
              valueColor: AlwaysStoppedAnimation<Color>(ringColor),
            ),
          ),
          SizedBox(
            width: logoSize,
            height: logoSize,
            child: Image.asset(
              'assets/splash/logo_transparent.png',
              fit: BoxFit.contain,
              gaplessPlayback: true,
            ),
          ),
        ],
      ),
    );
  }
}
