import 'package:flutter/material.dart';
import '../config/theme.dart';

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
      ..color = color.withValues(alpha: 0.12)
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
