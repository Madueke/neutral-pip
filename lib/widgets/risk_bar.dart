import 'package:flutter/material.dart';
import '../config/theme.dart';

/// Segmented exposure/loss bar with green (safe), amber (caution), red
/// (limit) zones. Green/red are risk semantics here.
class RiskBar extends StatelessWidget {
  final double fraction;
  final double highLimit;
  final double dangerLimit;
  final String leftLabel;
  final String rightLabel;

  const RiskBar({
    super.key,
    required this.fraction,
    this.highLimit = 0.5,
    this.dangerLimit = 0.8,
    this.leftLabel = '',
    this.rightLabel = '',
  });

  @override
  Widget build(BuildContext context) {
    final double clamped = fraction.clamp(0.0, 1.0);
    final Color fillColor = clamped >= dangerLimit
        ? AppColors.bear
        : clamped >= highLimit
            ? AppColors.amber
            : AppColors.bull;
    final Color textColor = Theme.of(context).colorScheme.onSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (leftLabel.isNotEmpty || rightLabel.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  leftLabel,
                  style: TextStyle(
                    fontSize: AppTokens.captionSize,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
                Text(
                  rightLabel,
                  style: TextStyle(
                    fontSize: AppTokens.captionSize,
                    color: fillColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppTokens.radiusChip),
          child: SizedBox(
            height: 8,
            child: Stack(
              children: [
                Container(color: AppColors.borderDark),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: clamped,
                    child: Container(color: fillColor),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
