import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../services/trading_api_service.dart';
import '../widgets/app_animations.dart';
import '../widgets/price_text.dart';
import '../widgets/signal_chip.dart';
import '../widgets/stat_card.dart';

/// Trading journal: hero P/L summary, statistics grid, and a timeline of
/// per-trade cards (screenshot, entry/exit, reasoning, outcome, emotion).
///
/// TRADING MODE: never add tap-based execution here. This screen only reads
/// journal data from the backend API; it never drives on-screen automation.
class JournalScreen extends StatefulWidget {
  final TradingApiService tradingApiService;

  const JournalScreen({super.key, required this.tradingApiService});

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  List<Map<String, dynamic>> _entries = [];
  bool _loading = true;
  bool _isStub = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await widget.tradingApiService.getJournal();
    if (!mounted) return;
    setState(() {
      _isStub = data['status'] == 'stub';
      final raw = data['entries'];
      _entries = raw is List
          ? raw.whereType<Map<String, dynamic>>().toList()
          : <Map<String, dynamic>>[];
      _loading = false;
    });
  }

  double? _num(Map<String, dynamic> m, List<String> keys) {
    for (final key in keys) {
      final v = m[key];
      if (v is num) return v.toDouble();
    }
    return null;
  }

  String _str(
    Map<String, dynamic> m,
    List<String> keys, [
    String fallback = '--',
  ]) {
    for (final key in keys) {
      final v = m[key];
      if (v is String && v.trim().isNotEmpty) return v;
    }
    return fallback;
  }

  String _fmtPnl(double v) =>
      '${v >= 0 ? '+' : '-'}\$${v.abs().toStringAsFixed(2)}';

  double _rrFor(Map<String, dynamic> entry) {
    final direction =
        _str(entry, const ['direction', 'side']).toUpperCase();
    final entryPrice = _num(entry, const ['entry', 'entry_price']);
    final sl = _num(entry, const ['sl', 'stop_loss']);
    final tp = _num(entry, const ['tp', 'take_profit']);
    if (entryPrice == null || sl == null || tp == null) return 0;
    final risk = (entryPrice - sl).abs();
    if (risk == 0) return 0;
    final reward = (tp - entryPrice).abs();
    return reward / risk;
  }

  double? _holdMinutes(Map<String, dynamic> entry) {
    final v = _num(
      entry,
      const ['hold_time_minutes', 'hold_time', 'duration_minutes'],
    );
    if (v == null) return null;
    // Some backends report hours.
    if (_num(entry, const ['hold_time', 'duration_minutes']) != null &&
        _num(entry, const ['hold_time_minutes']) == null) {
      return v * 60;
    }
    return v;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    double netPnl = 0;
    double grossWins = 0;
    double grossLosses = 0;
    int wins = 0;
    double rrSum = 0;
    int rrCount = 0;
    double holdSum = 0;
    int holdCount = 0;
    double biggestWin = 0;
    double biggestLoss = 0;

    for (final entry in _entries) {
      final pnl = _num(entry, const ['pnl', 'net_pnl', 'profit']);
      if (pnl != null) {
        netPnl += pnl;
        if (pnl > 0) {
          wins++;
          grossWins += pnl;
          if (pnl > biggestWin) biggestWin = pnl;
        } else {
          grossLosses += pnl.abs();
          if (pnl.abs() > biggestLoss) biggestLoss = pnl.abs();
        }
      }
      final rr = _rrFor(entry);
      if (rr > 0) {
        rrSum += rr;
        rrCount++;
      }
      final hold = _holdMinutes(entry);
      if (hold != null) {
        holdSum += hold;
        holdCount++;
      }
    }

    final int total = _entries.length;
    final String winRate = total == 0
        ? '--'
        : '${((wins / total) * 100).toStringAsFixed(0)}%';
    final String avgRr = rrCount == 0 ? '--' : '${(rrSum / rrCount).toStringAsFixed(2)}R';
    final String avgHold = holdCount == 0
        ? '--'
        : holdSum / holdCount < 90
            ? '${(holdSum / holdCount).toStringAsFixed(0)}m'
            : '${((holdSum / holdCount) / 60).toStringAsFixed(1)}h';
    final String profitFactor = grossLosses == 0
        ? (grossWins > 0 ? '∞' : '--')
        : (grossWins / grossLosses).toStringAsFixed(2);
    final Color pnlColor = netPnl > 0
        ? AppColors.bull
        : netPnl < 0
            ? AppColors.bear
            : Theme.of(context).colorScheme.onSurface;
    final String monthlyPnl = total == 0
        ? '--'
        : _fmtPnl(netPnl);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Journal'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  AppTokens.spaceLg,
                  AppTokens.spaceSm,
                  AppTokens.spaceLg,
                  AppTokens.spaceXxl,
                ),
                children: [
                  FadeInUp(
                    child: _buildHero(monthlyPnl, pnlColor, isDark),
                  ),
                  const SizedBox(height: AppTokens.spaceLg),
                  FadeInUp(
                    delay: const Duration(milliseconds: 80),
                    child: Row(
                      children: [
                        Expanded(
                          child: StatCard(
                            label: 'Win Rate',
                            value: winRate,
                            valueColor: AppColors.bull,
                          ),
                        ),
                        const SizedBox(width: AppTokens.spaceSm),
                        Expanded(
                          child: StatCard(label: 'Avg R:R', value: avgRr),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppTokens.spaceSm),
                  FadeInUp(
                    delay: const Duration(milliseconds: 140),
                    child: Row(
                      children: [
                        Expanded(
                          child: StatCard(
                            label: 'Avg Hold Time',
                            value: avgHold,
                          ),
                        ),
                        const SizedBox(width: AppTokens.spaceSm),
                        Expanded(
                          child: StatCard(
                            label: 'Profit Factor',
                            value: profitFactor,
                            valueColor: AppColors.info,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppTokens.spaceSm),
                  FadeInUp(
                    delay: const Duration(milliseconds: 200),
                    child: Row(
                      children: [
                        Expanded(
                          child: StatCard(
                            label: 'Biggest Win',
                            value: total == 0 ? '--' : _fmtPnl(biggestWin),
                            valueColor: AppColors.bull,
                          ),
                        ),
                        const SizedBox(width: AppTokens.spaceSm),
                        Expanded(
                          child: StatCard(
                            label: 'Biggest Loss',
                            value: total == 0 ? '--' : _fmtPnl(-biggestLoss),
                            valueColor: AppColors.bear,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppTokens.spaceXl),
                  FadeInUp(
                    child: Text(
                      'TIMELINE',
                      style: AppFonts.body(
                        size: AppTokens.fontSizeTiny,
                        weight: FontWeight.w700,
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondaryLight,
                        height: 1,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppTokens.spaceMd),
                  if (_entries.isEmpty)
                    FadeInUp(child: _buildEmptyState())
                  else
                    for (var i = 0; i < _entries.length; i++)
                      FadeInUp(
                        delay: Duration(milliseconds: 60 * (i % 4)),
                        child: _buildTimelineEntry(_entries[i], i, isDark),
                      ),
                ],
              ),
            ),
    );
  }

  Widget _buildHero(String monthlyPnl, Color pnlColor, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(AppTokens.spaceXl),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTokens.radiusCardLg),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [Color(0xFF1D2740), Color(0xFF161D2F)]
              : const [Color(0xFFFFFFFF), Color(0xFFF4F6FA)],
        ),
        border: Border.all(
          color: pnlColor.withValues(alpha: 0.35),
        ),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MONTHLY P/L',
                  style: AppFonts.body(
                    size: AppTokens.fontSizeTiny,
                    weight: FontWeight.w700,
                    color: pnlColor.withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  monthlyPnl,
                  style: AppFonts.heading(
                    size: AppTokens.displaySize,
                    weight: FontWeight.w700,
                    color: pnlColor,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_entries.length} trade${_entries.length == 1 ? '' : 's'} '
                  'recorded this period',
                  style: AppFonts.body(
                    size: AppTokens.captionSize,
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: pnlColor.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(18),
              boxShadow: AppShadows.glow,
            ),
            child: Icon(
              Icons.trending_up_rounded,
              color: pnlColor,
              size: 26,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineEntry(
    Map<String, dynamic> entry,
    int index,
    bool isDark,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final String direction =
        _str(entry, const ['direction', 'side']).toUpperCase();
    final String symbol = _str(entry, const ['symbol', 'pair', 'ticker']);
    final String id = _str(entry, const ['id', 'trade_id', 'tradeId']);
    final double? pnl = _num(entry, const ['pnl', 'net_pnl', 'profit']);
    final double? entryPrice = _num(entry, const ['entry', 'entry_price']);
    final double? exitPrice = _num(entry, const ['exit', 'exit_price']);
    final double? sl = _num(entry, const ['sl', 'stop_loss']);
    final double? tp = _num(entry, const ['tp', 'take_profit']);
    final String reasoning =
        _str(entry, const ['reasoning', 'notes', 'note']);
    final String outcome = _str(entry, const ['outcome', 'result']);
    final String emotion = _str(entry, const ['emotion', 'mood']);
    final String lessons = _str(entry, const ['lessons', 'lesson']);

    final Widget chip = direction.contains('SELL')
        ? SignalChip.sell()
        : direction.contains('BUY')
            ? SignalChip.buy()
            : SignalChip.neutral();

    final Color dotColor = pnl == null
        ? scheme.onSurfaceVariant
        : pnl >= 0
            ? AppColors.bull
            : AppColors.bear;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Timeline rail
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  margin: const EdgeInsets.only(top: 26),
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: dotColor.withValues(alpha: 0.5),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: dotColor.withValues(alpha: 0.18),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTokens.spaceSm),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: AppTokens.spaceLg),
              padding: const EdgeInsets.all(AppTokens.spaceLg),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(AppTokens.radiusCard),
                border: Border.all(
                  color: isDark ? AppColors.borderDark : AppColors.borderLight,
                  width: AppTokens.borderWidth,
                ),
                boxShadow: AppShadows.card,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              symbol == '--' ? id : symbol,
                              style: AppFonts.heading(
                                size: AppTokens.titleSize,
                                weight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            chip,
                          ],
                        ),
                      ),
                      if (pnl != null)
                        PriceText(
                          _fmtPnl(pnl),
                          fontSize: AppTokens.titleSize,
                        ),
                    ],
                  ),
                  const SizedBox(height: AppTokens.spaceMd),
                  const Divider(height: 1),
                  const SizedBox(height: AppTokens.spaceMd),
                  Row(
                    children: [
                      _priceCell(scheme, 'Entry', entryPrice),
                      _priceCell(scheme, 'Exit', exitPrice),
                      _priceCell(scheme, 'SL', sl),
                      _priceCell(scheme, 'TP', tp),
                    ],
                  ),
                  if (reasoning != '--') ...[
                    const SizedBox(height: AppTokens.spaceMd),
                    _noteRow(Icons.lightbulb_rounded, 'Reasoning', reasoning,
                        isDark),
                  ],
                  if (outcome != '--') ...[
                    const SizedBox(height: AppTokens.spaceSm),
                    _noteRow(Icons.flag_rounded, 'Outcome', outcome, isDark),
                  ],
                  if (emotion != '--') ...[
                    const SizedBox(height: AppTokens.spaceSm),
                    _noteRow(Icons.psychology_rounded, 'Emotion', emotion,
                        isDark),
                  ],
                  if (lessons != '--') ...[
                    const SizedBox(height: AppTokens.spaceSm),
                    _noteRow(Icons.school_rounded, 'Lessons', lessons, isDark),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _noteRow(IconData icon, String label, String text, bool isDark) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 15,
          color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
        ),
        const SizedBox(width: AppTokens.spaceSm),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: AppFonts.body(
                size: AppTokens.captionSize,
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
              children: [
                TextSpan(
                  text: '$label  ',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(text: text),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppTokens.spaceXl),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        border: Border.all(
          color: scheme.outlineVariant,
          width: AppTokens.borderWidth,
        ),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        children: [
          const Icon(
            Icons.menu_book_outlined,
            color: AppColors.amber,
            size: 32,
          ),
          const SizedBox(height: AppTokens.spaceMd),
          Text(
            'Journal is empty',
            style: AppFonts.heading(
              size: AppTokens.titleSize,
              weight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _isStub
                ? 'Connect a trading backend in Settings to sync your trades.'
                : 'No trades recorded yet.',
            textAlign: TextAlign.center,
            style: AppFonts.body(
              size: AppTokens.bodySize,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _priceCell(
    ColorScheme scheme,
    String label,
    double? value,
  ) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: AppFonts.body(
              size: AppTokens.fontSizeTiny,
              weight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 3),
          PriceText(
            value == null ? '--' : value.toStringAsFixed(2),
            fontSize: AppTokens.bodySize,
          ),
        ],
      ),
    );
  }
}
