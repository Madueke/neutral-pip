/// A structured AI trade setup rendered as a premium card.
class TradeSignal {
  final String pair;
  final String timeframe;
  final String bias; // "LONG" or "SHORT"
  final double entry;
  final double stopLoss;
  final double takeProfit;
  final double riskPercent;
  final double riskReward;
  final int confidence; // 0-100
  final String confidenceReason;
  final String marketStructure;
  final String liquidity;
  final String trend;
  final String newsImpact;
  final String strategyMatch;

  const TradeSignal({
    required this.pair,
    required this.timeframe,
    required this.bias,
    required this.entry,
    required this.stopLoss,
    required this.takeProfit,
    required this.riskPercent,
    required this.riskReward,
    required this.confidence,
    required this.confidenceReason,
    required this.marketStructure,
    required this.liquidity,
    required this.trend,
    required this.newsImpact,
    required this.strategyMatch,
  });

  /// Sample signals for the dashboard preview. Replace with live backend
  /// data as the Trading API lands.
  static const List<TradeSignal> samples = [
    TradeSignal(
      pair: 'XAU/USD',
      timeframe: '4H',
      bias: 'LONG',
      entry: 2418.5,
      stopLoss: 2398.0,
      takeProfit: 2462.0,
      riskPercent: 1.2,
      riskReward: 2.2,
      confidence: 74,
      confidenceReason:
          'Clean higher-low series with liquidity resting above the 2460 swing. '
          'Trend is bullish and the news calendar is light for gold.',
      marketStructure: 'Higher highs, higher lows',
      liquidity: 'Buyside resting above 2460.0',
      trend: 'Bullish on 4H and daily',
      newsImpact: 'Low — no high-impact data today',
      strategyMatch: 'Matches your breakout strategy',
    ),
    TradeSignal(
      pair: 'BTC/USDT',
      timeframe: '1H',
      bias: 'SHORT',
      entry: 108400,
      stopLoss: 110100,
      takeProfit: 104900,
      riskPercent: 0.9,
      riskReward: 1.9,
      confidence: 61,
      confidenceReason:
          'Rejection at the 108k supply zone with bearish divergence on RSI. '
          'Structure is breaking lower but volume is moderate.',
      marketStructure: 'Lower lows on the 1H',
      liquidity: 'Sellside liquidity at 104900',
      trend: 'Neutral, rolling over',
      newsImpact: 'Medium — CPI at 14:30 UTC',
      strategyMatch: 'Partial match — risk below your tolerance',
    ),
  ];
}
