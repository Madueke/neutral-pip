import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_message.dart';
import '../models/home_quick_action.dart';
import '../config/theme.dart';
import '../services/ai_service.dart';
import '../services/action_handler.dart';
import '../services/trading_api_service.dart';
import '../services/voice_service.dart';
import '../widgets/guide_dialog.dart';
import '../widgets/logo_loader.dart';
import '../widgets/message_bubble.dart';
import '../widgets/trading_avatar.dart';
import '../services/telegram_service.dart';
import '../services/chat_history_service.dart';
import '../services/notification_service.dart';
import 'settings_screen.dart';
import 'task_history_screen.dart';
import 'journal_screen.dart';
import 'risk_dashboard_screen.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import '../main.dart';
import '../config/feature_flags.dart';

/// Attachment sources available in Trading Mode.
enum AttachmentSource { gallery, camera, file, screenshot, chartUrl }

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.aiService,
    this.actionHandler,
    this.voiceService,
    this.notificationService,
    this.telegramService,
    this.tradingApiService,
    this.tradingModeEnabled,
    this.onOpenSettings,
  });

  /// Optional injected services — when provided (e.g. by [AppShell]) the
  /// same instances are shared across tabs so settings propagate.
  final AiService? aiService;
  final ActionHandler? actionHandler;
  final VoiceService? voiceService;
  final NotificationService? notificationService;
  final TelegramService? telegramService;
  final TradingApiService? tradingApiService;
  final bool? tradingModeEnabled;

  /// When set, the Settings action routes to this callback instead of
  /// pushing a fresh SettingsScreen (used by the tab shell).
  final VoidCallback? onOpenSettings;

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _textFocusNode = FocusNode();
  late final AiService _aiService;
  late final ActionHandler _actionHandler;
  late final VoiceService _voiceService;
  late final NotificationService _notificationService;
  late final TelegramService _telegramService;

  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _isListening = false;

  // Custom switch state: 'chat' or 'agent'
  String _mode = 'chat';

  // Top-level execution mode: false = Phone Control, true = Trading Mode.
  bool _tradingModeEnabled = false;
  late final TradingApiService _tradingApiService;

  // Trading Mode attachments (image_picker / file_picker)
  final ImagePicker _picker = ImagePicker();
  final List<ChatAttachment> _pendingAttachments = [];

  // Chat Session state tracking
  String _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
  String _sessionTitle = '';

  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;
  Timer? _overlayHistoryTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _aiService = widget.aiService ?? AiService();
    _actionHandler = widget.actionHandler ?? ActionHandler();
    _voiceService = widget.voiceService ?? VoiceService();
    _notificationService = widget.notificationService ?? NotificationService();
    _telegramService =
        widget.telegramService ?? TelegramService(_actionHandler, _aiService);
    _tradingApiService =
        widget.tradingApiService ?? TradingApiService(_aiService);
    _tradingModeEnabled = widget.tradingModeEnabled ?? false;
    _initServices();
    _startOverlayHistorySync();
    // Register as the handler for overlay bubble tasks
    onOverlayTask = (task) => _sendMessage(task);
  }

  /// Entry point for dashboard quick actions (AppShell tab routing).
  void runQuickAction(HomeQuickAction action) {
    switch (action) {
      case HomeQuickAction.captureChart:
        if (_tradingModeEnabled) {
          _captureChartScreenshot();
        } else {
          _showAttachmentPicker();
        }
      case HomeQuickAction.pasteUrl:
        _promptChartUrl();
      case HomeQuickAction.askAi:
        _focusInput();
      case HomeQuickAction.upload:
        _showAttachmentPicker();
    }
  }

  void _focusInput() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      FocusScope.of(context).requestFocus(_textFocusNode);
    });
  }

  Future<void> _initServices() async {
    await _aiService.init();
    await _notificationService.requestPermission();
    await _voiceService.init();
    await _telegramService.init();
    await _tradingApiService.init();
    final prefs = await SharedPreferences.getInstance();
    _tradingModeEnabled = prefs.getBool('trading_mode_enabled') ?? false;
    await _actionHandler.shizuku.checkAvailability();

    if (mounted) {
      setState(() {});
    }
  }

  /// Opens Settings from a guide dialog (model setup, permissions).
  Future<void> _openSettingsFromGuide() async {
    if (!mounted) return;
    final onOpenSettings = widget.onOpenSettings;
    if (onOpenSettings != null) {
      onOpenSettings();
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          aiService: _aiService,
          shizukuService: _actionHandler.shizuku,
          screenAutomationService: _actionHandler.screenAutomation,
          telegramService: _telegramService,
          tradingApiService: _tradingApiService,
          tradingModeEnabled: _tradingModeEnabled,
        ),
      ),
    );
    await _actionHandler.shizuku.checkAvailability();
    if (mounted) setState(() {});
  }

  Future<void> _saveSession() async {
    if (_messages.isEmpty) return;
    // Set first user message as session title if not set
    if (_sessionTitle.isEmpty) {
      final firstUserMsg = _messages.firstWhere(
        (m) => m.isUser,
        orElse: () => ChatMessage(role: 'user', content: 'New Chat'),
      );
      _sessionTitle = firstUserMsg.content.length > 28
          ? '${firstUserMsg.content.substring(0, 25)}...'
          : firstUserMsg.content;
    }

    final session = ChatSession(
      id: _sessionId,
      title: _sessionTitle,
      timestamp: DateTime.now(),
      messages: _messages.map((m) => m.toJson()).toList(),
    );

    await ChatHistoryService.saveSession(session);
  }

  Future<void> _sendMessage(
    String text, {
    List<Map<String, dynamic>> attachments = const [],
  }) async {
    if (text.trim().isEmpty) return;

    // Require an AI model before chatting. Trading Mode with a backend
    // configured uses the trading API directly and does not need one.
    final needsAiModel = !(_tradingModeEnabled && _tradingApiService.isConfigured);
    if (needsAiModel && !_aiService.hasValidConfiguration) {
      await showModelSetupGuide(context, openSettings: _openSettingsFromGuide);
      return;
    }

    final userMessage = ChatMessage(
      role: 'user',
      content: text.trim(),
      attachments: attachments.map((a) => ChatAttachment.fromJson(a)).toList(),
    );
    _pendingAttachments.clear();
    setState(() {
      _messages.add(userMessage);
      _isLoading = true;
    });
    _updateOverlayState();
    _textController.clear();
    _scrollToBottom();
    await _saveSession();

    // Add empty placeholder assistant message for streaming
    final assistantMessage = ChatMessage(role: 'assistant', content: '');
    setState(() {
      _messages.add(assistantMessage);
    });
    final assistantIndex = _messages.length - 1;

    try {
      if (_tradingModeEnabled) {
        // TRADING MODE: never add tap-based execution here.
        // Commands route to the secure trading backend API instead of the
        // screen-automation agent - no on-device taps are ever performed.
        final history = _messages
            .where(
              (m) =>
                  (m.role == 'user' || m.role == 'assistant') &&
                  m.content.isNotEmpty,
            )
            .map((m) => {'role': m.role, 'content': m.content})
            .toList();
        // The current user message is the last non-empty entry (the
        // assistant placeholder that follows has empty content and is
        // filtered above). It is sent separately as `text` (plus
        // attachments), so drop it to avoid sending the turn twice.
        if (history.isNotEmpty) {
          history.removeLast();
        }
        final response = await _tradingApiService.chat(
          text.trim(),
          history,
          attachments: attachments,
        );
        if (mounted) {
          setState(() {
            _messages[assistantIndex] = ChatMessage(
              role: 'assistant',
              content: response,
            );
          });
        }
        await _saveSession();
        return;
      }

      final isAgent = _mode == 'agent';
      final stream = _aiService
          .sendMessageStream(text.trim(), isAgentMode: isAgent)
          .timeout(
            const Duration(seconds: 90),
            onTimeout: (sink) {
              sink.addError(
                TimeoutException(
                  'The model did not return visible text within 90 seconds.',
                ),
              );
              sink.close();
            },
          );
      String accumulated = '';

      await for (final chunk in stream) {
        accumulated += chunk;
        if (mounted) {
          setState(() {
            _messages[assistantIndex] = ChatMessage(
              role: 'assistant',
              content: accumulated,
            );
          });
          _scrollToBottom();
        }
      }
      await _saveSession();

      // Check if it's an action
      final action = _aiService.parseAction(accumulated);

      if (action != null) {
        // If it's an action, we remove the raw JSON message from display
        setState(() {
          _messages.removeAt(assistantIndex);
        });

        // Every action mutates the device, so it needs the accessibility
        // service. If it is off, guide the user instead of failing silently.
        final serviceRunning = await _actionHandler.screenAutomation
            .isServiceRunning();
        if (!serviceRunning) {
          if (mounted) {
            setState(() {
              _messages.add(
                ChatMessage(
                  role: 'assistant',
                  content:
                      'I need Screen Control permission to do that. Enable it '
                      'and I will run your request right away.',
                ),
              );
            });
            _scrollToBottom();
            await showAccessibilityGuide(
              context,
              _actionHandler.screenAutomation,
            );
          }
          await _saveSession();
          return;
        }

        await _showTaskProgressOverlay('Starting: ${text.trim()}');

        // Execute the action (pass aiService for multi-step tasks)
        final result = await _actionHandler.execute(
          action,
          aiService: _aiService,
          onProgress: (msg) {
            developer.log('Task progress: $msg', name: 'NeutralPip');
            _sendOverlayEvent('OVERLAY_PROGRESS', msg);
            if (mounted) {
              setState(() {
                _messages.add(
                  ChatMessage(role: 'assistant', content: '⏳ $msg'),
                );
              });
              _scrollToBottom();
            }
          },
        );

        setState(() {
          _messages.add(
            ChatMessage(
              role: 'assistant',
              content: result.success
                  ? (action.response.isNotEmpty
                        ? action.response
                        : (result.details ?? 'Done.'))
                  : (action.response.isNotEmpty
                        ? '${action.response}\n\n⚠️ ${result.details}'
                        : '⚠️ ${result.details}'),
              actionResult: result,
            ),
          );
        });
        _sendOverlayEvent(
          'OVERLAY_TASK_FINISHED',
          result.success
              ? (result.details ?? 'Task complete.')
              : 'Task failed: ${result.details ?? 'Unknown error'}',
        );
        if (action.action != 'execute_task') {
          await _notificationService.showTaskCompleteNotification(
            result.success ? 'Task Completed' : 'Task Failed',
            result.details ??
                (result.success
                    ? 'Agent finished its goal.'
                    : 'Agent could not complete the task.'),
          );
        }
        await _saveSession();
      } else {
        // Plain text response, we already rendered it, just speak it
        _voiceService.speak(accumulated);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          if (_messages.isNotEmpty && _messages.length > assistantIndex) {
            _messages.removeAt(assistantIndex);
          }
          _messages.add(
            ChatMessage(
              role: 'assistant',
              content: 'Error: ${e.toString().replaceFirst('Exception: ', '')}',
            ),
          );
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _scrollToBottom();
        _updateOverlayState();
      }
    }
  }

  Future<void> _showTaskProgressOverlay(String message) async {
    if (!FeatureFlags.floatingOverlayEnabled) return;
    if (!await FlutterOverlayWindow.isPermissionGranted()) return;

    // Never cover Neutral Pip itself. The lifecycle observer will create the
    // overlay after an automated action moves this app to the background.
    if (_appLifecycleState != AppLifecycleState.paused) return;

    if (!await FlutterOverlayWindow.isActive()) {
      await FlutterOverlayWindow.showOverlay(
        enableDrag: true,
        overlayTitle: 'Neutral Pip',
        overlayContent: 'Performing task...',
        flag: OverlayFlag.focusPointer,
        alignment: OverlayAlignment.centerRight,
        visibility: NotificationVisibility.visibilitySecret,
        positionGravity: PositionGravity.auto,
        startPosition: const OverlayPosition(0, 200),
        width: 56,
        height: 56,
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }

    // Keep the overlay minimized during automation. The user can still tap the
    // bubble to open the full conversation whenever they choose.
    _sendOverlayEvent('OVERLAY_TASK_STARTED', message);
  }

  void _sendOverlayEvent(String type, String message) {
    if (!FeatureFlags.floatingOverlayEnabled) return;
    final safeMessage = message.replaceAll('|', ' ');
    unawaited(
      FlutterOverlayWindow.shareData(
        '$type|$safeMessage',
      ).timeout(const Duration(seconds: 2)).catchError((Object _) {}),
    );
  }

  Future<void> _sendOverlayHistorySnapshot() async {
    if (!FeatureFlags.floatingOverlayEnabled) return;
    final history = base64Encode(
      utf8.encode(
        jsonEncode(_messages.map((message) => message.toJson()).toList()),
      ),
    );
    try {
      await FlutterOverlayWindow.shareData(
        'OVERLAY_HISTORY|$history',
      ).timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _toggleVoice() async {
    if (_isListening) {
      await _voiceService.stopListening();
      setState(() => _isListening = false);
      return;
    }

    final micStatus = await Permission.microphone.status;
    if (!micStatus.isGranted) {
      if (mounted) await showMicrophoneGuide(context);
      return;
    }

    setState(() => _isListening = true);

    await _voiceService.startListening(
      onResult: (text) {
        _sendMessage(text);
      },
      onDone: () {
        if (mounted) {
          setState(() => _isListening = false);
        }
      },
    );
  }

  void _startNewChat() {
    setState(() {
      _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
      _sessionTitle = '';
      _messages.clear();
      _aiService.clearHistory();
    });
  }

  void _loadChatSession(ChatSession session) {
    setState(() {
      _sessionId = session.id;
      _sessionTitle = session.title;
      _messages.clear();
      for (final m in session.messages) {
        _messages.add(ChatMessage.fromJson(m));
      }

      _aiService.clearHistory();
      for (final m in _messages) {
        if (m.actionResult != null) continue;
        _aiService.addHistoryMessage(m.role, m.content);
      }
    });
    _scrollToBottom();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _overlayHistoryTimer?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    _textFocusNode.dispose();
    _voiceService.dispose();
    _telegramService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() {
      _appLifecycleState = state;
    });
    if (state == AppLifecycleState.resumed) {
      _startOverlayHistorySync();
      unawaited(_handleAppForegrounded());
    } else {
      _overlayHistoryTimer?.cancel();
      _updateOverlayState();
    }
  }

  void _startOverlayHistorySync() {
    _overlayHistoryTimer?.cancel();
    if (!FeatureFlags.floatingOverlayEnabled) return;
    unawaited(_importOverlayChatHistory());
    _overlayHistoryTimer = Timer.periodic(const Duration(milliseconds: 500), (
      _,
    ) {
      if (_appLifecycleState == AppLifecycleState.resumed) {
        unawaited(_importOverlayChatHistory());
      }
    });
  }

  Future<void> _handleAppForegrounded() async {
    await _updateOverlayState();
    await _importOverlayChatHistory();
  }

  Future<void> _importOverlayChatHistory() async {
    if (!FeatureFlags.floatingOverlayEnabled) return;
    if (_importingOverlayHistory) return;
    _importingOverlayHistory = true;
    try {
      final handoff = await ChatHistoryService.consumeOverlayMessages();
      if (!mounted || handoff.isEmpty) return;

      final imported = handoff.map(ChatMessage.fromJson).toList();
      for (final message in imported) {
        if (message.actionResult == null) {
          _aiService.addHistoryMessage(message.role, message.content);
        }
      }
      setState(() {
        _messages.addAll(imported);
      });
      _scrollToBottom();
      await _saveSession();
    } finally {
      _importingOverlayHistory = false;
    }
  }

  int _overlayUpdateGeneration = 0;
  bool _importingOverlayHistory = false;

  Future<void> _updateOverlayState() async {
    if (!FeatureFlags.floatingOverlayEnabled) return;
    final generation = ++_overlayUpdateGeneration;
    final isBackground = _appLifecycleState == AppLifecycleState.paused;
    final shouldBeActive = isBackground;

    bool granted = await FlutterOverlayWindow.isPermissionGranted();
    if (!granted || generation != _overlayUpdateGeneration) return;

    bool active = await FlutterOverlayWindow.isActive();
    if (generation != _overlayUpdateGeneration) return;
    if (shouldBeActive && !active) {
      await Future.delayed(const Duration(milliseconds: 200));
      if (generation != _overlayUpdateGeneration) return;
      if (_appLifecycleState != AppLifecycleState.paused) return;
      if (await FlutterOverlayWindow.isActive()) return;
      await FlutterOverlayWindow.showOverlay(
        enableDrag: true,
        overlayTitle: "Neutral Pip",
        overlayContent: _isLoading
            ? "Performing task..."
            : "Floating Assistant",
        flag: OverlayFlag.focusPointer,
        alignment: OverlayAlignment.centerRight,
        visibility: NotificationVisibility.visibilitySecret,
        positionGravity: PositionGravity.auto,
        startPosition: const OverlayPosition(0, 200),
        width: 56,
        height: 56,
      );
      if (_isLoading && _appLifecycleState == AppLifecycleState.paused) {
        // Give the overlay isolate time to attach its listener, then send the
        // full active conversation. A second snapshot makes cold starts
        // reliable without duplicating messages because the overlay replaces
        // its list atomically.
        await Future<void>.delayed(const Duration(milliseconds: 250));
        await _sendOverlayHistorySnapshot();
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (_isLoading && _appLifecycleState == AppLifecycleState.paused) {
          await _sendOverlayHistorySnapshot();
        }
      }
    } else if (shouldBeActive && active && _isLoading) {
      await _sendOverlayHistorySnapshot();
    } else if (!shouldBeActive && active) {
      try {
        await FlutterOverlayWindow.shareData(
          'OVERLAY_RESET|',
        ).timeout(const Duration(milliseconds: 150));
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (generation != _overlayUpdateGeneration) return;
      if (_appLifecycleState == AppLifecycleState.paused) return;
      await FlutterOverlayWindow.closeOverlay();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const TradingAvatar(size: 32),
            const SizedBox(width: AppTokens.spaceSm),
            Text(
              'Neutral Pip',
              style: AppFonts.heading(
                size: 17,
                weight: FontWeight.w700,
                letterSpacing: -0.3,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu_rounded),
            tooltip: 'Menu',
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: 'New chat',
            onPressed: _isLoading ? null : _startNewChat,
          ),
          // Settings Action
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            onPressed: () async {
              final onOpenSettings = widget.onOpenSettings;
              if (onOpenSettings != null) {
                onOpenSettings();
                return;
              }
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(
                    aiService: _aiService,
                    shizukuService: _actionHandler.shizuku,
                    screenAutomationService: _actionHandler.screenAutomation,
                    telegramService: _telegramService,
                    tradingApiService: _tradingApiService,
                    tradingModeEnabled: _tradingModeEnabled,
                  ),
                ),
              );
              await _actionHandler.shizuku.checkAvailability();
              if (mounted) setState(() {});
            },
          ),
        ],
      ),
      drawer: _buildDrawer(context, isDark),
      body: Stack(
        children: [
          // Background mesh glows
          _buildBackgroundGlows(isDark),

          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
              child: Container(color: Colors.transparent),
            ),
          ),

          Column(
            children: [
              // Top-level mode selector (Phone Control / Trading Mode)
              _buildTradingModeSelector(isDark),

              // Persistent safety badge while Trading Mode is active
              if (_tradingModeEnabled) _buildTradingModeBadge(isDark),

              // Trading quick actions (Trading Mode only)
              if (_tradingModeEnabled) _buildTradingActionBar(),

              // Pill selector switcher
              _buildModeSelector(isDark),

              // API key warning banner
              if (!_aiService.isConfigured)
                Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.amber.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: AppColors.amber,
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'API not configured. Tap Settings to add details.',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SettingsScreen(
                                aiService: _aiService,
                                shizukuService: _actionHandler.shizuku,
                                screenAutomationService:
                                    _actionHandler.screenAutomation,
                                telegramService: _telegramService,
                                tradingApiService: _tradingApiService,
                                tradingModeEnabled: _tradingModeEnabled,
                              ),
                            ),
                          );
                          if (mounted) setState(() {});
                        },
                        child: const Text('Configure'),
                      ),
                    ],
                  ),
                ),

              // Chat content area
              Expanded(
                child: _messages.isEmpty
                    ? _buildEmptyState(isDark)
                    : ListView.builder(
                        controller: _scrollController,
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          return MessageBubble(message: _messages[index]);
                        },
                      ),
              ),

              // Think loading indicator
              if (_isLoading)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      const LogoLoader(
                        size: 14,
                        strokeWidth: 2,
                        showGlow: false,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Thinking...',
                        style: AppFonts.body(
                          size: 12,
                          weight: FontWeight.w500,
                          color: isDark
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondaryLight,
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: () {
                          _actionHandler.cancelTask();
                          setState(() {
                            _isLoading = false;
                          });
                        },
                        icon: const Icon(
                          Icons.stop_circle_rounded,
                          size: 16,
                          color: AppColors.bear,
                        ),
                        label: Text(
                          'Stop',
                          style: AppFonts.body(
                            size: 12,
                            weight: FontWeight.w700,
                            color: AppColors.bear,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ),
                ),

              // Custom Input bar
              _buildInputBar(isDark),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer(BuildContext context, bool isDark) {
    final drawerBg = isDark ? AppColors.bgDark : AppColors.bgLight;
    final textStyle = AppFonts.body(
      color: isDark
          ? AppColors.textSecondaryDark
          : AppColors.textSecondaryLight,
      weight: FontWeight.w600,
      size: 13.5,
    );
    final headerStyle = AppFonts.heading(
      size: 17,
      weight: FontWeight.w700,
      letterSpacing: -0.5,
      color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
    );

    return Drawer(
      backgroundColor: drawerBg,
      child: Column(
        children: [
          // Drawer Header
          Container(
            padding: const EdgeInsets.only(
              top: 60,
              bottom: 20,
              left: 24,
              right: 24,
            ),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Icon(
                  Icons.smart_toy_rounded,
                  color: Theme.of(context).primaryColor,
                  size: 26,
                ),
                const SizedBox(width: 12),
                Text('Neutral Pip', style: headerStyle),
              ],
            ),
          ),

          // New Chat Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    Navigator.pop(context); // Close drawer
                    _startNewChat();
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.add_comment_rounded,
                          color: AppColors.onAmber,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'New Chat',
                          style: AppFonts.body(
                            size: 13.5,
                            weight: FontWeight.w700,
                            color: AppColors.onAmber,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          const Divider(indent: 16, endIndent: 16, height: 20),

          // Section CHAT HISTORY
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'CHAT HISTORY',
                style: AppFonts.body(
                  size: 10,
                  weight: FontWeight.w800,
                  letterSpacing: 1.5,
                  color: Theme.of(context).primaryColor,
                ),
              ),
            ),
          ),

          // Chat Sessions List
          Expanded(
            child: FutureBuilder<List<ChatSession>>(
              future: ChatHistoryService.loadSessions(),
              builder: (context, snapshot) {
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return Center(
                    child: Text(
                      'No recent chats',
                      style: AppFonts.body(
                        size: 12,
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondaryLight,
                      ),
                    ),
                  );
                }

                final sessions = snapshot.data!;
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: sessions.length,
                  itemBuilder: (context, index) {
                    final session = sessions[index];
                    final isCurrent = session.id == _sessionId;

                    return Container(
                      margin: const EdgeInsets.symmetric(
                        vertical: 2,
                        horizontal: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.08)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: isCurrent
                            ? Border.all(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.15),
                              )
                            : null,
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 0,
                        ),
                        dense: true,
                        leading: Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 15,
                          color: isCurrent
                              ? Theme.of(context).colorScheme.primary
                              : (Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant),
                        ),
                        title: Text(
                          session.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textStyle.copyWith(
                            fontWeight: isCurrent
                                ? FontWeight.bold
                                : FontWeight.w500,
                            color: isCurrent
                                ? (isDark
                                      ? AppColors.textPrimaryDark
                                      : AppColors.textPrimaryLight)
                                : null,
                          ),
                        ),
                        trailing: IconButton(
                          icon: Icon(
                            Icons.delete_outline_rounded,
                            size: 16,
                            color: AppColors.bear.withValues(alpha: 0.7),
                          ),
                          onPressed: () async {
                            await ChatHistoryService.deleteSession(session.id);
                            if (isCurrent) {
                              _startNewChat();
                            }
                            (context as Element)
                                .markNeedsBuild(); // Re-trigger build refresh
                          },
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          _loadChatSession(session);
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),

          const Divider(indent: 16, endIndent: 16, height: 20),

          // Section TASKS & SETTINGS
          ListTile(
            horizontalTitleGap: 8,
            leading: Icon(
              Icons.history_rounded,
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
              size: 20,
            ),
            title: Text('Task History', style: textStyle),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TaskHistoryScreen()),
              );
            },
          ),
          ListTile(
            horizontalTitleGap: 8,
            leading: Icon(
              Icons.settings_rounded,
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
              size: 20,
            ),
            title: Text('Settings', style: textStyle),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(
                    aiService: _aiService,
                    shizukuService: _actionHandler.shizuku,
                    screenAutomationService: _actionHandler.screenAutomation,
                    telegramService: _telegramService,
                    tradingApiService: _tradingApiService,
                    tradingModeEnabled: _tradingModeEnabled,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildBackgroundGlows(bool isDark) {
    return Positioned.fill(
      child: Stack(
        children: [
          Positioned(
            top: -150,
            left: -50,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    isDark
                        ? AppColors.amber.withValues(alpha: 0.10)
                        : AppColors.amber.withValues(alpha: 0.07),
                    isDark
                        ? AppColors.amber.withValues(alpha: 0)
                        : AppColors.amber.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 50,
            right: -100,
            child: Container(
              width: 350,
              height: 350,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    isDark
                        ? const Color(0xFF334155).withValues(alpha: 0.35)
                        : const Color(0xFF94A3B8).withValues(alpha: 0.12),
                    isDark
                        ? const Color(0xFF334155).withValues(alpha: 0)
                        : const Color(0xFF94A3B8).withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeSelector(bool isDark) {
    final activeBg = Theme.of(context).colorScheme.surfaceContainerHighest;

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: activeBg,
          borderRadius: BorderRadius.circular(AppTokens.radiusPill),
          border: Border.all(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.06),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildModeButton(
              'chat',
              'Chat',
              Icons.chat_bubble_outline_rounded,
              isDark,
            ),
            _buildModeButton(
              'agent',
              'Agent',
              Icons.smart_toy_outlined,
              isDark,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeButton(
    String modeId,
    String label,
    IconData icon,
    bool isDark,
  ) {
    final isSelected = _mode == modeId;

    return GestureDetector(
      onTap: () {
        setState(() {
          _mode = modeId;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTokens.radiusPill),
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Colors.transparent,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.20),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected
                  ? AppColors.onAmber
                  : (isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: AppFonts.body(
                size: 13,
                weight: FontWeight.w700,
                color: isSelected
                    ? AppColors.onAmber
                    : (isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondaryLight),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTradingModeBadge(bool isDark) {
    // TRADING MODE: never add tap-based execution here.
    // Persistent trust/safety indicator: trades execute via the secure
    // backend API, never through on-screen automation.
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color:
              (isDark
                      ? AppColors.surfaceElevatedDark
                      : AppColors.surfaceElevatedLight)
                  .withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.shield_rounded,
              size: 14,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Execution via secure API — no on-screen automation used for trades.',
                style: AppFonts.body(
                  size: 11,
                  weight: FontWeight.w600,
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// TRADING MODE: never add tap-based execution here.
  /// Quick shortcuts only open analysis UI or trigger chart capture;
  /// execution always happens through the secure backend API.
  Widget _buildTradingActionBar() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.spaceLg,
        0,
        AppTokens.spaceLg,
        4,
      ),
      child: Row(
        children: [
          _buildActionTile(
            scheme,
            Icons.screenshot_monitor_outlined,
            'Capture Chart',
            () => _captureChartScreenshot(),
          ),
          _buildActionTile(
            scheme,
            Icons.link_rounded,
            'Chart URL',
            () => _promptChartUrl(),
          ),
          _buildActionTile(
            scheme,
            Icons.menu_book_outlined,
            'Journal',
            () => _openJournal(),
          ),
          _buildActionTile(
            scheme,
            Icons.shield_outlined,
            'Risk',
            () => _openRisk(),
          ),
        ],
      ),
    );
  }

  Widget _buildActionTile(
    ColorScheme scheme,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceSm),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(AppTokens.radiusCard),
            border: Border.all(
              color: scheme.outlineVariant,
              width: AppTokens.borderWidth,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, size: 18, color: AppColors.amber),
              const SizedBox(height: 4),
              Text(
                label,
                style: AppFonts.body(
                  size: AppTokens.fontSizeTiny,
                  weight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openJournal() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => JournalScreen(tradingApiService: _tradingApiService),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openRisk() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            RiskDashboardScreen(tradingApiService: _tradingApiService),
      ),
    );
    if (mounted) setState(() {});
  }

  /// TRADING MODE: never add tap-based execution here.
  /// Mode selection only changes the execution path; it never performs
  /// device actions itself.
  Widget _buildTradingModeSelector(bool isDark) {
    final activeBg = Theme.of(context).colorScheme.surfaceContainerHighest;

    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: activeBg,
          borderRadius: BorderRadius.circular(AppTokens.radiusPill),
          border: Border.all(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.06),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTradingModeButton(
              false,
              'Phone Control',
              Icons.phone_android_rounded,
              isDark,
            ),
            _buildTradingModeButton(
              true,
              'Trading Mode',
              Icons.trending_up_rounded,
              isDark,
            ),
          ],
        ),
      ),
    );
  }

  /// TRADING MODE: never add tap-based execution here.
  /// Button selection only changes the execution path; it never performs
  /// device actions itself.
  Widget _buildTradingModeButton(
    bool tradingMode,
    String label,
    IconData icon,
    bool isDark,
  ) {
    final isSelected = _tradingModeEnabled == tradingMode;

    return GestureDetector(
      onTap: () => _setTradingMode(tradingMode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTokens.radiusPill),
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Colors.transparent,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.20),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected
                  ? AppColors.onAmber
                  : (isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: AppFonts.body(
                size: 13,
                weight: FontWeight.w700,
                color: isSelected
                    ? AppColors.onAmber
                    : (isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondaryLight),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setTradingMode(bool enabled) async {
    // TRADING MODE: never add tap-based execution here.
    // This toggle only selects the execution path (secure backend API vs
    // on-screen automation); it never triggers device actions itself.
    setState(() {
      _tradingModeEnabled = enabled;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('trading_mode_enabled', enabled);
  }

  Widget _buildEmptyState(bool isDark) {
    final time = DateTime.now();
    String timeGreeting = 'Hello';
    if (time.hour >= 5 && time.hour < 12) {
      timeGreeting = 'Hello, good morning.';
    } else if (time.hour >= 12 && time.hour < 17) {
      timeGreeting = 'Hello, good afternoon.';
    } else if (time.hour >= 17 && time.hour < 22) {
      timeGreeting = 'Hello, good evening.';
    } else {
      timeGreeting = 'Hello.';
    }

    final suggestions = _tradingModeEnabled
        ? [
            'Analyze BTC/USD on the 15m chart',
            'What is my current risk exposure?',
            'Show my latest journal entries',
            'Explain this chart pattern',
          ]
        : _mode == 'chat'
        ? [
            'Write a professional email',
            'Explain quantum computing simply',
            'Brainstorm mobile app ideas',
            'Write a poem about robots',
          ]
        : [
            'Open YouTube and search for cats',
            'Call Mom',
            'Set volume to 80%',
            'What\'s on my screen?',
          ];

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    timeGreeting,
                    style: AppFonts.heading(
                      size: 30,
                      weight: FontWeight.w300,
                      letterSpacing: -1.5,
                      height: 1.1,
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondaryLight,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'How can I help you?',
                    style: AppFonts.heading(
                      size: 30,
                      weight: FontWeight.w600,
                      letterSpacing: -1.5,
                      height: 1.2,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            if (_tradingModeEnabled) ...[
              const SizedBox(height: 24),
              Container(
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
                      Icons.candlestick_chart_rounded,
                      color: AppColors.amber,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Drop a chart screenshot or paste a TradingView URL '
                        'to get an AI signal read.',
                        style: AppFonts.body(
                          size: 13,
                          height: 1.4,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 48),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'SUGGESTIONS',
                style: AppFonts.body(
                  size: 11,
                  weight: FontWeight.w800,
                  letterSpacing: 1.5,
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 52,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: suggestions.length,
                itemBuilder: (context, index) {
                  final suggestion = suggestions[index];
                  return Container(
                    margin: const EdgeInsets.only(right: 12),
                    child: InkWell(
                      onTap: () => _sendMessage(suggestion),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppColors.surfaceElevatedDark
                              : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isDark
                                ? AppColors.borderDark
                                : AppColors.borderLight,
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: isDark ? 0.1 : 0.02,
                              ),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            suggestion,
                            style: AppFonts.body(
                              size: 12.5,
                              weight: FontWeight.w600,
                              color: isDark
                                  ? AppColors.textPrimaryDark
                                  : AppColors.textPrimaryLight,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// TRADING MODE: never add tap-based execution here.
  List<Map<String, dynamic>> _attachmentMaps() =>
      _pendingAttachments.map((a) => a.toJson()).toList();

  /// TRADING MODE: never add tap-based execution here.
  void _removePendingAttachment(ChatAttachment attachment) {
    setState(() {
      _pendingAttachments.remove(attachment);
    });
  }

  Future<void> _showAttachmentPicker() async {
    // TRADING MODE: never add tap-based execution here.
    // Attachments are sent to the secure backend API alongside the text;
    // they are never used to drive on-screen automation.
    final source = await showModalBottomSheet<AttachmentSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Gallery'),
              subtitle: const Text('Chart screenshots from your library'),
              onTap: () => Navigator.pop(context, AttachmentSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Camera'),
              subtitle: const Text('Capture a chart with the camera'),
              onTap: () => Navigator.pop(context, AttachmentSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: const Text('File'),
              subtitle: const Text('PDF, text, or image files'),
              onTap: () => Navigator.pop(context, AttachmentSource.file),
            ),
            ListTile(
              leading: const Icon(Icons.screenshot_monitor_outlined),
              title: const Text('Capture Chart'),
              subtitle: const Text('Screenshot the current chart on screen'),
              onTap: () => Navigator.pop(context, AttachmentSource.screenshot),
            ),
            ListTile(
              leading: const Icon(Icons.link_rounded),
              title: const Text('Chart URL'),
              subtitle: const Text('Paste a public TradingView chart URL'),
              onTap: () => Navigator.pop(context, AttachmentSource.chartUrl),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    switch (source) {
      case AttachmentSource.gallery:
        await _pickImage(ImageSource.gallery);
        break;
      case AttachmentSource.camera:
        await _pickImage(ImageSource.camera);
        break;
      case AttachmentSource.file:
        await _pickFile();
        break;
      case AttachmentSource.screenshot:
        await _captureChartScreenshot();
        break;
      case AttachmentSource.chartUrl:
        await _promptChartUrl();
        break;
    }
  }

  Future<void> _captureChartScreenshot() async {
    // TRADING MODE: never add tap-based execution here.
    // Capture only reads the current screen (native screenshot); it never
    // performs taps, swipes, or any other device action.
    final attachment = await _actionHandler.screenAutomation
        .captureChartScreenshot();
    if (!mounted) return;
    if (attachment == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not capture chart. Requires Android 11+ and the '
            'accessibility service to be active.',
          ),
        ),
      );
      return;
    }
    setState(() {
      _pendingAttachments.add(attachment);
    });
  }

  Future<void> _promptChartUrl() async {
    // TRADING MODE: never add tap-based execution here.
    // A chart URL is metadata for the backend; it never triggers any
    // on-device action itself.
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Chart URL'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'https://www.tradingview.com/chart/...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (url == null || url.isEmpty || !mounted) return;
    if (!url.startsWith('http')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid http(s) URL.')),
      );
      return;
    }
    setState(() {
      _pendingAttachments.add(
        ChatAttachment(name: url, path: url, type: 'url'),
      );
    });
  }

  /// TRADING MODE: never add tap-based execution here.
  /// Picking an image only adds a local file reference; it never performs
  /// any device action.
  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(source: source);
      if (picked == null || !mounted) return;
      setState(() {
        _pendingAttachments.add(
          ChatAttachment(
            name: picked.name,
            path: picked.path,
            type: 'image',
            mimeType: picked.mimeType,
          ),
        );
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not pick image: $e')));
      }
    }
  }

  /// TRADING MODE: never add tap-based execution here.
  /// Picking a file only adds a local file reference; it never performs
  /// any device action.
  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'txt', 'md', 'png', 'jpg', 'jpeg'],
      );
      if (result == null || result.files.isEmpty || !mounted) return;
      final file = result.files.first;
      final lowerName = file.name.toLowerCase();
      final isImage =
          lowerName.endsWith('.png') ||
          lowerName.endsWith('.jpg') ||
          lowerName.endsWith('.jpeg');
      setState(() {
        _pendingAttachments.add(
          ChatAttachment(
            name: file.name,
            path: file.path ?? file.name,
            type: isImage ? 'image' : 'file',
            sizeBytes: file.size,
          ),
        );
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not pick file: $e')));
      }
    }
  }

  Widget _buildInputBar(bool isDark) {
    final scheme = Theme.of(context).colorScheme;
    final chipColor = Theme.of(context).cardTheme.color ?? scheme.surface;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      decoration: const BoxDecoration(color: Colors.transparent),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Pending attachments (Trading Mode only)
          if (_tradingModeEnabled && _pendingAttachments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: _pendingAttachments.map((att) {
                  return Chip(
                    avatar: Icon(
                      att.type == 'image'
                          ? Icons.image_outlined
                          : Icons.insert_drive_file_outlined,
                      size: 16,
                    ),
                    label: Text(
                      att.name,
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                    visualDensity: VisualDensity.compact,
                    onDeleted: () => _removePendingAttachment(att),
                  );
                }).toList(),
              ),
            ),
          Row(
            children: [
              // Glowing Voice Mic button (hidden in Trading Mode - voice
              // commands would route to the trading API while the mic
              // drives the Phone Control agent flow).
              if (!_tradingModeEnabled)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isListening ? Colors.redAccent : chipColor,
                    border: Border.all(
                      color: _isListening
                          ? Colors.redAccent
                          : scheme.onSurface.withValues(alpha: 0.08),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isDark ? 0.2 : 0.03,
                        ),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                      if (_isListening)
                        BoxShadow(
                          color: Colors.redAccent.withValues(alpha: 0.4),
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                    ],
                  ),
                  child: IconButton(
                    icon: Icon(
                      _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                      color: _isListening
                          ? Colors.white
                          : Theme.of(context).colorScheme.primary,
                    ),
                    onPressed: _isLoading ? null : _toggleVoice,
                  ),
                ),
              const SizedBox(width: 10),

              // Custom Text input container
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: chipColor,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: scheme.onSurface.withValues(alpha: 0.08),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isDark ? 0.2 : 0.03,
                        ),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      if (_tradingModeEnabled)
                        IconButton(
                          icon: const Icon(Icons.attach_file_rounded, size: 20),
                          color: Theme.of(context).colorScheme.primary,
                          tooltip: 'Attach chart image or file',
                          onPressed: _isLoading ? null : _showAttachmentPicker,
                        ),
                      Expanded(
                        child: TextField(
                          controller: _textController,
                          style: AppFonts.body(size: 14),
                          decoration: InputDecoration(
                            hintText: _isListening
                                ? 'Listening...'
                                : 'Type a command...',
                            hintStyle: AppFonts.body(
                              size: 13,
                              color: isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondaryLight,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            border: InputBorder.none,
                          ),
                          textInputAction: TextInputAction.send,
                          onSubmitted: _isLoading
                              ? null
                              : (text) => _sendMessage(
                                  text,
                                  attachments: _attachmentMaps(),
                                ),
                        ),
                      ),

                      // Solid Send button
                      Container(
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        child: IconButton(
                          icon: const Icon(
                            Icons.send_rounded,
                            size: 16,
                            color: AppColors.onAmber,
                          ),
                          onPressed: _isLoading
                              ? null
                              : () => _sendMessage(
                                  _textController.text,
                                  attachments: _attachmentMaps(),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
