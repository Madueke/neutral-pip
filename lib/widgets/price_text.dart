import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import '../config/theme.dart';

/// Monospace price/delta text with automatic green/red coloring when a
/// direction is supplied (strictly semantic).
class PriceText extends StatelessWidget {
  final String text;
  final double fontSize;
  final Color? color;
  final double? change;

  const PriceText(
    this.text, {
    super.key,
    this.fontSize = AppTokens.bodySize,
    this.color,
    this.change,
  });

  @override
  Widget build(BuildContext context) {
    final Color resolved = color ??
        (change == null
            ? Theme.of(context).colorScheme.onSurface
            : change! >= 0
                ? AppColors.bull
                : AppColors.bear);
    return Text(
      text,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: resolved,
      ),
    );
  }
}
