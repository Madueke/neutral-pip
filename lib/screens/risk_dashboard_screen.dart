import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../services/trading_api_service.dart';
import '../widgets/price_text.dart';
import '../widgets/risk_bar.dart';
import '../widgets/stat_card.dart';

/// Risk dashboard: exposure and daily-loss meters plus open positions.
///
/// TRADING MODE: never add tap-based execution here. This screen only reads
/// risk data from the backend API; it never drives on-screen automation.
class RiskDashboardScreen extends StatefulWidget {
  final TradingApiService tradingApiService;

  const RiskDashboardScreen({super.key, required this.tradingApiService});

  @override
  State<RiskDashboardScreen> createState() => _RiskDashboardScreenState();
}

class _RiskDashboardScreenState extends State<RiskDashboardScreen> {
  Map<String, dynamic> _data = {};
  bool _loading = true;
  bool _isStub = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await widget.tradingApiService.getRiskStatus();
    if (!mounted) return;
    setState(() {
      _data = data;
      _isStub = data['status'] == 'stub';
      _loading = false;
    });
  }

  double? _num(List<String> keys) {
    for (final key in keys) {
      final v = _data[key];
      if (v is num) return v.toDouble();
    }
    return null;
  }

  String _str(List<String> keys, [String fallback = '--']) {
    for (final key in keys) {
      final v = _data[key];
      if (v is String && v.trim().isNotEmpty) return v;
    }
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final double? exposure = _num(const ['exposure_percent', 'exposure']);
    final double? lossUsed =
        _num(const ['daily_loss_used', 'daily_loss_used_percent']);
    final double? lossLimit =
        _num(const ['daily_loss_limit', 'daily_loss_limit_percent']);

    final double? lossFraction = (lossUsed != null &&
            lossLimit != null &&
            lossLimit > 0)
        ? lossUsed / lossLimit
        : null;
    final double? exposureFraction =
        exposure != null && exposure > 1 ? exposure / 100 : exposure;

    final String riskLevel =
        _str(const ['riskLevel', 'risk_level'], 'unknown').toLowerCase();
    final bool severe = riskLevel == 'high' ||
        riskLevel == 'critical' ||
        (lossFraction != null && lossFraction >= 0.8) ||
        (exposureFraction != null && exposureFraction >= 0.8);

    final rawPositions = _data['open_positions'];
    final List<Map<String, dynamic>> positions = rawPositions is List
        ? rawPositions.whereType<Map<String, dynamic>>().toList()
        : <Map<String, dynamic>>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Risk'),
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
                  if (severe) _buildSeverityBanner(),
                  if (severe) const SizedBox(height: AppTokens.spaceLg),
                  Row(
                    children: [
                      Expanded(
                        child: StatCard(
                          label: 'Exposure',
                          value: exposure == null
                              ? '--'
                              : '${exposure.toStringAsFixed(0)}%',
                          valueColor: (exposureFraction ?? 0) >= 0.8
                              ? AppColors.bear
                              : (exposureFraction ?? 0) >= 0.5
                                  ? AppColors.amber
                                  : AppColors.bull,
                        ),
                      ),
                      const SizedBox(width: AppTokens.spaceSm),
                      Expanded(
                        child: StatCard(
                          label: 'Daily Loss',
                          value: lossUsed == null
                              ? '--'
                              : '${lossUsed.toStringAsFixed(0)}%',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTokens.spaceSm),
                  Row(
                    children: [
                      Expanded(
                        child: StatCard(
                          label: 'Loss Limit',
                          value: lossLimit == null
                              ? '--'
                              : '${lossLimit.toStringAsFixed(0)}%',
                        ),
                      ),
                      const SizedBox(width: AppTokens.spaceSm),
                      Expanded(
                        child: StatCard(
                          label: 'Level',
                          value: riskLevel == 'unknown'
                              ? '--'
                              : riskLevel.toUpperCase(),
                          valueColor: severe
                              ? AppColors.bear
                              : riskLevel == 'unknown'
                                  ? scheme.onSurface
                                  : AppColors.bull,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTokens.spaceXl),
                  if (lossFraction != null)
                    Container(
                      padding: const EdgeInsets.all(AppTokens.spaceLg),
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius:
                            BorderRadius.circular(AppTokens.radiusCard),
                        border: Border.all(
                          color: scheme.outlineVariant,
                          width: AppTokens.borderWidth,
                        ),
                      ),
                      child: RiskBar(
                        fraction: lossFraction,
                        leftLabel: 'DAILY LOSS USED',
                        rightLabel:
                            '${(lossFraction * 100).toStringAsFixed(0)}% / '
                            '${lossLimit!.toStringAsFixed(0)}%',
                      ),
                    ),
                  if (lossFraction != null)
                    const SizedBox(height: AppTokens.spaceXl),
                  Text(
                    'OPEN POSITIONS',
                    style: TextStyle(
                      fontSize: AppTokens.fontSizeTiny,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppTokens.spaceMd),
                  if (positions.isEmpty)
                    _buildEmptyPositions()
                  else
                    ...positions.map(_buildPositionRow),
                  if (_isStub) ...[
                    const SizedBox(height: AppTokens.spaceXl),
                    _buildStubHint(),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildSeverityBanner() {
    return Container(
      padding: const EdgeInsets.all(AppTokens.spaceLg),
      decoration: BoxDecoration(
        color: AppColors.bear.withOpacity(0.12),
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        border: Border.all(
          color: AppColors.bear.withOpacity(0.4),
          width: AppTokens.borderWidth,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.bear),
          const SizedBox(width: AppTokens.spaceMd),
          Expanded(
            child: Text(
              'Risk limits approaching. Review exposure and open positions '
              'before taking new trades.',
              style: TextStyle(
                fontSize: AppTokens.bodySize,
                fontWeight: FontWeight.w600,
                height: 1.4,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyPositions() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceXl),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        border: Border.all(
          color: scheme.outlineVariant,
          width: AppTokens.borderWidth,
        ),
      ),
      child: Center(
        child: Text(
          'No open positions',
          style: TextStyle(
            fontSize: AppTokens.bodySize,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildStubHint() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppTokens.spaceLg),
      decoration: BoxDecoration(
        color: AppColors.amber.withOpacity(0.08),
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        border: Border.all(
          color: AppColors.amber.withOpacity(0.35),
          width: AppTokens.borderWidth,
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            color: AppColors.amber,
            size: 20,
          ),
          const SizedBox(width: AppTokens.spaceMd),
          Expanded(
            child: Text(
              'Live risk data needs a trading backend. Add its URL in '
              'Settings to see real numbers here.',
              style: TextStyle(
                fontSize: AppTokens.captionSize,
                height: 1.4,
                color: scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPositionRow(Map<String, dynamic> position) {
    final scheme = Theme.of(context).colorScheme;
    final String symbol = _posStr(position, const ['symbol', 'pair', 'ticker']);
    final String size = _posStr(position, const ['size', 'volume', 'qty']);
    final double? entry = _posNum(position, const ['entry', 'entry_price']);
    final double? current = _posNum(position, const ['current', 'mark', 'price']);
    final double? pnl = _posNum(position, const ['pnl', 'unrealized_pnl']);

    return Container(
      margin: const EdgeInsets.only(bottom: AppTokens.spaceSm),
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceLg,
        vertical: AppTokens.spaceMd,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        border: Border.all(
          color: scheme.outlineVariant,
          width: AppTokens.borderWidth,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  symbol,
                  style: TextStyle(
                    fontSize: AppTokens.bodySize,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  size == '--' ? '--' : 'Size $size',
                  style: TextStyle(
                    fontSize: AppTokens.fontSizeTiny,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (entry != null) ...[
            _posPrice(scheme, 'ENTRY', entry.toStringAsFixed(2)),
            const SizedBox(width: AppTokens.spaceLg),
          ],
          if (current != null) ...[
            _posPrice(scheme, 'MARK', current.toStringAsFixed(2)),
            const SizedBox(width: AppTokens.spaceLg),
          ],
          if (pnl != null)
            PriceText(
              '${pnl >= 0 ? '+' : '-'}\$${pnl.abs().toStringAsFixed(2)}',
              fontSize: AppTokens.bodySize,
            ),
        ],
      ),
    );
  }

  Widget _posPrice(ColorScheme scheme, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: AppTokens.fontSizeTiny,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        PriceText(value, fontSize: AppTokens.captionSize),
      ],
    );
  }

  double? _posNum(Map<String, dynamic> m, List<String> keys) {
    for (final key in keys) {
      final v = m[key];
      if (v is num) return v.toDouble();
    }
    return null;
  }

  String _posStr(
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
}
