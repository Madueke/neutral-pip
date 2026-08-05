import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'action_handler.dart';
import 'ai_service.dart';

class TelegramService {
  final ActionHandler _actionHandler;
  final AiService _aiService;
  
  String _botToken = '';
  bool _isEnabled = false;
  int _lastUpdateId = 0;
  bool _isPolling = false;
  Timer? _pollingTimer;

  TelegramService(this._actionHandler, this._aiService);

  String get botToken => _botToken;
  bool get isEnabled => _isEnabled;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _botToken = prefs.getString('telegram_bot_token') ?? '';
    _isEnabled = prefs.getBool('telegram_enabled') ?? false;

    if (_isEnabled && _botToken.isNotEmpty) {
      startPolling();
    }
  }

  Future<void> saveSettings({required String botToken, required bool isEnabled}) async {
    _botToken = botToken;
    _isEnabled = isEnabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('telegram_bot_token', _botToken);
    await prefs.setBool('telegram_enabled', _isEnabled);

    if (_isEnabled && _botToken.isNotEmpty) {
      startPolling();
    } else {
      stopPolling();
    }
  }

  void startPolling() {
    if (_isPolling) return;
    _isPolling = true;
    _pollUpdates();
  }

  void stopPolling() {
    _isPolling = false;
    _pollingTimer?.cancel();
  }

  Future<void> _pollUpdates() async {
    if (!_isPolling || _botToken.isEmpty) return;

    try {
      final url = Uri.parse('https://api.telegram.org/bot$_botToken/getUpdates');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'offset': _lastUpdateId + 1,
          'timeout': 30, // Long polling timeout
          'allowed_updates': ['message'],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['ok'] == true) {
          final results = data['result'] as List;
          final seenChatIds = <String>[];
          for (final update in results) {
            _lastUpdateId = update['update_id'];
            if (update['message'] != null && update['message']['text'] != null) {
              final text = update['message']['text'];
              final chatId = update['message']['chat']['id'];
              seenChatIds.add(chatId.toString());

              // Process message asynchronously so we don't block the polling loop
              _handleIncomingMessage(chatId.toString(), text);
            }
          }
          if (seenChatIds.isNotEmpty) {
            await _rememberChatIds(seenChatIds);
          }
        }
      }
    } catch (e) {
      print('Telegram polling error: $e');
    }

    // Continue polling
    if (_isPolling) {
      _pollingTimer = Timer(const Duration(seconds: 1), _pollUpdates);
    }
  }

  Future<void> _handleIncomingMessage(String chatId, String text) async {
    // Acknowledge receipt
    await _sendMessage(chatId, '🤖 Received: "$text". Working on it...');

    try {
      // 1. Send text to AI
      final aiResponse = await _aiService.sendMessage(text);
      
      // 2. Parse the action
      final action = _aiService.parseAction(aiResponse);

      if (action != null) {
        // 3. Execute the action
        final result = await _actionHandler.execute(
          action,
          aiService: _aiService,
          onProgress: (msg) {
            // Send progress updates back to telegram
            _sendMessage(chatId, '⏳ $msg');
          },
        );
        await _sendMessage(chatId, '✅ ${result.details ?? "Done"}');
      } else {
        // It's a plain text response
        await _sendMessage(chatId, '💬 $aiResponse');
      }
    } catch (e) {
      await _sendMessage(chatId, '❌ Error: $e');
    }
  }

  Future<void> _sendMessage(String chatId, String text) async {
    if (_botToken.isEmpty) return;
    try {
      final url = Uri.parse('https://api.telegram.org/bot$_botToken/sendMessage');
      await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'chat_id': chatId,
          'text': text,
        }),
      );
    } catch (e) {
      print('Failed to send telegram message: $e');
    }
  }

  /// Chat IDs that have previously messaged the bot, persisted to
  /// SharedPreferences as they arrive from getUpdates polling.
  ///
  /// TRADING MODE: never add tap-based execution here.
  /// Used as the destination list for scheduled analysis pushes; it only
  /// stores identifiers and never performs any device action.
  Future<List<String>> getStoredChatIds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('telegram_chat_ids') ?? const [];
  }

  /// Persist any newly-seen chat IDs from the polling loop.
  ///
  /// TRADING MODE: never add tap-based execution here.
  Future<void> _rememberChatIds(Iterable<String> chatIds) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList('telegram_chat_ids') ?? const [];
    final updated = [...existing];
    var changed = false;
    for (final id in chatIds) {
      if (!updated.contains(id)) {
        updated.add(id);
        changed = true;
      }
    }
    if (changed) {
      await prefs.setStringList('telegram_chat_ids', updated);
    }
  }

  /// Send a scheduled analysis push to one chat. Pure outbound push, NOT a
  /// reply to any user message, formatted so users can tell it apart from
  /// live chat replies.
  ///
  /// TRADING MODE: never add tap-based execution here.
  /// This only sends a Telegram message; it never performs device actions.
  Future<void> sendScheduledAnalysis(
    String chatId,
    String symbol,
    String timeframe,
    String analysis,
    String confidence,
    String strategyMatch,
  ) async {
    if (_botToken.isEmpty) return;
    const separator = '──────────────────';
    final text =
        '📊 SCHEDULED ANALYSIS\n'
        '$separator\n'
        'Pair: ${_escapeHtml(symbol)} | ${_escapeHtml(timeframe)}\n'
        'Strategy match: ${_escapeHtml(strategyMatch)}\n'
        'Confidence: ${_escapeHtml(confidence)}\n'
        '\n'
        '${_escapeHtml(analysis)}\n'
        '$separator\n'
        '🤖 Meridian Trading Co-Pilot';
    await _sendHtml(chatId, text);
  }

  /// Send the same scheduled analysis to every chat that has previously
  /// messaged the bot, in a loop over getStoredChatIds().
  ///
  /// TRADING MODE: never add tap-based execution here.
  Future<void> sendScheduledAnalysisBroadcast(
    String symbol,
    String timeframe,
    String analysis,
    String confidence,
    String strategyMatch,
  ) async {
    final chatIds = await getStoredChatIds();
    for (final chatId in chatIds) {
      await sendScheduledAnalysis(
        chatId,
        symbol,
        timeframe,
        analysis,
        confidence,
        strategyMatch,
      );
    }
  }

  /// Escape HTML special characters so Telegram's parse_mode HTML never
  /// rejects the push when a value contains &, <, or >.
  ///
  /// TRADING MODE: never add tap-based execution here.
  String _escapeHtml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  /// POST a pre-formatted message with parse_mode HTML so emoji and box
  /// drawing characters render cleanly.
  ///
  /// TRADING MODE: never add tap-based execution here.
  Future<void> _sendHtml(String chatId, String text) async {
    if (_botToken.isEmpty) return;
    try {
      final url = Uri.parse(
        'https://api.telegram.org/bot$_botToken/sendMessage',
      );
      await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'chat_id': chatId,
          'text': text,
          'parse_mode': 'HTML',
        }),
      );
    } catch (e) {
      print('Failed to send telegram message: $e');
    }
  }

  void dispose() {
    stopPolling();
  }
}
