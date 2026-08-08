import 'package:flutter/material.dart';
import '../config/theme.dart';
import 'price_text.dart';

/// Key-value stat card used in dashboard strips, with an optional delta
/// shown beside the value. Delta colors are semantic: green for positive,
/// red for negative, unless an explicit deltaColor is supplied.
class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final String? delta;
  final Color? deltaColor;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.delta,
    this.deltaColor,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color resolvedDelta =
        deltaColor ??
        (delta == null
            ? scheme.onSurfaceVariant
            : delta!.startsWith('-')
            ? AppColors.bear
            : AppColors.bull);

    return Container(
      padding: const EdgeInsets.all(AppTokens.spaceLg),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: AppFonts.body(
              size: AppTokens.fontSizeTiny,
              weight: FontWeight.w600,
              letterSpacing: 0.8,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 5),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: PriceText(
                  value,
                  fontSize: AppTokens.titleSize,
                  color: valueColor,
                ),
              ),
              if (delta != null) ...[
                const SizedBox(width: 4),
                Text(
                  delta!,
                  style: AppFonts.body(
                    size: AppTokens.captionSize,
                    weight: FontWeight.w700,
                    color: resolvedDelta,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
