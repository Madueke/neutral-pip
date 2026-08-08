import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../config/theme.dart';
import 'logo_loader.dart';

/// TRADING MODE: read-only display of TradingView's official embeddable
/// Advanced Chart widget inside a WebView. No login, no credentials, no
/// automation, and nothing is extracted from the page — it is purely so the
/// user can see a real, live chart in-app. All data fetching for the agent
/// stays on the backend's market-data layer.

/// Map our watchlist symbols (as saved in Connect Trading Accounts) to
/// TradingView exchange-qualified symbols.
const Map<String, String> _tvSymbolMap = {
  'XAUUSD': 'OANDA:XAUUSD',
  'XAGUSD': 'OANDA:XAGUSD',
  'GOLD': 'OANDA:XAUUSD',
  'SILVER': 'OANDA:XAGUSD',
  'EURUSD': 'OANDA:EURUSD',
  'GBPUSD': 'OANDA:GBPUSD',
  'USDJPY': 'OANDA:USDJPY',
  'US500': 'CURRENCYCOM:US500',
  'SPX': 'CURRENCYCOM:US500',
  'US30': 'CURRENCYCOM:US30',
  'NAS100': 'CURRENCYCOM:NAS100',
  'USOIL': 'CURRENCYCOM:USOIL',
  'WTI': 'CURRENCYCOM:USOIL',
  'BTCUSD': 'BINANCE:BTCUSDT',
  'ETHUSD': 'BINANCE:ETHUSDT',
};

const List<String> _cryptoBases = [
  'BTC',
  'ETH',
  'XRP',
  'LTC',
  'SOL',
  'ADA',
  'DOGE',
  'DOT',
  'LINK',
  'AVAX',
  'MATIC',
  'BNB',
];

/// Our timeframe codes -> TradingView widget interval values.
const Map<String, String> _tvIntervalMap = {
  'M1': '1',
  'M5': '5',
  'M15': '15',
  'M30': '30',
  'H1': '60',
  'H2': '120',
  'H4': '240',
  'D1': 'D',
  'W1': 'W',
};

/// Convert one of our watchlist symbols to a TradingView symbol.
String toTradingViewSymbol(String symbol) {
  final s = symbol.trim().toUpperCase();
  final mapped = _tvSymbolMap[s];
  if (mapped != null) return mapped;
  final base = s.length > 3 ? s.substring(0, 3) : s;
  if (_cryptoBases.contains(base)) {
    final pair = s.endsWith('USD')
        ? '${s.substring(0, s.length - 3)}USDT'
        : '${base}USDT';
    return 'BINANCE:$pair';
  }
  if (RegExp(r'^[A-Z]{6}$').hasMatch(s)) return 'FX:$s';
  return s;
}

/// Convert one of our timeframe codes (M15/H1/H4/D1...) to a TradingView
/// widget interval value. Unknown codes default to 60 (H1).
String toTradingViewInterval(String timeframe) {
  return _tvIntervalMap[timeframe.trim().toUpperCase()] ?? '60';
}

/// The official TradingView Advanced Chart embed (dark theme), parameterized
/// by symbol and timeframe. Rendered as a self-contained HTML document so it
/// can be loaded straight into a WebView.
String buildTradingViewChartHtml(String symbol, String timeframe) {
  final tvSymbol = toTradingViewSymbol(symbol);
  final interval = toTradingViewInterval(timeframe);
  return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <style>
    html, body { margin: 0; padding: 0; height: 100%; overflow: hidden;
                 position: relative; background-color: #0B0F19; }
    /* Close the 100% height chain: the wrapper must size itself to the
       viewport so the autosized widget fills it completely instead of
       collapsing to its default block height. */
    .tradingview-widget-container { position: relative; width: 100%; height: 100%; }
    .tradingview-widget-container__widget { width: 100%; height: 100%; }
    #tradingview_widget { width: 100%; height: 100%; }
  </style>
</head>
<body>
  <div class="tradingview-widget-container">
    <div id="tradingview_widget"></div>
    <script type="text/javascript" src="https://s3.tradingview.com/tv.js"></script>
    <script type="text/javascript">
      new TradingView.widget({
        "autosize": true,
        "symbol": "$tvSymbol",
        "interval": "$interval",
        "timezone": "Etc/UTC",
        "theme": "dark",
        "style": "1",
        "locale": "en",
        "toolbar_bg": "#161D2F",
        "enable_publishing": false,
        "allow_symbol_change": true,
        "save_image": false,
        "container_id": "tradingview_widget"
      });
    </script>
  </div>
</body>
</html>
''';
}

/// A live TradingView Advanced Chart for one symbol/timeframe.
///
/// [height] pins the chart to a fixed height; when null the chart expands to
/// fill its parent. Rebuild with a fresh [Key] (e.g. keyed on symbol +
/// timeframe) to switch instruments.
class TradingViewChart extends StatefulWidget {
  final String symbol;
  final String timeframe;
  final double? height;

  const TradingViewChart({
    super.key,
    required this.symbol,
    required this.timeframe,
    this.height,
  });

  @override
  State<TradingViewChart> createState() => _TradingViewChartState();
}

class _TradingViewChartState extends State<TradingViewChart> {
  late WebViewController _controller;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller = _buildController();
  }

  WebViewController _buildController() {
    return WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppColors.bgDark)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            // Only surface failures of the main document; subresources
            // (chart assets) may fail transiently while the chart still
            // comes up.
            if (error.isForMainFrame == true && mounted) {
              setState(() => _failed = true);
            }
          },
        ),
      )
      ..loadHtmlString(
        buildTradingViewChartHtml(widget.symbol, widget.timeframe),
      );
  }

  void _retry() {
    setState(() {
      _loading = true;
      _failed = false;
    });
    _controller = _buildController();
  }

  @override
  Widget build(BuildContext context) {
    final child = Container(
      decoration: BoxDecoration(
        color: AppColors.bgDark,
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
      ),
      child: Stack(
        children: [
          Positioned.fill(child: WebViewWidget(controller: _controller)),
          if (_loading)
            const Positioned.fill(
              child: ColoredBox(
                color: AppColors.bgDark,
                child: Center(child: LogoLoader(size: 20)),
              ),
            ),
          if (_failed)
            Positioned.fill(
              child: ColoredBox(
                color: AppColors.bgDark,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.cloud_off_rounded,
                        size: 34,
                        color: AppColors.textMutedDark,
                      ),
                      const SizedBox(height: AppTokens.spaceSm),
                      Text(
                        "Couldn't load the chart",
                        style: AppFonts.body(
                          size: AppTokens.bodySize,
                          weight: FontWeight.w600,
                          color: AppColors.textSecondaryDark,
                        ),
                      ),
                      const SizedBox(height: AppTokens.spaceSm),
                      TextButton.icon(
                        onPressed: _retry,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    if (widget.height == null) return child;
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: child,
    );
  }
}
