import 'package:shared_preferences/shared_preferences.dart';

/// Standalone client for the Trading Mode backend.
///
/// TRADING MODE: never add tap-based execution here.
/// This service deliberately has NO dependency on ScreenAutomationService,
/// TaskExecutor, or ActionHandler, and must never call any tap/click/swipe
/// method. All trading actions go through the secure backend API instead.
class TradingApiService {
  String _tradingBackendUrl = '';

  /// Configurable backend base URL (SharedPreferences key:
  /// trading_backend_url). Empty until the user sets it in Settings.
  String get tradingBackendUrl => _tradingBackendUrl;

  bool get isConfigured => _tradingBackendUrl.isNotEmpty;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _tradingBackendUrl = prefs.getString('trading_backend_url') ?? '';
  }

  Future<void> saveSettings({required String tradingBackendUrl}) async {
    _tradingBackendUrl = tradingBackendUrl;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('trading_backend_url', tradingBackendUrl);
  }

  /// Analyze a symbol on a timeframe. Future backend endpoint: POST /analyze.
  ///
  /// TRADING MODE: never add tap-based execution here.
  Future<Map<String, dynamic>> analyze(
    String symbol,
    String timeframe,
  ) async {
    return {
      'status': 'stub',
      'symbol': symbol,
      'timeframe': timeframe,
      'summary': 'Mock analysis - backend not configured yet.',
    };
  }

  /// Chat with the trading assistant. Future backend endpoint: POST /chat.
  ///
  /// TRADING MODE: never add tap-based execution here.
  Future<String> chat(
    String message,
    List<Map<String, String>> history, {
    List<Map<String, dynamic>> attachments = const [],
  }) async {
    // TRADING MODE: never add tap-based execution here.
    // Attachments (e.g. chart screenshots) are accepted by the stub but
    // ignored for now; the real backend will receive them with the text.
    return 'Mock trading response - backend not configured yet. '
        'Configure a trading backend URL in Settings to enable live chat.';
  }

  /// Fetch the trading journal. Future backend endpoint: GET /journal.
  ///
  /// TRADING MODE: never add tap-based execution here.
  Future<Map<String, dynamic>> getJournal() async {
    return {
      'status': 'stub',
      'entries': <Map<String, dynamic>>[],
    };
  }

  /// Fetch current risk status. Future backend endpoint: GET /risk-status.
  ///
  /// TRADING MODE: never add tap-based execution here.
  Future<Map<String, dynamic>> getRiskStatus() async {
    return {
      'status': 'stub',
      'riskLevel': 'unknown',
      'message': 'Mock risk status - backend not configured yet.',
    };
  }

  /// Submit a trade signal for execution. Future backend endpoint:
  /// POST /execute-trade-signal (placeholder; exact route to be defined by
  /// the hosted backend).
  ///
  /// TRADING MODE: never add tap-based execution here. Trade execution must
  /// only ever happen server-side through this API - never via screen taps.
  Future<Map<String, dynamic>> executeTradeSignal(
    Map<String, dynamic> signal,
  ) async {
    return {
      'status': 'stub',
      'accepted': false,
      'message': 'Mock trade signal handler - backend not configured yet.',
      'signal': signal,
    };
  }
}
