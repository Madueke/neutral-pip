import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../config/theme.dart';

/// Animated circular gauge with a gradient arc and a center value.
class CircularGauge extends StatefulWidget {
  final double value; // 0.0 - 1.0
  final String label;
  final String valueText;
  final Color? color;
  final double size;

  const CircularGauge({
    super.key,
    required this.value,
    required this.label,
    required this.valueText,
    this.color,
    this.size = 168,
  });

  @override
  State<CircularGauge> createState() => _CircularGaugeState();
}

class _CircularGaugeState extends State<CircularGauge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = widget.color ??
        (widget.value >= 0.7
            ? AppColors.bull
            : widget.value >= 0.4
                ? AppColors.amber
                : AppColors.bear);
    final track = isDark ? AppColors.surfaceElevatedDark : AppColors.borderLight;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _animation,
            builder: (context, _) {
              return CustomPaint(
                size: Size.square(widget.size),
                painter: _GaugePainter(
                  value: widget.value * _animation.value,
                  color: color,
                  track: track,
                ),
              );
            },
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.valueText,
                style: AppFonts.heading(
                  size: 30,
                  weight: FontWeight.w700,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.label,
                style: AppFonts.body(
                  size: AppTokens.fontSizeTiny,
                  weight: FontWeight.w700,
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double value;
  final Color color;
  final Color track;

  _GaugePainter({
    required this.value,
    required this.color,
    required this.track,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 12;
    const startAngle = math.pi * 0.75;
    const sweep = math.pi * 1.5;

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round
      ..color = track;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweep,
      false,
      trackPaint,
    );

    if (value <= 0) return;

    final valuePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: startAngle,
        endAngle: startAngle + sweep,
        colors: [
          color.withValues(alpha: 0.55),
          color,
          color.withValues(alpha: 0.55),
        ],
      ).createShader(
        Rect.fromCircle(center: center, radius: radius),
      );

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweep * value.clamp(0.0, 1.0),
      false,
      valuePaint,
    );

    // Glow dot at the arc tip
    final tipAngle = startAngle + sweep * value.clamp(0.0, 1.0);
    final tip = Offset(
      center.dx + math.cos(tipAngle) * radius,
      center.dy + math.sin(tipAngle) * radius,
    );
    canvas.drawCircle(
      tip,
      6,
      Paint()..color = color.withValues(alpha: 0.35),
    );
    canvas.drawCircle(tip, 3.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_GaugePainter oldDelegate) =>
      oldDelegate.value != value ||
      oldDelegate.color != color ||
      oldDelegate.track != track;
}
