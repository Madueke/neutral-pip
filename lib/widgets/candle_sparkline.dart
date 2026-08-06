import 'package:flutter/material.dart';
import '../config/theme.dart';

/// Minimal candlestick sparkline drawn from OHLC data.
class CandleSparkline extends StatelessWidget {
  final List<List<double>> candles; // [open, high, low, close]
  final Color? bullColor;
  final Color? bearColor;
  final double height;

  const CandleSparkline({
    super.key,
    required this.candles,
    this.bullColor,
    this.bearColor,
    this.height = 36,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(double.infinity, height),
      painter: _CandlePainter(
        candles,
        bullColor ?? AppColors.bull,
        bearColor ?? AppColors.bear,
      ),
    );
  }
}

class _CandlePainter extends CustomPainter {
  final List<List<double>> candles;
  final Color bull;
  final Color bear;

  _CandlePainter(this.candles, this.bull, this.bear);

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;

    double minV = double.infinity, maxV = double.negativeInfinity;
    for (final c in candles) {
      minV = [minV, c[2], c[3]].reduce((a, b) => a < b ? a : b);
      maxV = [maxV, c[1], c[2]].reduce((a, b) => a > b ? a : b);
    }
    final span = (maxV - minV) == 0 ? 1.0 : (maxV - minV);
    final step = size.width / candles.length;
    final bodyWidth = step * 0.45;

    double y(double v) => size.height - ((v - minV) / span) * size.height;

    final bullPaint = Paint()..color = bull;
    final bearPaint = Paint()..color = bear;

    for (var i = 0; i < candles.length; i++) {
      final c = candles[i];
      final isBull = c[3] >= c[0];
      final paint = isBull ? bullPaint : bearPaint;
      final x = step * i + step / 2;

      // Wick
      canvas.drawLine(
        Offset(x, y(c[2])),
        Offset(x, y(c[1])),
        paint..strokeWidth = 1.2,
      );

      // Body
      final top = y(c[0] > c[3] ? c[0] : c[3]);
      final bottom = y(c[0] > c[3] ? c[3] : c[0]);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTRB(x - bodyWidth / 2, top, x + bodyWidth / 2, bottom),
        const Radius.circular(1.5),
      );
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(_CandlePainter oldDelegate) =>
      oldDelegate.candles != candles;
}
