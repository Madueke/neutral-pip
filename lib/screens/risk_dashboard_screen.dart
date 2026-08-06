import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../services/trading_api_service.dart';
import '../widgets/app_animations.dart';
import '../widgets/circular_gauge.dart';
import '../widgets/logo_loader.dart';
import '../widgets/price_text.dart';
import '../widgets/risk_bar.dart';
import '../widgets/stat_card.dart';

/// Risk dashboard: account health gauge, exposure and loss meters, and open
/// positions.
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

  double _fraction(double? used, double? limit) {
    if (used == null || limit == null || limit <= 0) return 0;
    return (used / limit).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final double? exposure = _num(const ['exposure_percent', 'exposure']);
    final double? lossUsed = _num(const [
      'daily_loss_used',
      'daily_loss_used_percent',
    ]);
    final double? lossLimit = _num(const [
      'daily_loss_limit',
      'daily_loss_limit_percent',
    ]);
    final double? weeklyUsed = _num(const [
      'weekly_loss_used',
      'weekly_loss_used_percent',
    ]);
    final double? weeklyLimit = _num(const [
      'weekly_loss_limit',
      'weekly_loss_limit_percent',
    ]);
    final double? drawdown = _num(const [
      'drawdown',
      'drawdown_percent',
      'max_drawdown',
    ]);
    final double? maxAllowed = _num(const [
      'max_allowed_loss',
      'max_allowed_loss_percent',
      'max_loss',
    ]);

    final double? lossFraction =
        (lossUsed != null && lossLimit != null && lossLimit > 0)
        ? lossUsed / lossLimit
        : null;
    final double? exposureFraction = exposure != null && exposure > 1
        ? exposure / 100
        : exposure;

    final String riskLevel = _str(const [
      'riskLevel',
      'risk_level',
    ], 'unknown').toLowerCase();
    final bool severe =
        riskLevel == 'high' ||
        riskLevel == 'critical' ||
        (lossFraction != null && lossFraction >= 0.8) ||
        (exposureFraction != null && exposureFraction >= 0.8);

    final hasLiveData =
        exposure != null ||
        lossUsed != null ||
        drawdown != null ||
        weeklyUsed != null;
    // Account health: 100 minus weighted risk usage. Falls back to a neutral
    // preview value when no backend data is present.
    final double health = hasLiveData
        ? (100 -
                  (exposureFraction ?? 0) * 40 -
                  (lossFraction ?? 0) * 40 -
                  _fraction(drawdown, maxAllowed) * 20)
              .clamp(0, 100)
        : 82.0;
    final double healthFraction = health / 100;
    final Color healthColor = health >= 70
        ? AppColors.bull
        : health >= 45
        ? AppColors.amber
        : AppColors.bear;

    final rawPositions = _data['open_positions'];
    final List<Map<String, dynamic>> positions = rawPositions is List
        ? rawPositions.whereType<Map<String, dynamic>>().toList()
        : <Map<String, dynamic>>[];

    return Scaffold(
      backgroundColor: Colors.transparent,
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
          ? const Center(child: LogoLoader())
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
                  if (severe) FadeInUp(child: _buildSeverityBanner()),
                  if (severe) const SizedBox(height: AppTokens.spaceLg),
                  FadeInUp(
                    child: _buildGaugeHero(
                      health,
                      healthFraction,
                      healthColor,
                      isDark,
                    ),
                  ),
                  const SizedBox(height: AppTokens.spaceXl),
                  FadeInUp(
                    delay: const Duration(milliseconds: 80),
                    child: Row(
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
                            valueColor: (lossFraction ?? 0) >= 0.8
                                ? AppColors.bear
                                : (lossFraction ?? 0) >= 0.5
                                ? AppColors.amber
                                : AppColors.bull,
                          ),
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
                  ),
                  const SizedBox(height: AppTokens.spaceXl),
                  FadeInUp(
                    child: Text(
                      'LIMIT USAGE',
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
                  FadeInUp(child: _buildProgressMeters()),
                  const SizedBox(height: AppTokens.spaceXl),
                  FadeInUp(
                    child: Text(
                      'OPEN POSITIONS',
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
                  if (positions.isEmpty)
                    FadeInUp(child: _buildEmptyPositions())
                  else
                    for (final position in positions)
                      FadeInUp(child: _buildPositionRow(position)),
                  if (_isStub) ...[
                    const SizedBox(height: AppTokens.spaceXl),
                    FadeInUp(child: _buildStubHint()),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildGaugeHero(
    double health,
    double healthFraction,
    Color color,
    bool isDark,
  ) {
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
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
        ),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        children: [
          CircularGauge(
            value: healthFraction,
            valueText: health.toStringAsFixed(0),
            label: 'ACCOUNT HEALTH',
            color: color,
          ),
          const SizedBox(height: AppTokens.spaceLg),
          Text(
            _isStub && health == 82
                ? 'Live health requires a trading backend. '
                      'Add its URL in Settings.'
                : 'Your account is in good shape. '
                      'Stick to your plan and size within limits.',
            textAlign: TextAlign.center,
            style: AppFonts.body(
              size: AppTokens.captionSize,
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressMeters() {
    final double? exposure = _num(const ['exposure_percent', 'exposure']);
    final double? lossUsed = _num(const [
      'daily_loss_used',
      'daily_loss_used_percent',
    ]);
    final double? lossLimit = _num(const [
      'daily_loss_limit',
      'daily_loss_limit_percent',
    ]);
    final double? weeklyUsed = _num(const [
      'weekly_loss_used',
      'weekly_loss_used_percent',
    ]);
    final double? weeklyLimit = _num(const [
      'weekly_loss_limit',
      'weekly_loss_limit_percent',
    ]);
    final double? drawdown = _num(const [
      'drawdown',
      'drawdown_percent',
      'max_drawdown',
    ]);
    final double? maxAllowed = _num(const [
      'max_allowed_loss',
      'max_allowed_loss_percent',
      'max_loss',
    ]);

    final exposureFraction = exposure != null && exposure > 1
        ? exposure / 100
        : exposure;

    return Container(
      padding: const EdgeInsets.all(AppTokens.spaceLg),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: AppTokens.borderWidth,
        ),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        children: [
          RiskBar(
            fraction: exposureFraction ?? 0,
            leftLabel: 'EXPOSURE',
            rightLabel: exposure == null
                ? '--'
                : '${exposure.toStringAsFixed(0)}%',
          ),
          const SizedBox(height: AppTokens.spaceMd),
          RiskBar(
            fraction: _fraction(lossUsed, lossLimit),
            leftLabel: 'DAILY LOSS',
            rightLabel: lossUsed == null
                ? '--'
                : '${lossUsed.toStringAsFixed(0)}% / '
                      '${lossLimit?.toStringAsFixed(0) ?? '--'}%',
          ),
          const SizedBox(height: AppTokens.spaceMd),
          RiskBar(
            fraction: _fraction(weeklyUsed, weeklyLimit),
            leftLabel: 'WEEKLY LOSS',
            rightLabel: weeklyUsed == null
                ? '--'
                : '${weeklyUsed.toStringAsFixed(0)}% / '
                      '${weeklyLimit?.toStringAsFixed(0) ?? '--'}%',
          ),
          const SizedBox(height: AppTokens.spaceMd),
          RiskBar(
            fraction: _fraction(drawdown, maxAllowed),
            leftLabel: 'DRAWDOWN',
            rightLabel: drawdown == null
                ? '--'
                : '${drawdown.toStringAsFixed(0)}% / '
                      '${maxAllowed?.toStringAsFixed(0) ?? '--'}%',
          ),
        ],
      ),
    );
  }

  Widget _buildSeverityBanner() {
    return Container(
      padding: const EdgeInsets.all(AppTokens.spaceLg),
      decoration: BoxDecoration(
        color: AppColors.bear.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        border: Border.all(
          color: AppColors.bear.withValues(alpha: 0.4),
          width: AppTokens.borderWidth,
        ),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.bear),
          const SizedBox(width: AppTokens.spaceMd),
          Expanded(
            child: Text(
              'Risk limits approaching. Review exposure and open positions '
              'before taking new trades.',
              style: AppFonts.body(
                size: AppTokens.bodySize,
                weight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
                height: 1.4,
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
          const Icon(Icons.inbox_rounded, color: AppColors.amber, size: 28),
          const SizedBox(height: AppTokens.spaceMd),
          Text(
            'No open positions',
            style: AppFonts.body(
              size: AppTokens.bodySize,
              weight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStubHint() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppTokens.spaceLg),
      decoration: BoxDecoration(
        color: AppColors.amber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        border: Border.all(
          color: AppColors.amber.withValues(alpha: 0.35),
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
              style: AppFonts.body(
                size: AppTokens.captionSize,
                color: scheme.onSurface,
                height: 1.4,
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
    final double? current = _posNum(position, const [
      'current',
      'mark',
      'price',
    ]);
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
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  symbol,
                  style: AppFonts.heading(
                    size: AppTokens.bodySize,
                    weight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  size == '--' ? '--' : 'Size $size',
                  style: AppFonts.body(
                    size: AppTokens.fontSizeTiny,
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
          style: AppFonts.body(
            size: AppTokens.fontSizeTiny,
            weight: FontWeight.w600,
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
