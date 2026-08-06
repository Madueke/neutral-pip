import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/trade_signal.dart';

/// Premium signal card: pair, bias, entry/SL/TP, risk, and an explained
/// confidence meter. Confidence is never shown as a bare percentage.
class TradeCard extends StatelessWidget {
  final TradeSignal signal;
  final VoidCallback? onTap;

  const TradeCard({super.key, required this.signal, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isLong = signal.bias == 'LONG';
    final biasColor = isLong ? AppColors.bull : AppColors.bear;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;
    final secondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final muted = isDark ? AppColors.textMutedDark : AppColors.textMutedLight;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppTokens.spaceLg),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(AppTokens.radiusCard),
            border: Border.all(color: border, width: AppTokens.borderWidth),
            boxShadow: AppShadows.card,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    signal.pair,
                    style: AppFonts.heading(
                      size: AppTokens.titleSize,
                      weight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: AppTokens.spaceSm),
                  _Tag(label: signal.timeframe, color: secondary),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTokens.spaceMd,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: biasColor.withValues(alpha: 0.14),
                      borderRadius:
                          BorderRadius.circular(AppTokens.radiusChip),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isLong
                              ? Icons.arrow_upward_rounded
                              : Icons.arrow_downward_rounded,
                          size: 14,
                          color: biasColor,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          signal.bias,
                          style: TextStyle(
                            fontSize: AppTokens.captionSize,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: biasColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTokens.spaceLg),
              Row(
                children: [
                  _Level(
                    label: 'ENTRY',
                    value: _fmt(signal.entry),
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  _Level(
                    label: 'STOP LOSS',
                    value: _fmt(signal.stopLoss),
                    color: AppColors.bear,
                  ),
                  _Level(
                    label: 'TAKE PROFIT',
                    value: _fmt(signal.takeProfit),
                    color: AppColors.bull,
                  ),
                  _Level(
                    label: 'RISK / RR',
                    value: '${_fmt(signal.riskPercent)}% / '
                        '${signal.riskReward.toStringAsFixed(1)}R',
                    color: AppColors.amber,
                  ),
                ],
              ),
              const SizedBox(height: AppTokens.spaceLg),
              _ConfidenceMeter(signal: signal, muted: muted),
              const SizedBox(height: AppTokens.spaceLg),
              _FactorRow(
                icon: Icons.hub_rounded,
                label: 'Market structure',
                value: signal.marketStructure,
                muted: muted,
              ),
              _FactorRow(
                icon: Icons.water_drop_rounded,
                label: 'Liquidity',
                value: signal.liquidity,
                muted: muted,
              ),
              _FactorRow(
                icon: Icons.show_chart_rounded,
                label: 'Trend',
                value: signal.trend,
                muted: muted,
              ),
              _FactorRow(
                icon: Icons.campaign_rounded,
                label: 'News impact',
                value: signal.newsImpact,
                muted: muted,
              ),
              const SizedBox(height: AppTokens.spaceMd),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.spaceMd,
                  vertical: AppTokens.spaceSm,
                ),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppTokens.radiusControl),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.track_changes_rounded,
                      size: 16,
                      color: AppColors.info,
                    ),
                    const SizedBox(width: AppTokens.spaceSm),
                    Expanded(
                      child: Text(
                        signal.strategyMatch,
                        style: AppFonts.body(
                          size: AppTokens.captionSize,
                          weight: FontWeight.w600,
                          color: AppColors.info,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _fmt(double v) {
    return v == v.roundToDouble()
        ? v.toStringAsFixed(0)
        : v.toStringAsFixed(v.abs() < 1000 ? 1 : 0);
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color color;
  const _Tag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTokens.radiusChip),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _Level extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Level({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppFonts.body(
              size: AppTokens.fontSizeTiny,
              weight: FontWeight.w600,
              color: color.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: AppFonts.heading(
              size: 13,
              weight: FontWeight.w700,
              color: color,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfidenceMeter extends StatelessWidget {
  final TradeSignal signal;
  final Color muted;
  const _ConfidenceMeter({required this.signal, required this.muted});

  @override
  Widget build(BuildContext context) {
    final confidence = signal.confidence.clamp(0, 100);
    final color = confidence >= 70
        ? AppColors.bull
        : confidence >= 50
            ? AppColors.amber
            : AppColors.warning;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'CONFIDENCE',
              style: AppFonts.body(
                size: AppTokens.fontSizeTiny,
                weight: FontWeight.w700,
                color: muted,
              ),
            ),
            const Spacer(),
            Text(
              '$confidence%',
              style: AppFonts.heading(
                size: 13,
                weight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppTokens.radiusChip),
          child: LinearProgressIndicator(
            value: confidence / 100,
            minHeight: 6,
            backgroundColor: color.withValues(alpha: 0.15),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        const SizedBox(height: AppTokens.spaceSm),
        Text(
          signal.confidenceReason,
          style: AppFonts.body(
            size: AppTokens.captionSize,
            color: muted,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _FactorRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color muted;
  const _FactorRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.muted,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.spaceXs * 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: muted),
          const SizedBox(width: AppTokens.spaceSm),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: AppFonts.body(
                  size: AppTokens.captionSize,
                  color: muted,
                ),
                children: [
                  TextSpan(
                    text: '$label  ',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: value),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
