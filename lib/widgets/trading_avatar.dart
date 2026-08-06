import 'package:flutter/material.dart';
import '../config/theme.dart';

/// Neutral Pip logomark: amber candlestick glyph on a dark tile with a pip
/// accent dot. Amber only, by design; green/red are reserved for semantics.
class TradingAvatar extends StatelessWidget {
  final double size;
  final bool showLabel;

  const TradingAvatar({super.key, this.size = 44, this.showLabel = false});

  @override
  Widget build(BuildContext context) {
    final Color onTile = Theme.of(context).colorScheme.onSurface;
    final double glyphSize = size * 0.60;
    final double dotSize = size * 0.12;

    final Widget glyph = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.surfaceElevatedDark, AppColors.bgDark],
        ),
        border: Border.all(
          color: AppColors.amber.withValues(alpha: 0.45),
          width: 1.2,
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            Icons.candlestick_chart,
            color: AppColors.amber,
            size: glyphSize,
          ),
          Positioned(
            top: size * 0.16,
            right: size * 0.16,
            child: Container(
              width: dotSize,
              height: dotSize,
              decoration: const BoxDecoration(
                color: AppColors.amber,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );

    if (!showLabel) return glyph;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        glyph,
        const SizedBox(width: AppTokens.spaceMd),
        Text(
          'Neutral Pip',
          style: AppFonts.heading(
            size: size * 0.24,
            weight: FontWeight.w700,
            letterSpacing: -0.2,
            color: onTile,
          ),
        ),
      ],
    );
  }
}
