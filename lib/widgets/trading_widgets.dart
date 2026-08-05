import 'package:flutter/material.dart';
import '../config/theme.dart';

/// BUY / SELL / NEUTRAL signal chip. Green and red are used here strictly
/// because they carry buy/sell meaning.
class SignalChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;

  const SignalChip._(this.label, this.color, this.icon);

  factory SignalChip.buy([String label = 'BUY']) =>
      SignalChip._(label, AppColors.bull, Icons.arrow_upward_rounded);
  factory SignalChip.sell([String label = 'SELL']) =>
      SignalChip._(label, AppColors.bear, Icons.arrow_downward_rounded);
  factory SignalChip.neutral([String label = 'NEUTRAL']) =>
      SignalChip._(label, AppColors.textSecondaryDark, Icons.remove_rounded);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceSm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(AppTokens.radiusChip),
        border: Border.all(color: color.withOpacity(0.5), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: AppTokens.fontSizeTiny,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

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

/// Tiny candlestick-style sparkline, painted without a chart dependency.
class MiniSparkline extends StatelessWidget {
  final List<double> values;
  final double height;
  final Color color;

  const MiniSparkline(
    this.values, {
    super.key,
    this.height = 28,
    this.color = AppColors.bull,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(double.infinity, height),
      painter: _SparklinePainter(values, color),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> values;
  final Color color;

  _SparklinePainter(this.values, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2 || size.width <= 0) return;

    final double min = values.reduce((a, b) => a < b ? a : b);
    final double max = values.reduce((a, b) => a > b ? a : b);
    final double range = (max - min) == 0 ? 1 : (max - min);

    final Path line = Path();
    final double step = size.width / (values.length - 1);
    for (int i = 0; i < values.length; i++) {
      final double x = i * step;
      final double y = size.height - ((values[i] - min) / range) * size.height;
      if (i == 0) {
        line.moveTo(x, y);
      } else {
        line.lineTo(x, y);
      }
    }

    final Paint stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final Paint fill = Paint()
      ..color = color.withOpacity(0.12)
      ..style = PaintingStyle.fill;

    final Path area = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(area, fill);
    canvas.drawPath(line, stroke);
  }

  @override
  bool shouldRepaint(_SparklinePainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}

/// Key-value stat card used in dashboard strips.
class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final Widget? trailing;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppTokens.spaceMd),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        border: Border.all(
          color: scheme.outlineVariant,
          width: AppTokens.borderWidth,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: AppTokens.fontSizeTiny,
              fontWeight: FontWeight.w600,
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
              if (trailing != null) ...[
                const SizedBox(width: 4),
                trailing!,
              ],
            ],
          ),
        ],
      ),
    );
  }
}
