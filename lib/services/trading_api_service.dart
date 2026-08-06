import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'ai_service.dart';
import '../config/feature_flags.dart';
import '../models/chat_message.dart';

/// Standalone client for the Trading Mode backend.
///
/// TRADING MODE: never add tap-based execution here.
/// This service deliberately has NO dependency on ScreenAutomationService,
/// TaskExecutor, or ActionHandler, and must never call any tap/click/swipe
/// method. All trading actions go through the secure backend API instead.
class TradingApiService {
  final AiService _aiService;

  TradingApiService(this._aiService);

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

  /// Chat with the trading assistant.
  ///
  /// When a backend URL is configured, the text, prior history, and
  /// attachment metadata are POSTed to [tradingBackendUrl]/chat and the
  /// response body's `reply` field is returned. If the backend is not
  /// configured (or the POST fails), the user's existing AI key/model is
  /// used directly: vision when an image attachment is present, otherwise
  /// a plain chat message.
  ///
  /// TRADING MODE: never add tap-based execution here.
  Future<String> chat(
    String message,
    List<Map<String, String>> history, {
    List<Map<String, dynamic>> attachments = const [],
  }) async {
    if (isConfigured) {
      // A URL attachment becomes the chart_url field; the backend fetches
      // the chart image itself (first URL wins; the field is singular).
      final urlAttachments = attachments
          .where((a) => a['type'] == 'url')
          .toList();
      final chartUrl = urlAttachments.isEmpty
          ? null
          : urlAttachments.first['path'] as String?;
      try {
        final response = await http
            .post(
              Uri.parse('$tradingBackendUrl/chat'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'message': message,
                'history': history,
                'attachments': _attachmentMetadata(attachments),
                if (chartUrl != null && chartUrl.isNotEmpty)
                  'chart_url': chartUrl,
              }),
            )
            .timeout(const Duration(minutes: 5));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data is Map<String, dynamic> &&
              data['reply'] is String &&
              (data['reply'] as String).trim().isNotEmpty) {
            return data['reply'] as String;
          }
        }
        // Non-200 or missing reply: fall through to the direct AI path.
      } catch (_) {
        // Network or parse error: fall through to the direct AI path.
      }
      final fallback = await _directAiReply(message, history, attachments);
      return '[Backend unavailable — using direct AI] $fallback';
    }

    // No backend configured yet: use the user's existing AI key directly.
    return _directAiReply(message, history, attachments);
  }

  /// Build attachment metadata for the backend: name/type/mimeType/sizeBytes
  /// only, never the raw base64 (the backend requests file contents
  /// separately).
  ///
  /// TRADING MODE: never add tap-based execution here.
  List<Map<String, dynamic>> _attachmentMetadata(
    List<Map<String, dynamic>> attachments,
  ) {
    return attachments
        .map((a) => {
              'name': a['name'],
              'type': a['type'],
              'mimeType': a['mimeType'],
              'sizeBytes': a['sizeBytes'],
            })
        .toList();
  }

  /// Direct-AI fallback used when no backend is configured or the backend
  /// call fails: vision when an image attachment is present, plain chat
  /// otherwise.
  ///
  /// TRADING MODE: never add tap-based execution here.
  Future<String> _directAiReply(
    String message,
    List<Map<String, String>> history,
    List<Map<String, dynamic>> attachments,
  ) async {
    final chatAttachments = attachments
        .map((a) => ChatAttachment.fromJson(a))
        .toList();

    // URL attachments become text lines on the message, one per URL, so the
    // model knows it must fetch and analyze the chart at that address.
    // They are kept out of the attachment list passed to the vision call.
    final urlLines = chatAttachments
        .where((a) => a.type == 'url')
        .map(
          (a) =>
              'Chart URL provided: ${a.path} — please fetch and analyze '
              'this chart image.',
        )
        .toList();

    if (chatAttachments.any((a) => a.type == 'image')) {
      final visionText = [message, ...urlLines].join('\n');
      final nonUrlAttachments = chatAttachments
          .where((a) => a.type != 'url')
          .toList();
      final chatHistory = history
          .map((m) => ChatMessage(
                role: m['role'] ?? 'user',
                content: m['content'] ?? '',
              ))
          .toList();
      return _aiService.sendVisionMessage(
        visionText,
        nonUrlAttachments,
        chatHistory,
      );
    }
    if (urlLines.isNotEmpty) {
      // No image attached: keep the URL visible to the model through the
      // plain text message so it is never silently dropped.
      return _aiService.sendMessage(
        [message, ...urlLines].join('\n'),
        isAgentMode: false,
      );
    }
    return _aiService.sendMessage(message, isAgentMode: false);
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

  // ---------------------------------------------------------------------------
  // Connect Trading Accounts
  //
  // Backend contract (endpoints not implemented yet, see
  // FeatureFlags.mockTradingAccountBackend):
  //   POST /connect-account      body: { user_id, account: 'tradingview'|'mt5',
  //                                     ...account-specific fields }
  //                              → 200 { status: 'ok', session: { token, user_id } }
  //   GET  /account-status       query: user_id
  //                              → 200 { user_id, accounts: { <key>: { status,
  //                                     detail? } } }   status in
  //                                     'connected'|'not_connected'|'error'
  //   POST /disconnect-account   body: { user_id, account: <key> }
  //                              → 200 { status: 'ok', disconnected: true }
  //
  // Client-side we persist ONLY the returned session token (per account) and
  // a stable client-generated user_id. Sensitive MT5 credentials are sent to
  // the backend once and are never stored locally.
  //
  // TRADING MODE: never add tap-based execution here. Account connection is
  // a backend-only operation - the app never touches a broker terminal.
  // ---------------------------------------------------------------------------

  /// Stable client-generated user id, persisted in SharedPreferences. Used
  /// as `user_id` on every account endpoint until the backend ships auth.
  Future<String> _userId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('trading_user_id');
    if (id == null || id.isEmpty) {
      id =
          'u_${DateTime.now().millisecondsSinceEpoch}_'
          '${_randomSuffix()}';
      await prefs.setString('trading_user_id', id);
    }
    return id;
  }

  String _randomSuffix() {
    final s = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return s.substring(s.length - 6);
  }

  /// SharedPreferences keys holding the per-account session token returned by
  /// the backend. These are the ONLY thing persisted after a connect; the
  /// raw credentials never touch disk.
  static const String _tokenPrefKeyPrefix = 'trading_account_token_';
  static const String tradingViewAccountKey = 'tradingview';
  static const String mt5AccountKey = 'mt5';

  /// Connect the TradingView watchlist (no login): posts the selected
  /// symbols and timeframes. Future backend endpoint: POST /connect-account.
  ///
  /// TRADING MODE: never add tap-based execution here.
  Future<Map<String, dynamic>> connectTradingView({
    required List<String> symbols,
    required List<String> timeframes,
  }) async {
    final userId = await _userId();
    final body = {
      'user_id': userId,
      'account': tradingViewAccountKey,
      'symbols': symbols,
      'timeframes': timeframes,
    };

    final response = await _postAccount('/connect-account', body, userId);
    if (response != null) {
      if (response['status'] == 'ok') {
        await _persistSession(tradingViewAccountKey, response);
      }
      return response;
    }

    // TODO(mock): remove once the real backend ships. Mirrors the expected
    // 200 response so the UI is testable end to end.
    final mock = {
      'status': 'ok',
      'session': {
        'token': 'mock-tv-${_randomSuffix()}',
        'user_id': userId,
      },
    };
    await _persistSession(tradingViewAccountKey, mock);
    return mock;
  }

  /// Connect a real MT5 account. Credentials are posted to the backend once
  /// and are never persisted client-side; only the returned session token is
  /// kept. Future backend endpoint: POST /connect-account.
  ///
  /// TRADING MODE: never add tap-based execution here.
  Future<Map<String, dynamic>> connectMt5({
    required String accountNumber,
    required String password,
    required String brokerServer,
  }) async {
    final userId = await _userId();
    final body = {
      'user_id': userId,
      'account': mt5AccountKey,
      'account_number': accountNumber.trim(),
      'password': password,
      'broker_server': brokerServer.trim(),
    };

    final response = await _postAccount('/connect-account', body, userId);
    if (response != null) {
      if (response['status'] == 'ok') {
        await _persistSession(mt5AccountKey, response);
      }
      return response;
    }

    // TODO(mock): remove once the real backend ships.
    final mock = {
      'status': 'ok',
      'session': {
        'token': 'mock-mt5-${_randomSuffix()}',
        'user_id': userId,
      },
    };
    await _persistSession(mt5AccountKey, mock);
    return mock;
  }

  /// Fetch connection status for every known account. Future backend
  /// endpoint: GET /account-status?user_id=...
  ///
  /// TRADING MODE: never add tap-based execution here.
  Future<Map<String, dynamic>> getAccountStatus() async {
    final userId = await _userId();

    if (!FeatureFlags.mockTradingAccountBackend && isConfigured) {
      try {
        final uri = Uri.parse('$tradingBackendUrl/account-status').replace(
          queryParameters: {'user_id': userId},
        );
        final response = await http
            .get(uri, headers: {'Content-Type': 'application/json'})
            .timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data is Map<String, dynamic>) return data;
        }
      } catch (_) {
        // Fall through to the mock below so the screen still renders.
      }
    }

    // TODO(mock): remove once the real backend ships. Derives a plausible
    // status from the locally stored session tokens.
    final prefs = await SharedPreferences.getInstance();
    return {
      'user_id': userId,
      'accounts': {
        tradingViewAccountKey: {
          'status': prefs.getString(
                    '$_tokenPrefKeyPrefix$tradingViewAccountKey',
                  ) !=
                  null
              ? 'connected'
              : 'not_connected',
        },
        mt5AccountKey: {
          'status':
              prefs.getString('$_tokenPrefKeyPrefix$mt5AccountKey') != null
                  ? 'connected'
                  : 'not_connected',
        },
      },
    };
  }

  /// Disconnect an account. Future backend endpoint:
  /// POST /disconnect-account.
  ///
  /// TRADING MODE: never add tap-based execution here.
  Future<Map<String, dynamic>> disconnectAccount(String accountKey) async {
    final userId = await _userId();
    final body = {
      'user_id': userId,
      'account': accountKey,
    };

    final response = await _postAccount('/disconnect-account', body, userId);
    // Clear the local session token regardless of mock/real outcome.
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_tokenPrefKeyPrefix$accountKey');

    if (response != null) return response;
    return {'status': 'ok', 'disconnected': true, 'account': accountKey};
  }

  /// Shared POST for connect/disconnect; returns the decoded 200 body, or
  /// null when the backend is mocked/unconfigured/unreachable.
  Future<Map<String, dynamic>?> _postAccount(
    String path,
    Map<String, dynamic> body,
    String userId,
  ) async {
    if (FeatureFlags.mockTradingAccountBackend || !isConfigured) return null;
    try {
      final response = await http
          .post(
            Uri.parse('$tradingBackendUrl$path'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) return data;
      }
      return {
        'status': 'error',
        'message': 'Backend returned HTTP ${response.statusCode}.',
      };
    } catch (e) {
      return {
        'status': 'error',
        'message': 'Could not reach backend: $e',
      };
    }
  }

  /// Persist only the session token from a successful connect response.
  Future<void> _persistSession(
    String accountKey,
    Map<String, dynamic> response,
  ) async {
    final session = response['session'];
    final token = session is Map<String, dynamic> ? session['token'] : null;
    if (token is String && token.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_tokenPrefKeyPrefix$accountKey', token);
    }
  }
}
