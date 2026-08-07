import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../services/ai_service.dart';
import '../services/auth_service.dart';
import '../widgets/logo_loader.dart';
import 'auth_gate.dart';
import '../services/telegram_service.dart';
import '../services/trading_api_service.dart';
import 'connect_accounts_screen.dart';
import 'strategy_training_screen.dart';
import 'agent_setup_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import '../config/feature_flags.dart';
import '../config/theme.dart';

class SettingsScreen extends StatefulWidget {
  final AiService aiService;
  final TelegramService telegramService;
  final TradingApiService tradingApiService;

  const SettingsScreen({
    super.key,
    required this.aiService,
    required this.telegramService,
    required this.tradingApiService,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  late TextEditingController _apiKeyController;
  late TextEditingController _baseUrlController;
  late TextEditingController _modelController;
  late TextEditingController _telegramTokenController;
  late TextEditingController _tradingBackendUrlController;
  bool _obscureKey = true;
  bool _telegramEnabled = false;
  late TextEditingController _maxTokensController;
  double _temperature = 1.0;
  bool _useScreenCompression = true;
  bool _useSystemPrompt = true;
  bool _floatingIconEnabled = false;
  bool _isOverlayPermissionGranted = false;

  // Auto-Execute (Trading Mode): server state + risk limits from strategy.
  bool _autoExecute = false;
  bool _autoExecuteUpdating = false;
  Map<String, dynamic>? _riskLimits;

  // Agent activation: the user's own pause switch (separate from the
  // admin kill-switch). Deactivation is reversible and never deletes data.
  bool? _agentActive;
  bool _agentUpdating = false;

  final Map<String, PermissionStatus> _permissions = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _apiKeyController = TextEditingController(text: widget.aiService.apiKey);
    _baseUrlController = TextEditingController(text: widget.aiService.baseUrl);
    _modelController = TextEditingController(text: widget.aiService.model);
    _telegramTokenController = TextEditingController(
      text: widget.telegramService.botToken,
    );
    _tradingBackendUrlController = TextEditingController(
      text: widget.tradingApiService.tradingBackendUrl,
    );
    _telegramEnabled = widget.telegramService.isEnabled;
    _temperature = widget.aiService.temperature;
    _maxTokensController = TextEditingController(
      text: widget.aiService.maxTokens.toString(),
    );
    _useScreenCompression = widget.aiService.useScreenCompression;
    _useSystemPrompt = widget.aiService.useSystemPrompt;

    // Auto-save listeners
    _apiKeyController.addListener(_autoSave);
    _baseUrlController.addListener(_autoSave);
    _modelController.addListener(_autoSave);
    _telegramTokenController.addListener(_autoSave);
    _tradingBackendUrlController.addListener(_autoSave);
    _maxTokensController.addListener(_autoSave);

    _checkPermissions();
    if (FeatureFlags.floatingOverlayEnabled) {
      _checkOverlayStatus();
    }
    _loadAutoExecute();
    _loadAgentStatus();
  }

  /// Load the agent's activation state from the backend. Stays `null` (and
  /// the toggle hides) when no trading backend is configured.
  Future<void> _loadAgentStatus() async {
    if (!widget.tradingApiService.isConfigured) return;
    final status = await widget.tradingApiService.getAgentStatus();
    if (!mounted || status['status'] == 'error') return;
    if (status.containsKey('agent_active')) {
      setState(() {
        _agentActive = status['agent_active'] == true;
      });
    }
  }

  /// Flip the user's own agent pause switch. Deactivating asks for
  /// confirmation (it pauses chat, analysis and alarms); reactivating is
  /// immediate and reversible.
  Future<void> _onAgentToggle(bool value) async {
    if (value) {
      // Reactivate — no confirmation needed, nothing is lost.
      setState(() => _agentUpdating = true);
      final response = await widget.tradingApiService.activateAgent();
      if (!mounted) return;
      setState(() {
        _agentUpdating = false;
        if (response['activated'] == true) _agentActive = true;
      });
      if (response['activated'] != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.bear,
            content: Text(
              'Could not activate: ${response['message'] ?? 'unknown error'}',
            ),
          ),
        );
      }
      return;
    }

