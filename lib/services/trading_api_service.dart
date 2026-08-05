import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'ai_service.dart';
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
}
