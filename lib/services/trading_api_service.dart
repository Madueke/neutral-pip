import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'ai_service.dart';
import 'auth_service.dart';
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
    // Keep the auth service in sync (session state + backend URL) so every
    // request below can attach the Bearer token.
    await AuthService.instance.init();
  }

  Future<void> saveSettings({required String tradingBackendUrl}) async {
    _tradingBackendUrl = tradingBackendUrl;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('trading_backend_url', tradingBackendUrl);
    await AuthService.instance.reloadBackendUrl();
  }

  /// Headers for authenticated requests: the session token from secure
  /// storage as `Authorization: Bearer` (added only when a session exists).
  /// The backend resolves the token to the user server-side; the app never
  /// sends a raw user_id.
  Map<String, String> get _authHeaders => AuthService.instance.authHeaders;

  /// Run the full backend analysis pipeline for a symbol/timeframe.
  /// Backend endpoint: POST /analyze (strategy + backtest + live chart +
  /// account state, with Claude reasoning). Falls back to a stub only when
  /// no backend is configured.
  ///
  /// TRADING MODE: never add tap-based execution here.
  Future<Map<String, dynamic>> analyze(
    String symbol,
    String timeframe,
  ) async {
    if (!isConfigured) {
      return {
        'status': 'stub',
        'symbol': symbol,
        'timeframe': timeframe,
        'summary': 'Configure a trading backend to run the analysis pipeline.',
      };
    }
    try {
      final response = await http
          .post(
            Uri.parse('$tradingBackendUrl/analyze'),
            headers: _authHeaders,
            body: jsonEncode({
              'symbol': symbol,
              'timeframe': timeframe,
            }),
          )
          .timeout(const Duration(minutes: 2));
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data is Map<String, dynamic>) {
        return data;
      }
      return {
        'status': 'error',
        'message': data is Map<String, dynamic> && data['error'] is String
            ? data['error'] as String
            : 'Backend returned HTTP ${response.statusCode}',
      };
    } catch (e) {
      return {'status': 'error', 'message': 'Could not reach backend: $e'};
    }
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

      // Get or create a session_id for memory persistence
      final sessionId = await _getOrCreateSessionId();

      try {
        final response = await http
            .post(
              Uri.parse('$tradingBackendUrl/chat'),
              // The backend resolves identity from the session token and
              // serves chat through its own Hermes instance, so no user
              // AI key/model headers are forwarded.
              headers: _authHeaders, // includes Authorization: Bearer
              body: jsonEncode({
                'message': message,
                'history': history,
                'attachments': _attachmentMetadata(attachments),
                if (chartUrl != null && chartUrl.isNotEmpty)
                  'chart_url': chartUrl,
                'session_id': sessionId,
              }),
            )
            .timeout(const Duration(minutes: 5));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data is Map<String, dynamic> &&
              data['reply'] is String &&
              (data['reply'] as String).trim().isNotEmpty) {
            // Optionally persist session_id from backend response
            if (data['session_id'] is String) {
              await _persistSessionId(data['session_id'] as String);
            }
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

  /// Get or create a persistent session_id for chat memory.
  Future<String> _getOrCreateSessionId() async {
    final prefs = await SharedPreferences.getInstance();
    var sessionId = prefs.getString('chat_session_id');
    if (sessionId == null || sessionId.isEmpty) {
      sessionId = 'chat_${DateTime.now().millisecondsSinceEpoch}_${_randomSuffix()}';
      await prefs.setString('chat_session_id', sessionId);
    }
    return sessionId;
  }

  /// Persist session_id returned by backend (if different).
  Future<void> _persistSessionId(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('chat_session_id', sessionId);
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

  /// Fetch the per-user trading journal. Backend endpoint: GET /journal.
  ///
  /// TRADING MODE: never add tap-based execution here.
  Future<Map<String, dynamic>> getJournal() async {
    if (!isConfigured) {
      return {'status': 'stub', 'entries': <Map<String, dynamic>>[]};
    }
    try {
      final response = await http
          .get(
            Uri.parse('$tradingBackendUrl/journal'),
            headers: _authHeaders,
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'status': 'ok',
          'entries': data is List ? data : <Map<String, dynamic>>[],
        };
      }
    } catch (_) {
      // Fall through to the empty stub below.
    }
    return {'status': 'stub', 'entries': <Map<String, dynamic>>[]};
  }

  /// Fetch current risk status. Backend endpoint: GET /risk-status.
  ///
  /// TRADING MODE: never add tap-based execution here.
  Future<Map<String, dynamic>> getRiskStatus() async {
    if (!isConfigured) {
      return {'status': 'stub', 'riskLevel': 'unknown'};
    }
    try {
      final response = await http
          .get(
            Uri.parse('$tradingBackendUrl/risk-status'),
            headers: _authHeaders,
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) return data;
      }
    } catch (_) {
      // Fall through to the stub below.
    }
    return {'status': 'stub', 'riskLevel': 'unknown'};
  }

  // ---------------------------------------------------------------------------
  // Live market data
  //
  //   GET /quote  latest price, indicator snapshot and a short sparkline
  //   GET /chart  OHLC candles for chart rendering
  //
  // Both hit the backend's cached public market-data layer (Yahoo + Binance
  // fallback); the app never talks to upstream chart APIs directly.
  // ---------------------------------------------------------------------------

  /// Latest quote + indicators for a symbol. Backend endpoint:
  /// GET /quote?symbol=&timeframe=. Returns
  /// { status: 'ok', symbol, last_close, change_percent, rsi_14, ema20,
  ///   ema50, macd, macd_histogram, atr_14, spark: [[o,h,l,c], ...], at } or
  /// { status: 'error', message } when no backend is configured.
  ///
  /// TRADING MODE: never add tap-based execution here.
  Future<Map<String, dynamic>> getQuote(
    String symbol, {
    String timeframe = 'M15',
  }) async {
    if (!isConfigured) {
      return {'status': 'error', 'message': 'Trading backend not configured'};
    }
    try {
      final response = await http
          .get(
            Uri.parse('$tradingBackendUrl/quote').replace(
              queryParameters: {'symbol': symbol, 'timeframe': timeframe},
            ),
          )
          .timeout(const Duration(seconds: 10));
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data is Map<String, dynamic>) {
        return data;
      }
      return {
        'status': 'error',
        'message': data is Map<String, dynamic> && data['error'] is String
            ? data['error'] as String
            : 'Backend returned HTTP ${response.statusCode}',
      };
    } catch (e) {
      return {'status': 'error', 'message': 'Could not reach backend: $e'};
    }
  }

  /// OHLC candles for a symbol/timeframe. Backend endpoint:
  /// GET /chart?symbol=&timeframe=&limit=. Returns
  /// { status: 'ok', symbol, timeframe, source, candles: [...] }.
  ///
  /// TRADING MODE: never add tap-based execution here.
  Future<Map<String, dynamic>> getChart(
    String symbol, {
    String timeframe = 'M15',
    int limit = 120,
  }) async {
    if (!isConfigured) {
      return {'status': 'error', 'message': 'Trading backend not configured'};
    }
    try {
      final response = await http
          .get(
            Uri.parse('$tradingBackendUrl/chart').replace(
              queryParameters: {
                'symbol': symbol,
                'timeframe': timeframe,
                'limit': '$limit',
              },
            ),
          )
          .timeout(const Duration(seconds: 10));
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data is Map<String, dynamic>) {
        return data;
      }
      return {
        'status': 'error',
        'message': data is Map<String, dynamic> && data['error'] is String
            ? data['error'] as String
            : 'Backend returned HTTP ${response.statusCode}',
      };
    } catch (e) {
      return {'status': 'error', 'message': 'Could not reach backend: $e'};
    }
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
  // Strategy training & auto-execute settings
  //
  //   POST   /strategy        save a versioned, encrypted strategy profile
  //   GET    /strategy        current profile + latest backtest result
  //   POST   /backtest        re-run the backtest explicitly
  //   GET    /settings        auto_execute flag + risk limits
  //   PATCH  /settings        update auto_execute
  //
  // The source of truth for strategy data is the backend; nothing sensitive
  // is persisted client-side beyond what this screen needs to render.
  // ---------------------------------------------------------------------------

  /// Fetch the current strategy profile + latest backtest result.
  /// Returns { status: 'ok', profile, version, backtest } when found,
  /// { status: 'not_found' } when the user has no profile yet, and
  /// { status: 'error', message } on failures.
  ///
  /// TRADING MODE: never add tap-based execution here.
  Future<Map<String, dynamic>> getStrategy() async {
    if (!isConfigured) {
      return {'status': 'error', 'message': 'Trading backend not configured'};
    }
    try {
      final response = await http
          .get(
            Uri.parse('$tradingBackendUrl/strategy'),
            headers: _authHeaders,
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) return data;
      }
      if (response.statusCode == 404) return {'status': 'not_found'};
    } catch (e) {
      return {'status': 'error', 'message': 'Could not reach backend: $e'};
    }
    return {'status': 'error', 'message': 'Unexpected backend response'};
  }

  /// Save (a new version of) the strategy profile. Backend endpoint:
  /// POST /strategy. The backend re-runs the backtest automatically.
  ///
  /// TRADING MODE: never add tap-based execution here.
  Future<Map<String, dynamic>> saveStrategy(
    Map<String, dynamic> profile,
  ) async {
    if (!isConfigured) {
      return {'status': 'error', 'message': 'Trading backend not configured'};
    }
    try {
      final response = await http
          .post(
            Uri.parse('$tradingBackendUrl/strategy'),
            headers: _authHeaders,
            body: jsonEncode({...profile}),
          )
          .timeout(const Duration(minutes: 2));
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data is Map<String, dynamic>) {
        return data;
      }
      return {
        'status': 'error',
        'message': data is Map<String, dynamic> && data['error'] is String
            ? data['error'] as String
            : 'Backend returned HTTP ${response.statusCode}',
      };
    } catch (e) {
      return {'status': 'error', 'message': 'Could not reach backend: $e'};
    }
  }

  /// Explicitly re-run the backtest. Backend endpoint: POST /backtest.
  ///
  /// TRADING MODE: never add tap-based execution here.
  Future<Map<String, dynamic>> runBacktest() async {
    if (!isConfigured) {
      return {'status': 'error', 'message': 'Trading backend not configured'};
    }
    try {
      final response = await http
          .post(
            Uri.parse('$tradingBackendUrl/backtest'),
            headers: _authHeaders,
          )
          .timeout(const Duration(minutes: 2));
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data is Map<String, dynamic>) {
        return data;
      }
      return {'status': 'error', 'message': 'Backend returned HTTP ${response.statusCode}'};
    } catch (e) {
      return {'status': 'error', 'message': 'Could not reach backend: $e'};
    }
  }

  /// Current auto-execute flag + risk limits. Backend endpoint:
  /// GET /settings. Returns { auto_execute, risk_limits }.
  ///
  /// TRADING MODE: never add tap-based execution here.
  Future<Map<String, dynamic>> getSettings() async {
    if (!isConfigured) {
      return {'status': 'error', 'auto_execute': false, 'risk_limits': null};
    }
    try {
      final response = await http
          .get(
            Uri.parse('$tradingBackendUrl/settings'),
            headers: _authHeaders,
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) return data;
      }
    } catch (_) {
      // Fall through to the safe default below.
    }
    return {'status': 'error', 'auto_execute': false, 'risk_limits': null};
  }

  /// Update the auto-execute flag. Backend endpoint: PATCH /settings.
  ///
  /// TRADING MODE: never add tap-based execution here. Execution happens
  /// server-side only, inside the user's configured risk limits.
  Future<Map<String, dynamic>> updateSettings({
    required bool autoExecute,
  }) async {
    if (!isConfigured) {
      return {'status': 'error', 'message': 'Trading backend not configured'};
    }
    try {
      final response = await http
          .patch(
            Uri.parse('$tradingBackendUrl/settings'),
            headers: _authHeaders,
            body: jsonEncode({'auto_execute': autoExecute}),
          )
          .timeout(const Duration(seconds: 15));
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data is Map<String, dynamic>) {
        return data;
      }
      return {
        'status': 'error',
        'message': data is Map<String, dynamic> && data['error'] is String
            ? data['error'] as String
            : 'Backend returned HTTP ${response.statusCode}',
      };
    } catch (e) {
      return {'status': 'error', 'message': 'Could not reach backend: $e'};
    }
  }

  // ---------------------------------------------------------------------------
  // Connect Trading Accounts
  //
  // Backend contract (live, see /home/ubuntu/meridian-backend):
  //   POST /connect-account      body: { account: 'tradingview'|'mt5',
  //                                     ...account-specific fields }
  //                              → 200 { status: 'ok', session: { token, user_id } }
  //   GET  /account-status       (Bearer) → 200 { user_id, accounts: { <key>: {
  //                                     status, detail? } } }   status in
  //                                     'connected'|'not_connected'|'error'
  //   POST /disconnect-account   body: { account: <key> }
  //                              → 200 { status: 'ok', disconnected: true }
  //
  // Identity comes from the Authorization: Bearer session token — the app
  // never sends a raw user_id. The `session.token` in the connect response
  // is a legacy per-account informational token, not the auth session.
  // Sensitive MT5 credentials are sent to the backend once and are never
  // stored locally (fields are cleared by the UI after success).
  //
  // TRADING MODE: never add tap-based execution here. Account connection is
  // a backend-only operation - the app never touches a broker terminal.
  // ---------------------------------------------------------------------------

  /// Resolved user id from the active auth session (informational; the
  /// backend derives identity from the Bearer token, not this value).
  Future<String?> getUserId() async => AuthService.instance.userId;

  /// Generate a short random suffix for session IDs.
  String _randomSuffix() {
    final s = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return s.substring(s.length - 6);
  }

  /// SharedPreferences keys holding the legacy per-account session token
  /// returned by the backend. These are the ONLY thing persisted after a
  /// connect; the raw credentials never touch disk.
  static const String _tokenPrefKeyPrefix = 'trading_account_token_';
  static const String tradingViewAccountKey = 'tradingview';
  static const String mt5AccountKey = 'mt5';

  /// Connect the TradingView watchlist (no login): posts the selected
  /// symbols and timeframes. Backend endpoint: POST /connect-account.
  ///
  /// TRADING MODE: never add tap-based execution here.
  Future<Map<String, dynamic>> connectTradingView({
    required List<String> symbols,
    required List<String> timeframes,
  }) async {
    final body = {
      'account': tradingViewAccountKey,
      'symbols': symbols,
      'timeframes': timeframes,
    };

    final response = await _postAccount('/connect-account', body);
    if (response != null) {
      if (response['status'] == 'ok') {
        await _persistSession(tradingViewAccountKey, response);
      }
      return response;
    }
    return {
      'status': 'error',
      'message': 'Trading backend not configured',
    };
  }

  /// Connect a real MT5 account. Credentials are posted to the backend once
  /// and are never persisted client-side; only the returned session token is
  /// kept. Backend endpoint: POST /connect-account.
  ///
  /// TRADING MODE: never add tap-based execution here.
  Future<Map<String, dynamic>> connectMt5({
    required String accountNumber,
    required String password,
    required String brokerServer,
  }) async {
    final body = {
      'account': mt5AccountKey,
      'account_number': accountNumber.trim(),
      'password': password,
      'broker_server': brokerServer.trim(),
    };

    final response = await _postAccount('/connect-account', body);
    if (response != null) {
      if (response['status'] == 'ok') {
        await _persistSession(mt5AccountKey, response);
      }
      return response;
    }
    return {
      'status': 'error',
      'message': 'Trading backend not configured',
    };
  }

  /// Fetch connection status for every known account. Backend endpoint:
  /// GET /account-status (Bearer).
  ///
  /// TRADING MODE: never add tap-based execution here.
  Future<Map<String, dynamic>> getAccountStatus() async {
    if (!isConfigured) {
      return {
        'accounts': {
          tradingViewAccountKey: {'status': 'not_connected'},
          mt5AccountKey: {'status': 'not_connected'},
        },
      };
    }
    try {
      final response = await http
          .get(
            Uri.parse('$tradingBackendUrl/account-status'),
            headers: _authHeaders,
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) return data;
      }
      if (response.statusCode == 401) {
        return {
          'auth_error': true,
          'accounts': {
            tradingViewAccountKey: {'status': 'not_connected'},
            mt5AccountKey: {'status': 'not_connected'},
          },
        };
      }
    } catch (_) {
      // Fall through to the not-connected defaults so the screen renders.
    }
    return {
      'accounts': {
        tradingViewAccountKey: {'status': 'not_connected'},
        mt5AccountKey: {'status': 'not_connected'},
      },
    };
  }

  /// Disconnect an account. Backend endpoint: POST /disconnect-account.
  ///
  /// TRADING MODE: never add tap-based execution here.
  Future<Map<String, dynamic>> disconnectAccount(String accountKey) async {
    final body = {
      'account': accountKey,
    };

    final response = await _postAccount('/disconnect-account', body);
    // Clear the local per-account token regardless of outcome.
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_tokenPrefKeyPrefix$accountKey');

    if (response != null) return response;
    return {'status': 'ok', 'disconnected': true, 'account': accountKey};
  }

  /// Shared POST for connect/disconnect; returns the decoded 200 body, or a
  /// structured error / null when the backend is unconfigured or unreachable.
  Future<Map<String, dynamic>?> _postAccount(
    String path,
    Map<String, dynamic> body,
  ) async {
    if (!isConfigured) return null;
    try {
      final response = await http
          .post(
            Uri.parse('$tradingBackendUrl$path'),
            headers: _authHeaders,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) return data;
      }
      return {
        'status': 'error',
        'message':
            response.statusCode == 401
                ? 'Session expired. Sign in again.'
                : 'Backend returned HTTP ${response.statusCode}.',
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

  // ---------------------------------------------------------------------------
  // Agent Setup: train from uploads + configuration
  //
  //   POST   /train                 multipart (PDFs + images) → PROPOSED
  //                                 strategy-profile update (never saved here)
  //   GET    /config?session_id=    current strategy profile, risk rules,
  //                                 alarms and skills (user_taught vs auto)
  //   POST   /config/skill-active   toggle a skill on/off
  //   POST   /config/alarm-active   toggle an alarm on/off
  //
  // Identity always comes from the Bearer session token; the backend derives
  // the user server-side. Skills are scoped by the chat session_id so they
  // match what the agent chat sees.
  // ---------------------------------------------------------------------------

  /// The persistent chat session_id used for memory + skills, shared with
  /// /chat so the config summary shows the same skills the agent sees.
  Future<String> getOrCreateSessionId() => _getOrCreateSessionId();

  /// Upload PDF strategy docs and/or chart images and get a PROPOSED
  /// strategy-profile update back. The backend never saves this — the caller
  /// decides to Confirm (via saveStrategy), Edit, or Discard.
  ///
  /// TRADING MODE: never add tap-based execution here.
  Future<Map<String, dynamic>> trainFromUploads(
    List<String> filePaths,
  ) async {
    if (!isConfigured) {
      return {'status': 'error', 'message': 'Trading backend not configured'};
    }
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$tradingBackendUrl/train'),
      );
      request.headers.addAll(_authHeaders);
      for (final path in filePaths) {
        request.files.add(await http.MultipartFile.fromPath('files', path));
      }
      final streamed =
          await request.send().timeout(const Duration(minutes: 3));
      final response = await http.Response.fromStream(streamed);
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data is Map<String, dynamic>) {
        return data;
      }
      return {
        'status': 'error',
        'message': data is Map<String, dynamic> && data['error'] is String
            ? data['error'] as String
            : 'Backend returned HTTP ${response.statusCode}',
      };
    } catch (e) {
      return {'status': 'error', 'message': 'Could not reach backend: $e'};
    }
  }

  /// Current agent configuration: strategy profile, risk rules, alarms, and
  /// skills split into user-taught and auto-extracted.
  ///
  /// TRADING MODE: never add tap-based execution here.
  Future<Map<String, dynamic>> getConfig({required String sessionId}) async {
    if (!isConfigured) {
      return {'status': 'error', 'message': 'Trading backend not configured'};
    }
    try {
      final response = await http
          .get(
            Uri.parse('$tradingBackendUrl/config').replace(
              queryParameters: {'session_id': sessionId},
            ),
            headers: _authHeaders,
          )
          .timeout(const Duration(seconds: 15));
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data is Map<String, dynamic>) {
        return data;
      }
      return {
        'status': 'error',
        'message': data is Map<String, dynamic> && data['error'] is String
            ? data['error'] as String
            : 'Backend returned HTTP ${response.statusCode}',
      };
    } catch (e) {
      return {'status': 'error', 'message': 'Could not reach backend: $e'};
    }
  }

  /// Toggle a skill's active state (it is kept, just not used in context).
  Future<Map<String, dynamic>> setSkillActive({
    required String sessionId,
    required String name,
    required bool active,
  }) {
    return _postConfig(
      '/config/skill-active',
      {'session_id': sessionId, 'name': name, 'active': active},
    );
  }

  /// Toggle an alarm's active state.
  Future<Map<String, dynamic>> setAlarmActive({
    required String id,
    required bool active,
  }) {
    return _postConfig('/config/alarm-active', {'id': id, 'active': active});
  }

  /// Current agent activation state: agent_active, activated_at, and whether
  /// a strategy profile / connected accounts exist yet.
  ///
  /// TRADING MODE: never add tap-based execution here.
  Future<Map<String, dynamic>> getAgentStatus() async {
    if (!isConfigured) {
      return {'status': 'error', 'message': 'Trading backend not configured'};
    }
    try {
      final response = await http
          .get(
            Uri.parse('$tradingBackendUrl/agent/status'),
            headers: _authHeaders,
          )
          .timeout(const Duration(seconds: 15));
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data is Map<String, dynamic>) {
        return data;
      }
      return {
        'status': 'error',
        'message': data is Map<String, dynamic> && data['error'] is String
            ? data['error'] as String
            : 'Backend returned HTTP ${response.statusCode}',
      };
    } catch (e) {
      return {'status': 'error', 'message': 'Could not reach backend: $e'};
    }
  }

  /// Activate the agent: creates the default strategy profile and risk rules
  /// on first activation and flips the flag on. Idempotent on re-activation.
  Future<Map<String, dynamic>> activateAgent() {
    return _postConfig('/agent/activate', {});
  }

  /// Pause the agent (reversible). Never deletes memory, strategy or history.
  Future<Map<String, dynamic>> deactivateAgent() {
    return _postConfig('/agent/deactivate', {});
  }

  Future<Map<String, dynamic>> _postConfig(
    String path,
    Map<String, dynamic> body,
  ) async {
    if (!isConfigured) {
      return {'status': 'error', 'message': 'Trading backend not configured'};
    }
    try {
      final response = await http
          .post(
            Uri.parse('$tradingBackendUrl$path'),
            headers: _authHeaders,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data is Map<String, dynamic>) {
        return data;
      }
      return {
        'status': 'error',
        'message': data is Map<String, dynamic> && data['error'] is String
            ? data['error'] as String
            : 'Backend returned HTTP ${response.statusCode}',
      };
    } catch (e) {
      return {'status': 'error', 'message': 'Could not reach backend: $e'};
    }
  }
}