    // Deactivate — reversible pause, ask before switching the agent off.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        ),
        title: const Text('Pause your agent?'),
        content: const Text(
          'Chat, analysis and alarms will pause until you switch it back on. '
          'Your strategy, memory and history are kept — nothing is deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.amber),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Pause'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _agentUpdating = true);
    final response = await widget.tradingApiService.deactivateAgent();
    if (!mounted) return;
    setState(() {
      _agentUpdating = false;
      if (response['deactivated'] == true) _agentActive = false;
    });
    if (response['deactivated'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.bear,
          content: Text(
            'Could not pause: ${response['message'] ?? 'unknown error'}',
          ),
        ),
      );
    }
  }

  /// Load the auto-execute flag + risk limits from the trading backend so
  /// the toggle shows the current server state and the applicable limits.
  Future<void> _loadAutoExecute() async {
    final data = await widget.tradingApiService.getSettings();
    if (!mounted) return;
    setState(() {
      _autoExecute = data['auto_execute'] == true;
      _riskLimits = data['risk_limits'] is Map<String, dynamic>
          ? data['risk_limits'] as Map<String, dynamic>
          : null;
    });
  }

  String get _riskLimitsSubtitle {
    final limits = _riskLimits;
    if (limits != null) {
      final risk = limits['max_risk_percent'];
      final daily = limits['max_daily_loss_percent'];
      return 'Risk limits: $risk% per trade · $daily% daily loss. '
          'Configured in Train My Strategy.';
    }
    return 'No risk limits saved yet. Set them in Train My Strategy first.';
  }

  /// Enabling auto-execute requires an explicit confirmation (same gate as
  /// connecting a real MT5 account). The toggle stays off until confirmed.
  Future<void> _onAutoExecuteChanged(bool value) async {
    if (value) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surfaceDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusCard),
          ),
          title: const Text('Enable auto-execution?'),
          content: const Text(
            'I understand the agent will place real trades on my connected '
            'MT5 account without asking me first, within my configured risk '
            'limits.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.amber),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('I Understand'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return; // stays off
    }

    setState(() {
      _autoExecute = value;
      _autoExecuteUpdating = true;
    });
    final response = await widget.tradingApiService.updateSettings(
      autoExecute: value,
    );
    if (!mounted) return;
    setState(() => _autoExecuteUpdating = false);
    if (response['status'] != 'ok') {
      setState(() => _autoExecute = !value); // revert on failure
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.bear,
          content: Text(
            'Could not update: ${response['message'] ?? 'unknown error'}',
          ),
        ),
      );
      return;
    }
    if (response['risk_limits'] is Map<String, dynamic>) {
      setState(() {
        _riskLimits = response['risk_limits'] as Map<String, dynamic>;
      });
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.bullDim,
        content: Text(
          value
              ? 'Auto-execute enabled. Trades are placed server-side within '
                    'your risk limits.'
              : 'Auto-execute disabled.',
        ),
      ),
    );
  }

  Future<void> _checkOverlayStatus() async {
    bool isActive = await FlutterOverlayWindow.isActive();
    bool isGranted = await FlutterOverlayWindow.isPermissionGranted();
    if (mounted) {
      setState(() {
        _floatingIconEnabled = isActive;
        _isOverlayPermissionGranted = isGranted;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _apiKeyController.removeListener(_autoSave);
    _baseUrlController.removeListener(_autoSave);
    _modelController.removeListener(_autoSave);
    _telegramTokenController.removeListener(_autoSave);
    _tradingBackendUrlController.removeListener(_autoSave);
    _maxTokensController.removeListener(_autoSave);
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    _telegramTokenController.dispose();
    _tradingBackendUrlController.dispose();
    _maxTokensController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
      if (FeatureFlags.floatingOverlayEnabled) {
        _checkOverlayStatus();
      }
    }
  }

  Future<void> _checkPermissions() async {
    final perms = {
      'Microphone': Permission.microphone,
      'Notifications': Permission.notification,
    };

    for (final entry in perms.entries) {
      _permissions[entry.key] = await entry.value.status;
    }
    final overlayGranted = FeatureFlags.floatingOverlayEnabled
        ? await FlutterOverlayWindow.isPermissionGranted()
        : false;
    if (mounted) {
      setState(() {
        _isOverlayPermissionGranted = overlayGranted;
      });
    }
  }

  Future<void> _requestPermission(String name, Permission permission) async {
    final status = await permission.request();
    setState(() => _permissions[name] = status);
  }

  void _autoSave() {
    widget.aiService.saveSettings(
      apiKey: _apiKeyController.text.trim(),
      baseUrl: _baseUrlController.text.trim(),
      model: _modelController.text.trim(),
    );

    widget.telegramService.saveSettings(
      botToken: _telegramTokenController.text.trim(),
      isEnabled: _telegramEnabled,
    );

    // TRADING MODE: never add tap-based execution here.
    widget.tradingApiService.saveSettings(
      tradingBackendUrl: _tradingBackendUrlController.text.trim(),
    );

    widget.aiService.saveAdvancedSettings(
      temperature: _temperature,
      maxTokens: int.tryParse(_maxTokensController.text) ?? 1024,
      useScreenCompression: _useScreenCompression,
      useSystemPrompt: _useSystemPrompt,
    );
  }

  /// Set or change the fast re-entry PIN (local to this device only).
  Future<void> _setPin() async {
    final newPin = await showDialog<String>(
      context: context,
      builder: (ctx) => const _PinDialog(),
    );
    if (newPin == null) return;
    await AuthService.instance.setPin(newPin);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('PIN saved for fast re-entry.')),
    );
    setState(() {});
  }

  /// Revoke the session server-side and return to the auth gate.
  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        title: const Text('Sign out?'),
        content: const Text(
          'Your session will be revoked on the backend. You will need your '
          'passkey to sign back in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.bear),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await AuthService.instance.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthGate()),
      (route) => false,
    );
  }

  Future<void> _fetchModels() async {
    final baseUrl = _baseUrlController.text.trim();
    final apiKey = _apiKeyController.text.trim();

    if (baseUrl.isEmpty || apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter Base URL and API Key first.'),
        ),
      );
      return;
    }

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: LogoLoader(size: 64)),
    );

    final models = await widget.aiService.fetchAvailableModels(baseUrl, apiKey);

    // Hide loading
    if (mounted) Navigator.pop(context);

    if (models.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No models found or error fetching models.'),
          ),
        );
      }
      return;
    }

    if (mounted) {
      final isNvidia = AiService.isNvidiaBaseUrl(baseUrl);
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            isNvidia ? 'Select a Free NVIDIA Model' : 'Select a Model',
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: ListView.builder(
              itemCount: models.length,
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text(models[index]),
                  onTap: () {
                    setState(() {
                      _modelController.text = models[index];
                    });
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildSettingsCard({
    required IconData icon,
    required String title,
    String? subtitle,
    required List<Widget> children,
    required bool isDark,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: AppTokens.spaceLg),
      padding: const EdgeInsets.all(AppTokens.spaceLg),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        border: Border.all(
          color: scheme.outlineVariant,
          width: AppTokens.borderWidth,
        ),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppTokens.radiusControl),
                  border: Border.all(
                    color: AppColors.amber.withValues(alpha: 0.25),
                    width: 1,
                  ),
                ),
                child: Icon(icon, color: AppColors.amber, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.toUpperCase(),
                      style: AppFonts.body(
                        size: 13,
                        weight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: scheme.onSurface,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: AppFonts.body(
                          size: 12,
                          color: isDark
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondaryLight,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceLg),
          ...children,
        ],
      ),
    );
  }

  /// Tiny uppercase label separating logical groups of setting cards.
  Widget _sectionLabel(String text) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(
        top: AppTokens.spaceMd,
        bottom: AppTokens.spaceSm,
      ),
      child: Text(
        text.toUpperCase(),
        style: AppFonts.body(
          size: AppTokens.fontSizeTiny,
          weight: FontWeight.w700,
          letterSpacing: 1.4,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }

  InputDecoration _buildInputDecoration({
    required String labelText,
    required String hintText,
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) {
    final scheme = Theme.of(context).colorScheme;
    const radius = BorderRadius.all(Radius.circular(AppTokens.radiusControl));
    final borderSide = BorderSide(color: scheme.outlineVariant, width: 1);
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      labelStyle: AppFonts.body(
        size: 13,
        weight: FontWeight.w600,
        color: scheme.onSurfaceVariant,
      ),
      hintStyle: AppFonts.body(
        size: 13,
        color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: radius, borderSide: borderSide),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: borderSide,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.primary,
          width: 1.8,
        ),
      ),
      floatingLabelBehavior: FloatingLabelBehavior.auto,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Settings',
          style: AppFonts.heading(
            size: AppTokens.headlineSize,
            weight: FontWeight.w700,
            color: scheme.onSurface,
          ),
        ),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          // Appearance
          _sectionLabel('Appearance'),
          _buildSettingsCard(
            icon: Icons.palette_outlined,
            title: 'Appearance',
            subtitle: 'Choose your preferred color theme',
            isDark: isDark,
            children: [
              ValueListenableBuilder<ThemeMode>(
                valueListenable: themeNotifier,
                builder: (context, currentMode, _) {
                  return SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<ThemeMode>(
                      style: SegmentedButton.styleFrom(
                        selectedBackgroundColor: Theme.of(
                          context,
                        ).colorScheme.primary,
                        selectedForegroundColor: AppColors.onAmber,
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        foregroundColor: Theme.of(
                          context,
                        ).colorScheme.onSurface,
                        side: BorderSide(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      segments: [
                        ButtonSegment(
                          value: ThemeMode.system,
                          label: const Text(
                            'System',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          icon: const Icon(Icons.brightness_auto, size: 16),
                        ),
                        ButtonSegment(
                          value: ThemeMode.light,
                          label: const Text(
                            'Light',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          icon: const Icon(Icons.light_mode, size: 16),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          label: const Text(
                            'Dark',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          icon: const Icon(Icons.dark_mode, size: 16),
                        ),
                      ],
                      selected: {currentMode},
                      onSelectionChanged: (Set<ThemeMode> newSelection) async {
                        final mode = newSelection.first;
                        themeNotifier.value = mode;
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString('themeMode', mode.name);
                      },
                    ),
                  );
                },
              ),
            ],
          ),

          // 2. AI Engine Config Card — fallback AI, used only when the
          // trading backend is unreachable or not connected (the backend
          // serves chat through its own Hermes instance).
          _sectionLabel('Fallback AI'),
          _buildSettingsCard(
            icon: Icons.psychology_outlined,
            title: 'Fallback AI Configuration',
            subtitle:
                'Used only when the trading backend is offline or not connected',
            isDark: isDark,
            children: [
              TextField(
                controller: _apiKeyController,
                decoration: _buildInputDecoration(
                  labelText: 'API Key',
                  hintText: 'sk-...',
                  prefixIcon: const Icon(Icons.key_rounded, size: 18),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureKey ? Icons.visibility_off : Icons.visibility,
                      size: 18,
                    ),
                    onPressed: () => setState(() => _obscureKey = !_obscureKey),
                  ),
                ),
                obscureText: _obscureKey,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _baseUrlController,
                decoration: _buildInputDecoration(
                  labelText: 'API Base URL',
                  hintText: 'https://api.deepseek.com',
                  prefixIcon: const Icon(Icons.dns_rounded, size: 18),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  ActionChip(
                    label: const Text(
                      'Local Server',
                      style: TextStyle(fontSize: 11),
                    ),
                    tooltip: 'For local Llama.cpp or LM Studio',
                    onPressed: () =>
                        _baseUrlController.text = 'http://192.168.1.X:8080/v1',
                  ),
                  ActionChip(
                    label: const Text(
                      'Ollama Cloud',
                      style: TextStyle(fontSize: 11),
                    ),
                    onPressed: () {
                      _baseUrlController.text = 'https://ollama.com/v1';
                      _modelController.text = 'gemma3:4b';
                    },
                  ),
                  ActionChip(
                    label: const Text(
                      'DeepSeek',
                      style: TextStyle(fontSize: 11),
                    ),
                    onPressed: () =>
                        _baseUrlController.text = 'https://api.deepseek.com',
                  ),
                  ActionChip(
                    label: const Text('Groq', style: TextStyle(fontSize: 11)),
                    onPressed: () => _baseUrlController.text =
                        'https://api.groq.com/openai/v1',
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.memory_rounded, size: 16),
                    label: const Text('NVIDIA', style: TextStyle(fontSize: 11)),
                    tooltip: 'NVIDIA NIM free endpoints',
                    onPressed: () {
                      _baseUrlController.text = AiService.nvidiaBaseUrl;
                      _modelController.text = AiService.nvidiaDefaultModel;
                    },
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.router_rounded, size: 16),
                    label: const Text(
                      'OpenRouter',
                      style: TextStyle(fontSize: 11),
                    ),
                    tooltip:
                        'OpenRouter unified API - Claude, DeepSeek, and more',
                    onPressed: () {
                      _baseUrlController.text = AiService.openRouterBaseUrl;
                      _modelController.text = AiService.openRouterDefaultModel;
                    },
                  ),
                  ActionChip(
                    label: const Text('Custom', style: TextStyle(fontSize: 11)),
                    tooltip: 'Clear fields',
                    onPressed: () {
                      _baseUrlController.clear();
                      _apiKeyController.clear();
                      _modelController.clear();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _modelController,
                      decoration: _buildInputDecoration(
                        labelText: 'Model',
                        hintText: 'deepseek-chat',
                        prefixIcon: const Icon(
                          Icons.smart_toy_rounded,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _fetchModels,
                    icon: const Icon(
                      Icons.cloud_download,
                      size: 18,
                      color: AppColors.onAmber,
                    ),
                    label: const Text(
                      'Fetch',
                      style: TextStyle(
                        color: AppColors.onAmber,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'When a trading backend is connected, chat and analysis run '
                'through the backend\'s AI. This key is only used as a '
                'fallback when the backend is unreachable or not connected.',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),

          // 3. Parameters & Tuning Card
          _buildSettingsCard(
            icon: Icons.tune_outlined,
            title: 'Response Settings',
            subtitle: 'Configure the assistant response behavior',
            isDark: isDark,
            children: [
              TextField(
                controller: _maxTokensController,
                keyboardType: TextInputType.number,
                decoration: _buildInputDecoration(
                  labelText: 'Context Limit (Max Tokens)',
                  hintText: '1024',
                  prefixIcon: const Icon(Icons.token_rounded, size: 18),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Temperature: ${_temperature.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
              Slider(
                value: _temperature,
                min: 0.0,
                max: 2.0,
                divisions: 20,
                label: _temperature.toStringAsFixed(2),
                onChanged: (value) {
                  setState(() {
                    _temperature = value;
                  });
                },
                onChangeEnd: (value) {
                  _autoSave();
                },
              ),
            ],
          ),

          // 4. Behavior & Extensions Card
          _buildSettingsCard(
            icon: Icons.extension_outlined,
            title: 'Behavior & Extensions',
            subtitle: 'Additional feature flags and overlay options',
            isDark: isDark,
            children: [
              SwitchListTile(
                title: const Text('Send System Prompt'),
                subtitle: const Text('Turn off for custom LoRA fine-tunes'),
                value: _useSystemPrompt,
                onChanged: (bool value) {
                  setState(() {
                    _useSystemPrompt = value;
                  });
                  _autoSave();
                },
                contentPadding: EdgeInsets.zero,
              ),
              if (FeatureFlags.floatingOverlayEnabled)
                SwitchListTile(
                  title: const Text('Enable Floating Assistant Icon'),
                  subtitle: const Text('Quick access to the co-pilot from any screen'),
                  value: _floatingIconEnabled,
                  onChanged: (val) async {
                    if (val) {
                      bool? isGranted =
                          await FlutterOverlayWindow.isPermissionGranted();
                      if (isGranted != true) {
                        bool? result =
                            await FlutterOverlayWindow.requestPermission();
                        if (result != true) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Permission to draw over other apps is required.',
                                ),
                              ),
                            );
                          }
                          return;
                        }
                      }
                      if (await FlutterOverlayWindow.isActive() == false) {
                        await FlutterOverlayWindow.showOverlay(
                          enableDrag: true,
                          overlayTitle: "Neutral Pip",
                          overlayContent: "Floating Assistant",
                          flag: OverlayFlag.focusPointer,
                          alignment: OverlayAlignment.centerRight,
                          visibility: NotificationVisibility.visibilitySecret,
                          positionGravity: PositionGravity.auto,
                          startPosition: const OverlayPosition(0, 200),
                          width: 56,
                          height: 56,
                        );
                      }
                    } else {
                      if (await FlutterOverlayWindow.isActive() == true) {
                        await FlutterOverlayWindow.closeOverlay();
                      }
                    }
                    setState(() => _floatingIconEnabled = val);
                    _autoSave();
                  },
                  contentPadding: EdgeInsets.zero,
                ),
            ],
          ),

          // 5b. Account Card (Trading Mode auth)
          if (AuthService.instance.isBackendConfigured) ...[
            _sectionLabel('Account'),
            _buildSettingsCard(
              icon: Icons.person_outline_rounded,
              title: 'Signed in as ${AuthService.instance.displayName ?? ''}',
              subtitle: AuthService.instance.email ?? '',
              isDark: isDark,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.password_rounded,
                      color: AppColors.amber),
                  title: const Text('Set / Change PIN'),
                  subtitle: const Text(
                    '4-6 digit fast re-entry PIN for this device only',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _setPin,
                ),
                const Divider(
                  height: AppTokens.spaceXl,
                  color: AppColors.borderDark,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.logout_rounded,
                      color: AppColors.bear),
                  title: const Text('Sign out'),
                  subtitle: const Text('Revoke this session on all devices',
                      style: TextStyle(color: AppColors.bear)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _signOut,
                ),
              ],
            ),
          ],

          // 5. Telegram Remote Access Card
          _sectionLabel('Connectivity'),
          _buildSettingsCard(
            icon: Icons.send_and_archive_outlined,
            title: 'Telegram',
            subtitle: 'Chat with your trading assistant and receive scheduled '
                'analysis pushes from anywhere',
            isDark: isDark,
            children: [
              TextField(
                controller: _telegramTokenController,
                decoration: _buildInputDecoration(
                  labelText: 'Telegram Bot Token',
                  hintText: '123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11',
                  prefixIcon: const Icon(Icons.send_rounded, size: 18),
                ),
              ),
              SwitchListTile(
                title: const Text('Enable Telegram Bot'),
                subtitle: const Text('Allows chatting with the assistant via '
                    'Telegram'),
                value: _telegramEnabled,
                onChanged: (val) {
                  setState(() => _telegramEnabled = val);
                  _autoSave();
                },
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),

          // 6. App Permissions Card
          _sectionLabel('App Permissions'),
          _buildSettingsCard(
            icon: Icons.security_outlined,
            title: 'App Permissions',
            subtitle: 'Required for voice chat and notifications',
            isDark: isDark,
            children: _buildPermissionTiles(),
          ),

          // 7. Trading Backend Card
          _sectionLabel('Trading'),
          _buildSettingsCard(
            icon: Icons.api_rounded,
            title: 'Trading Backend',
            subtitle:
                'Secure API for trading analysis and commands - no on-screen '
                'automation',
            isDark: isDark,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.circle,
                    size: 8,
                    color: widget.tradingApiService.isConfigured
                        ? AppColors.bull
                        : AppColors.textSecondaryDark,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    widget.tradingApiService.isConfigured
                        ? 'Connected'
                        : 'Offline. Add a backend URL below',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: widget.tradingApiService.isConfigured
                          ? AppColors.bull
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _tradingBackendUrlController,
                decoration: _buildInputDecoration(
                  labelText: 'Trading Backend URL',
                  hintText: 'https://your-trading-backend.example.com',
                  prefixIcon: const Icon(Icons.dns_rounded, size: 18),
                ),
              ),
              const SizedBox(height: AppTokens.spaceSm),
              const Divider(
                height: AppTokens.spaceXl,
                color: AppColors.borderDark,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.link_rounded, color: AppColors.amber),
                title: const Text('Connect Trading Accounts'),
                subtitle: const Text(
                  'TradingView watchlist & MT5 real accounts',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ConnectAccountsScreen(
                        tradingApiService: widget.tradingApiService,
                      ),
                    ),
                  );
                },
              ),
              const Divider(
                height: AppTokens.spaceXl,
                color: AppColors.borderDark,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.school_outlined, color: AppColors.amber),
                title: const Text('Train My Strategy'),
                subtitle: const Text(
                  'Define rules, indicators & risk limits, then backtest',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => StrategyTrainingScreen(
                        tradingApiService: widget.tradingApiService,
                      ),
                    ),
                  );
                },
              ),
              const Divider(
                height: AppTokens.spaceXl,
                color: AppColors.borderDark,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.smart_toy_outlined, color: AppColors.amber),
                title: const Text('Agent Setup'),
                subtitle: const Text(
                  'Train from uploads, configure by chat, manage skills & alarms',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AgentSetupScreen(
                        tradingApiService: widget.tradingApiService,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),

          // 7b. Auto-Execute Card (Trading Mode)
          _buildSettingsCard(
            icon: Icons.bolt_rounded,
            title: 'Auto-Execute',
            subtitle: 'Server-side trade execution within your risk limits',
            isDark: isDark,
            children: [
              SwitchListTile(
                title: const Text('Let the agent execute trades automatically.'),
                subtitle: Text(_riskLimitsSubtitle),
                value: _autoExecute,
                onChanged: _autoExecuteUpdating
                    ? null
                    : (value) => _onAutoExecuteChanged(value),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),

          // 7c. Agent Status Card — the user's own pause switch. Only shown
          // when a trading backend is configured (state lives server-side).
          if (_agentActive != null)
            _buildSettingsCard(
              icon: Icons.smart_toy_outlined,
              title: 'Agent Status',
              subtitle: 'Pause or resume your agent at any time',
              isDark: isDark,
              children: [
                SwitchListTile(
                  title: Text(
                    _agentActive! ? 'Agent is active' : 'Agent is paused',
                  ),
                  subtitle: Text(
                    _agentActive!
                        ? 'Chat, analysis and alarms are running.'
                        : 'Chat, analysis and alarms are paused. Your data is kept.',
                  ),
                  value: _agentActive!,
                  onChanged: _agentUpdating
                      ? null
                      : (value) => _onAgentToggle(value),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),

          // 8. About / Links Card
          _sectionLabel('About'),
          _buildSettingsCard(
            icon: Icons.info_outline_rounded,
            title: 'About Neutral Pip',
            subtitle: 'Resources and repository access',
            isDark: isDark,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Project Repository'),
                subtitle: const Text('View source code on GitHub'),
                leading: const Icon(Icons.code_rounded),
                onTap: () {
                  launchUrl(
                    Uri.parse('https://github.com/neutralpip/neutral-pip'),
                    mode: LaunchMode.externalApplication,
                  );
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Creator channels'),
                subtitle: const Text('Orailnoor & Tech Jarves on YouTube'),
                leading: const Icon(
                  Icons.play_circle_fill_rounded,
                  color: AppColors.bear,
                ),
                onTap: () => _openCreatorChannels(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildPermissionTiles() {
    final permissionMap = {
      'Microphone': Permission.microphone,
      'Notifications': Permission.notification,
    };

    final icons = {
      'Microphone': Icons.mic,
      'Notifications': Icons.notifications,
    };

    final list = permissionMap.entries.map((entry) {
      final status = _permissions[entry.key];
      final isGranted = status?.isGranted ?? false;

      return ListTile(
        leading: Icon(icons[entry.key]),
        title: Text(entry.key),
        trailing: isGranted
            ? Icon(
                Icons.check_circle,
                color: Theme.of(context).colorScheme.primary,
              )
            : TextButton(
                onPressed: () => _requestPermission(entry.key, entry.value),
                child: const Text('Grant'),
              ),
        subtitle: Text(
          isGranted
              ? 'Granted'
              : (status?.isDenied ?? true
                    ? 'Not granted'
                    : 'Denied permanently'),
          style: TextStyle(
            color: isGranted
                ? Theme.of(context).colorScheme.primary
                : (status?.isDenied ?? true ? AppColors.amber : AppColors.bear),
            fontSize: 12,
          ),
        ),
      );
    }).toList();

    if (FeatureFlags.floatingOverlayEnabled) {
      list.add(
        ListTile(
          leading: const Icon(Icons.layers),
          title: const Text('Display Over Other Apps (Floating Bubble)'),
          trailing: _isOverlayPermissionGranted
              ? Icon(
                  Icons.check_circle,
                  color: Theme.of(context).colorScheme.primary,
                )
              : TextButton(
                  onPressed: () async {
                    await FlutterOverlayWindow.requestPermission();
                    final granted =
                        await FlutterOverlayWindow.isPermissionGranted();
                    setState(() {
                      _isOverlayPermissionGranted = granted;
                    });
                  },
                  child: const Text('Grant'),
                ),
          subtitle: Text(
            _isOverlayPermissionGranted ? 'Granted' : 'Not granted',
            style: TextStyle(
              color: _isOverlayPermissionGranted
                  ? Theme.of(context).colorScheme.primary
                  : AppColors.amber,
              fontSize: 12,
            ),
          ),
        ),
      );
    }

    return list;
  }

  void _openCreatorChannels(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_outline_rounded),
              title: const Text('Orailnoor'),
              subtitle: const Text('youtube.com/orailnoor'),
              onTap: () {
                Navigator.pop(sheetContext);
                launchUrl(
                  Uri.parse('https://www.youtube.com/orailnoor'),
                  mode: LaunchMode.externalApplication,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_outline_rounded),
              title: const Text('Tech Jarves'),
              subtitle: const Text('youtube.com/techjarves'),
              onTap: () {
                Navigator.pop(sheetContext);
                launchUrl(
                  Uri.parse('https://www.youtube.com/techjarves'),
                  mode: LaunchMode.externalApplication,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Set/change PIN dialog (4-6 digits, entered twice).
class _PinDialog extends StatefulWidget {
  const _PinDialog();

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final _pinController = TextEditingController();
  final _confirmController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _save() {
    final pin = _pinController.text;
    final confirm = _confirmController.text;
    if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
      setState(() => _error = 'PIN must be 4 to 6 digits.');
      return;
    }
    if (pin != confirm) {
      setState(() => _error = 'PINs do not match.');
      return;
    }
    Navigator.of(context).pop(pin);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      backgroundColor: AppColors.surfaceDark,
      title: const Text('Set a re-entry PIN'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _pinController,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'New PIN (4-6 digits)',
              counterText: '',
            ),
          ),
          const SizedBox(height: AppTokens.spaceMd),
          TextField(
            controller: _confirmController,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'Confirm PIN',
              counterText: '',
              errorText: _error,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          style: FilledButton.styleFrom(backgroundColor: scheme.primary),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
