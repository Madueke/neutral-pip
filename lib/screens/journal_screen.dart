import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../services/trading_api_service.dart';
import '../widgets/price_text.dart';
import '../widgets/signal_chip.dart';
import '../widgets/stat_card.dart';

/// Trading journal: monthly summary strip plus per-trade cards.
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

  @override
  Widget build(BuildContext context) {
    double netPnl = 0;
    double grossWins = 0;
    double grossLosses = 0;
    int wins = 0;
    for (final entry in _entries) {
      final pnl = _num(entry, const ['pnl', 'net_pnl', 'profit']);
      if (pnl == null) continue;
      netPnl += pnl;
      if (pnl > 0) {
        wins++;
        grossWins += pnl;
      } else {
        grossLosses += pnl.abs();
      }
    }
    final int total = _entries.length;
    final String winRate = total == 0
        ? '--'
        : '${((wins / total) * 100).toStringAsFixed(0)}%';
    final String profitFactor = grossLosses == 0
        ? (grossWins > 0 ? '∞' : '--')
        : (grossWins / grossLosses).toStringAsFixed(2);
    final Color pnlColor = netPnl > 0
        ? AppColors.bull
        : netPnl < 0
            ? AppColors.bear
            : Theme.of(context).colorScheme.onSurface;

    return Scaffold(
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
                padding: const EdgeInsets.all(AppTokens.spaceLg),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: StatCard(
                          label: 'Net P&L',
                          value: netPnl == 0 && total == 0
                              ? '--'
                              : _fmtPnl(netPnl),
                          valueColor: pnlColor,
                        ),
                      ),
                      const SizedBox(width: AppTokens.spaceSm),
                      Expanded(
                        child: StatCard(label: 'Win Rate', value: winRate),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTokens.spaceSm),
                  Row(
                    children: [
                      Expanded(
                        child: StatCard(
                          label: 'Profit Factor',
                          value: profitFactor,
                        ),
                      ),
                      const SizedBox(width: AppTokens.spaceSm),
                      Expanded(
                        child: StatCard(
                          label: 'Trades',
                          value: total.toString(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTokens.spaceXl),
                  if (_entries.isEmpty)
                    _buildEmptyState()
                  else
                    ..._entries.map(_buildTradeCard),
                ],
              ),
            ),
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
            style: TextStyle(
              fontSize: AppTokens.titleSize,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _isStub
                ? 'Connect a trading backend in Settings to sync your trades.'
                : 'No trades recorded yet.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: AppTokens.bodySize,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTradeCard(Map<String, dynamic> entry) {
    final scheme = Theme.of(context).colorScheme;
    final String direction =
        _str(entry, const ['direction', 'side']).toUpperCase();
    final String symbol = _str(entry, const ['symbol', 'pair', 'ticker']);
    final String id = _str(entry, const ['id', 'trade_id', 'tradeId']);
    final double? pnl = _num(entry, const ['pnl', 'net_pnl', 'profit']);
    final double? entryPrice = _num(entry, const ['entry', 'entry_price']);
    final double? sl = _num(entry, const ['sl', 'stop_loss']);
    final double? tp = _num(entry, const ['tp', 'take_profit']);

    final Widget chip = direction.contains('SELL')
        ? SignalChip.sell()
        : direction.contains('BUY')
            ? SignalChip.buy()
            : SignalChip.neutral();

    return Container(
      margin: const EdgeInsets.only(bottom: AppTokens.spaceMd),
      padding: const EdgeInsets.all(AppTokens.spaceLg),
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
        children: [
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    symbol == '--' ? id : symbol,
                    style: TextStyle(
                      fontSize: AppTokens.titleSize,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  chip,
                ],
              ),
              const Spacer(),
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
              _priceCell(scheme, 'SL', sl),
              _priceCell(scheme, 'TP', tp),
            ],
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
            style: TextStyle(
              fontSize: AppTokens.fontSizeTiny,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
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
