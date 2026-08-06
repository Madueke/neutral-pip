import 'dart:async';
import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../services/trading_api_service.dart';

/// A backend symbol together with its display label for tickers/watchlists.
class LiveTickerSymbol {
  final String symbol;
  final String label;

  const LiveTickerSymbol(this.symbol, this.label);
}

/// Horizontally scrolling strip of live quotes that refreshes itself on a
/// short poll timer. Hidden until at least one quote has arrived (i.e. when
/// a trading backend is configured and reachable).
///
/// TRADING MODE: read-only market data. This widget never triggers
/// execution and never performs any on-screen automation.
class LiveTickerStrip extends StatefulWidget {
  final TradingApiService tradingApiService;
  final List<LiveTickerSymbol> symbols;

  const LiveTickerStrip({
    super.key,
    required this.tradingApiService,
    required this.symbols,
  });

  @override
  State<LiveTickerStrip> createState() => _LiveTickerStripState();
}

class _LiveTickerStripState extends State<LiveTickerStrip> {
  static const Duration _pollInterval = Duration(seconds: 6);

  Timer? _timer;
  final Map<String, Map<String, dynamic>> _quotes = {};

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_pollInterval, (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!widget.tradingApiService.isConfigured) return;
    for (final item in widget.symbols) {
      final quote = await widget.tradingApiService.getQuote(item.symbol);
      if (!mounted) return;
      if (quote['status'] == 'ok') {
        setState(() => _quotes[item.symbol] = quote);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_quotes.isEmpty) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;

    return Container(
      height: 36,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: border.withValues(alpha: 0.5)),
        ),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spaceLg,
          vertical: 7,
        ),
        itemCount: widget.symbols.length,
        separatorBuilder: (_, _) => Container(
          width: 1,
          height: 14,
          margin: const EdgeInsets.symmetric(horizontal: AppTokens.spaceLg),
          color: border.withValues(alpha: 0.6),
        ),
        itemBuilder: (context, index) {
          final item = widget.symbols[index];
          final quote = _quotes[item.symbol];
          return _TickerQuote(label: item.label, quote: quote);
        },
      ),
    );
  }
}

class _TickerQuote extends StatelessWidget {
  final String label;
  final Map<String, dynamic>? quote;

  const _TickerQuote({required this.label, required this.quote});

  @override
  Widget build(BuildContext context) {
    final change = ((quote?['change_percent'] as num?) ?? 0).toDouble();
    final changeUp = change >= 0;
    final changeColor = changeUp ? AppColors.bull : AppColors.bear;
    final price = (quote?['last_close'] as num?) ?? 0;
    final priceText = _fmtPrice(price.toDouble());

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: AppFonts.body(
            size: 11,
            weight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 8),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: child,
          ),
          child: Text(
            priceText,
            key: ValueKey('tick_$label$priceText'),
            style: AppFonts.body(
              size: 11,
              weight: FontWeight.w700,
              color: changeColor,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '${changeUp ? '+' : ''}${change.toStringAsFixed(2)}%',
          style: AppFonts.body(
            size: 10,
            weight: FontWeight.w700,
            color: changeColor,
          ),
        ),
      ],
    );
  }

  static String _fmtPrice(double v) {
    if (v >= 1000) return v.toStringAsFixed(0);
    if (v >= 100) return v.toStringAsFixed(1);
    return v.toStringAsFixed(2);
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
