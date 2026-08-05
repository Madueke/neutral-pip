import 'package:flutter/material.dart';
import '../config/theme.dart';

/// BUY / SELL / NEUTRAL signal chip. Green, red, and amber are used here
/// strictly because they carry buy/sell/neutral signal meaning.
class SignalChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;

  const SignalChip._(this.label, this.color, this.icon);

  factory SignalChip.buy([String label = 'BUY']) =>
      SignalChip._(label, AppColors.bull, Icons.arrow_upward_rounded);
  factory SignalChip.sell([String label = 'SELL']) =>
      SignalChip._(label, AppColors.bear, Icons.arrow_downward_rounded);
  factory SignalChip.neutral([String label = 'NEUTRAL']) =>
      SignalChip._(label, AppColors.amber, Icons.remove_rounded);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceSm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(AppTokens.radiusChip),
        border: Border.all(color: color.withOpacity(0.5), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: AppTokens.fontSizeTiny,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
