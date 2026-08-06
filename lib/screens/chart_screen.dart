import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/theme.dart';
import '../widgets/tradingview_chart.dart';

/// Load the user's watchlist symbols (saved by Connect Trading Accounts).
/// Falls back to the same defaults that screen uses when nothing is stored.
Future<List<String>> loadWatchlistSymbols() async {
  final prefs = await SharedPreferences.getInstance();
  final stored = prefs.getStringList('watchlist_symbols');
  if (stored != null && stored.isNotEmpty) return stored;
  return const ['EURUSD', 'XAUUSD'];
}

/// Load the user's preferred timeframe (first saved watchlist timeframe).
/// Defaults to H1.
Future<String> loadPreferredTimeframe() async {
  final prefs = await SharedPreferences.getInstance();
  final stored = prefs.getStringList('watchlist_timeframes');
  if (stored != null && stored.isNotEmpty) return stored.first;
  return 'H1';
}

/// Full-screen live TradingView chart for one symbol/timeframe.
///
/// TRADING MODE: display-only. The chart shows public TradingView data and
/// never feeds anything back to the app, the backend, or the agent; no
/// credentials and no automation are involved.
class ChartScreen extends StatefulWidget {
  final String initialSymbol;
  final String initialTimeframe;

  const ChartScreen({
    super.key,
    required this.initialSymbol,
    this.initialTimeframe = 'H1',
  });

  @override
  State<ChartScreen> createState() => _ChartScreenState();
}

class _ChartScreenState extends State<ChartScreen> {
  static const List<String> _timeframeOptions = ['M15', 'H1', 'H4', 'D1'];

  late String _symbol;
  late String _timeframe;
  int _reloadCounter = 0;

  @override
  void initState() {
    super.initState();
    _symbol = widget.initialSymbol.trim().toUpperCase();
    _timeframe = _timeframeOptions.contains(widget.initialTimeframe)
        ? widget.initialTimeframe
        : 'H1';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondaryLight;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _symbol,
              style: AppFonts.heading(
                size: AppTokens.titleSize,
                weight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
            Text(
              'Live TradingView chart',
              style: AppFonts.body(
                size: AppTokens.fontSizeTiny,
                weight: FontWeight.w600,
                color: AppColors.amber,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Reload chart',
            onPressed: () => setState(() => _reloadCounter++),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTokens.spaceLg,
                AppTokens.spaceSm,
                AppTokens.spaceLg,
                AppTokens.spaceMd,
              ),
              child: Row(
                children: [
                  Text(
                    'TIMEFRAME',
                    style: AppFonts.body(
                      size: AppTokens.fontSizeTiny,
                      weight: FontWeight.w700,
                      color: secondary,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(width: AppTokens.spaceMd),
                  Expanded(
                    child: Row(
                      children: [
                        for (final tf in _timeframeOptions)
                          Expanded(child: _buildTimeframeChip(tf, secondary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTokens.spaceLg,
                  0,
                  AppTokens.spaceLg,
                  AppTokens.spaceXl,
                ),
                child: TradingViewChart(
                  key: ValueKey('$_symbol-$_timeframe-$_reloadCounter'),
                  symbol: _symbol,
                  timeframe: _timeframe,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeframeChip(String tf, Color secondary) {
    final selected = tf == _timeframe;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTokens.radiusChip),
        onTap: () {
          if (selected) return;
          setState(() {
            _timeframe = tf;
            _reloadCounter++;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceSm),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.amber.withValues(alpha: 0.16)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTokens.radiusChip),
            border: Border.all(
              color: selected
                  ? AppColors.amber.withValues(alpha: 0.5)
                  : (Theme.of(context).brightness == Brightness.dark
                        ? AppColors.borderDark
                        : AppColors.borderLight),
            ),
          ),
          child: Center(
            child: Text(
              tf,
              style: AppFonts.body(
                size: AppTokens.fontSizeTiny,
                weight: FontWeight.w700,
                color: selected ? AppColors.amber : secondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
