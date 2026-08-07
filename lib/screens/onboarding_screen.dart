import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:ui';
import '../config/app_config.dart';
import '../config/theme.dart';
import '../services/ai_service.dart';
import '../widgets/auth_form.dart';
import '../widgets/logo_loader.dart';
import '../widgets/trading_avatar.dart';
import 'auth_gate.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with WidgetsBindingObserver {
  final PageController _pageController = PageController();
  final AiService _aiService = AiService();

  int _currentStep = 0;
  bool _isMicrophoneGranted = false;
  bool _isNotificationsGranted = false;
  bool _backendConfigured = false;

  // AI config states
  String _selectedProvider = 'deepseek';
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _baseUrlController = TextEditingController(
    text: 'https://api.deepseek.com',
  );
  final TextEditingController _modelController = TextEditingController(
    text: 'deepseek-chat',
  );
  bool _obscureKey = true;
  bool _isValidating = false;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAiDefaults();
    _loadBackendConfig();
    _checkPermissions();
  }

  Future<void> _loadBackendConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final storedBackend = prefs.getString('trading_backend_url') ?? '';
    final backendConfigured =
        storedBackend.trim().isNotEmpty || defaultTradingBackendUrl.isNotEmpty;
    if (mounted && backendConfigured != _backendConfigured) {
      setState(() => _backendConfigured = backendConfigured);
    }
  }

  Future<void> _loadAiDefaults() async {
    await _aiService.init();
    if (!mounted || !_aiService.isConfigured) return;
    setState(() {
      _selectedProvider = 'custom';
      _apiKeyController.text = _aiService.apiKey;
      _baseUrlController.text = _aiService.baseUrl;
      _modelController.text = _aiService.model;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
    }
  }

  Future<void> _checkPermissions() async {
    final microphoneStatus = await Permission.microphone.status;
    final notificationsStatus = await Permission.notification.status;

    if (mounted) {
      setState(() {
        _isMicrophoneGranted = microphoneStatus.isGranted;
        _isNotificationsGranted = notificationsStatus.isGranted;
      });
    }
  }

  Future<void> _requestPermission(Permission permission) async {
    await permission.request();
    _checkPermissions();
  }

  Future<void> _skipToHome() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_completed', true);
    if (!mounted) return;
    // Route through the auth gate so a fresh session lands on the PIN lock
    // (when set) or the app shell, matching every later cold start.
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const AuthGate()),
    );
  }

  void _selectProvider(String provider) {
    setState(() {
      _selectedProvider = provider;
      _validationError = null;
      if (provider == 'deepseek') {
        _baseUrlController.text = 'https://api.deepseek.com';
        _modelController.text = 'deepseek-chat';
      } else if (provider == 'groq') {
        _baseUrlController.text = 'https://api.groq.com/openai/v1';
        _modelController.text = 'llama-3.3-70b-versatile';
      } else if (provider == 'nvidia') {
        _baseUrlController.text = AiService.nvidiaBaseUrl;
        _modelController.text = AiService.nvidiaDefaultModel;
      } else if (provider == 'openrouter') {
        _baseUrlController.text = AiService.openRouterBaseUrl;
        _modelController.text = AiService.openRouterDefaultModel;
      } else if (provider == 'ollama') {
        _baseUrlController.text = 'http://10.0.2.2:11434/v1';
        _modelController.text = 'gemma2';
      } else if (provider == 'local') {
        _baseUrlController.text = 'http://10.0.2.2:1234/v1';
        _modelController.text = 'qwen2.5-7b-instruct';
      } else {
        _baseUrlController.clear();
        _modelController.clear();
      }
    });
  }

  Future<void> _testAndSave() async {
    setState(() {
      _isValidating = true;
      _validationError = null;
    });

    final apiKey = _apiKeyController.text.trim();
    final baseUrl = _baseUrlController.text.trim();
    final model = _modelController.text.trim();

    if (baseUrl.isEmpty || model.isEmpty) {
      setState(() {
        _validationError = 'Please fill out API Base URL and Model.';
        _isValidating = false;
      });
      return;
    }

    if (_selectedProvider != 'ollama' &&
        _selectedProvider != 'local' &&
        apiKey.isEmpty) {
      setState(() {
        _validationError = 'API Key is required for this provider.';
        _isValidating = false;
      });
      return;
    }

    try {
      final models = await _aiService.fetchAvailableModels(baseUrl, apiKey);
      if (models.isNotEmpty ||
          _selectedProvider == 'ollama' ||
          _selectedProvider == 'local') {
        await _aiService.saveSettings(
          apiKey: apiKey,
          baseUrl: baseUrl,
          model: model,
        );
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('onboarding_completed', true);

        if (mounted) {
          setState(() {
            _isValidating = false;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Configuration validated! Launching Neutral Pip...',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );

          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('onboarding_completed', true);
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const AuthGate()),
          );
        }
      } else {
        setState(() {
          _validationError =
              'Failed to fetch models from the server. Verify base URL and API Key.';
          _isValidating = false;
        });
      }
    } catch (e) {
      setState(() {
        _validationError =
            'Error: ${e.toString().replaceFirst('Exception: ', '')}';
        _isValidating = false;
      });
    }
  }

  Future<void> _fetchModels() async {
    final baseUrl = _baseUrlController.text.trim();
    final apiKey = _apiKeyController.text.trim();

    if (baseUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please enter an API Base URL first.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _isValidating = true;
    });

    try {
      final models = await _aiService.fetchAvailableModels(baseUrl, apiKey);

      setState(() {
        _isValidating = false;
      });

      if (models.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'No models found. Check base URL or API Key.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      if (mounted) {
        showModalBottomSheet(
          context: context,
          builder: (context) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AiService.isNvidiaBaseUrl(baseUrl)
                          ? 'Select a Free NVIDIA Model'
                          : 'Select a Model',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: ListView.builder(
                        physics: const BouncingScrollPhysics(),
                        itemCount: models.length,
                        itemBuilder: (context, index) {
                          final modelName = models[index];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                            ),
                            title: Text(
                              modelName,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                            trailing: const Icon(
                              Icons.chevron_right_rounded,
                              size: 18,
                            ),
                            onTap: () {
                              setState(() {
                                _modelController.text = modelName;
                              });
                              Navigator.pop(context);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      }
    } catch (e) {
      setState(() {
        _isValidating = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error: ${e.toString().replaceFirst('Exception: ', '')}',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  bool get _canProceedToModel => true;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          // Background fluid glow effect
          _buildBackgroundGlows(isDark),

          // Blur filter over background glows
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 120, sigmaY: 120),
              child: Container(color: Colors.transparent),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // Top Custom Animated Stepper Bar
                Padding(
                  padding: const EdgeInsets.only(
                    top: 24,
                    left: 32,
                    right: 32,
                    bottom: 8,
                  ),
                  child: _buildAnimatedStepper(isDark),
                ),

                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    onPageChanged: (page) {
                      setState(() {
                        _currentStep = page;
                      });
                    },
                    children: [
                      _buildWelcomePage(isDark),
                      if (_backendConfigured)
                        _buildAccountPage(isDark)
                      else
                        _buildPermissionsPage(isDark),
                      if (_backendConfigured)
                        _buildPermissionsPage(isDark)
                      else
                        _buildModelSetupPage(isDark),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackgroundGlows(bool isDark) {
    return Positioned.fill(
      child: Stack(
        children: [
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 350,
              height: 350,
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
            bottom: -50,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
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

  Widget _buildAnimatedStepper(bool isDark) {
    final stepTitles = _backendConfigured
        ? const ['Welcome', 'Account', 'Permissions']
        : const ['Welcome', 'Permissions', 'AI Setup'];
    final stepCount = stepTitles.length;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(stepCount, (index) {
            final isActive = _currentStep == index;
            final isCompleted = _currentStep > index;

            return AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutCubic,
              height: 6,
              width: isActive
                  ? MediaQuery.of(context).size.width * 0.35
                  : MediaQuery.of(context).size.width * 0.22,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: isActive
                    ? Theme.of(context).primaryColor
                    : isCompleted
                    ? Theme.of(context).primaryColor.withValues(alpha: 0.5)
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: Theme.of(
                            context,
                          ).primaryColor.withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
            );
          }),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < stepTitles.length; i++)
              _buildStepperLabel(i, stepTitles[i]),
          ],
        ),
      ],
    );
  }

  Widget _buildStepperLabel(int index, String text) {
    final isActive = _currentStep == index;
    final isCompleted = _currentStep > index;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Text(
      text,
      style: AppFonts.body(
        size: 12,
        weight: isActive ? FontWeight.w700 : FontWeight.w600,
        color: isActive
            ? Theme.of(context).primaryColor
            : isCompleted
            ? (isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight)
            : (isDark ? AppColors.textMutedDark : AppColors.textMutedLight),
      ),
    );
  }

  // --- STEP 1: WELCOME SCREEN ---
  Widget _buildWelcomePage(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(flex: 3),
          // Large Custom Glowing Logo Container
          Stack(
            alignment: Alignment.center,
            children: [
              // Outer Halo Glow
              Container(
                width: 170,
                height: 170,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.amber.withValues(alpha: 0.12),
                ),
              ),
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark ? AppColors.surfaceElevatedDark : Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.25 : 0.08,
                      ),
                      blurRadius: 25,
                      offset: const Offset(0, 10),
                    ),
                  ],
                  border: Border.all(
                    color: AppColors.amber.withValues(alpha: 0.35),
                    width: 1.5,
                  ),
                ),
                child: const TradingAvatar(size: 84),
              ),
            ],
          ),
          const Spacer(flex: 2),
          // Clean Title
          Text(
            'Neutral Pip',
            style: AppFonts.heading(
              size: 38,
              weight: FontWeight.w700,
              letterSpacing: -0.5,
              color: isDark
                  ? AppColors.textPrimaryDark
                  : AppColors.textPrimaryLight,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Your AI Trading Co-Pilot',
            textAlign: TextAlign.center,
            style: AppFonts.body(
              size: 15,
              height: 1.55,
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
            ),
          ),
          const Spacer(flex: 2),

          // Custom Sleek Features list
          _buildFeatureCard(
            Icons.candlestick_chart_rounded,
            'AI Chart Analysis',
            'Drop a chart screenshot or TradingView URL for an instant signal read.',
            isDark,
          ),
          const SizedBox(height: 12),
          _buildFeatureCard(
            Icons.shield_rounded,
            'Secure Trading Execution',
            'Every analysis and trade routes through a secure API — never on-device automation.',
            isDark,
          ),
          const SizedBox(height: 12),
          _buildFeatureCard(
            Icons.mic_rounded,
            'Voice Chat',
            'Speak your questions and hear the assistant read the analysis back.',
            isDark,
          ),

          const Spacer(flex: 3),
          // Get Started button
          Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: Theme.of(context).colorScheme.primary,
              boxShadow: [
                BoxShadow(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.25),
                  blurRadius: 15,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: () {
                _pageController.nextPage(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOutCubic,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: AppColors.onAmber,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Get Started',
                    style: AppFonts.body(
                      size: 16,
                      weight: FontWeight.w700,
                      letterSpacing: 0.2,
                      color: AppColors.onAmber,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    size: 20,
                    color: AppColors.onAmber,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildFeatureCard(
    IconData icon,
    String title,
    String subtitle,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.onSurface.withValues(alpha: 0.06),
          width: 1.2,
        ),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 22, color: Theme.of(context).primaryColor),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppFonts.body(
                    weight: FontWeight.w700,
                    size: 14,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 3),
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
            ),
          ),
        ],
      ),
    );
  }

  // --- STEP 2 (backend configured): ACCOUNT SCREEN ---
  Widget _buildAccountPage(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          Text(
            'Your trading account',
            style: AppFonts.heading(
              size: 24,
              weight: FontWeight.w700,
              letterSpacing: -0.5,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Your account powers chart analysis, risk management, and trade '
            'execution. Sign up once and everything is configured '
            'immediately.',
            style: AppFonts.body(
              size: 14,
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: AuthForm(
                onAuthenticated: () async {
                  if (!mounted) return;
                  _pageController.nextPage(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutCubic,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- STEP 2: PERMISSIONS SCREEN ---
  Widget _buildPermissionsPage(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          Text(
            'Configure Permissions',
            style: AppFonts.heading(
              size: 24,
              weight: FontWeight.w700,
              letterSpacing: -0.5,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'These permissions power voice chat and trading alerts. You can '
            'skip them now - when a feature needs one, we will guide you to '
            'grant it in a single tap.',
            style: AppFonts.body(
              size: 14,
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              children: [
                _buildSectionHeader('RECOMMENDED', isDark),
                _buildPermissionCard(
                  'Microphone',
                  'Required to listen to your voice commands and convert speech to text.',
                  Icons.mic_rounded,
                  _isMicrophoneGranted,
                  () => _requestPermission(Permission.microphone),
                  isDark,
                ),
                const SizedBox(height: 20),
                _buildSectionHeader('OPTIONAL', isDark),
                _buildPermissionCard(
                  'Notifications',
                  'Allows Neutral Pip to show trading alerts and assistant updates in your notification tray.',
                  Icons.notifications_rounded,
                  _isNotificationsGranted,
                  () => _requestPermission(Permission.notification),
                  isDark,
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),

          // Bottom Navigation Row
          Row(
            children: [
              TextButton(
                onPressed: () {
                  _pageController.previousPage(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutCubic,
                  );
                },
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                ),
                child: const Text(
                  'Back',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              TextButton(
                onPressed: () {
                  if (_backendConfigured) {
                    _skipToHome();
                  } else {
                    _pageController.nextPage(
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOutCubic,
                    );
                  }
                },
                child: const Text(
                  'Skip',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const Spacer(),
              Container(
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: _canProceedToModel
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  boxShadow: _canProceedToModel
                      ? [
                          BoxShadow(
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.25),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: ElevatedButton(
                  onPressed: _canProceedToModel
                      ? () {
                          if (_backendConfigured) {
                            _skipToHome();
                          } else {
                            _pageController.nextPage(
                              duration: const Duration(milliseconds: 400),
                              curve: Curves.easeOutCubic,
                            );
                          }
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: AppColors.onAmber,
                    shadowColor: Colors.transparent,
                    disabledForegroundColor: isDark
                        ? AppColors.textMutedDark
                        : AppColors.textMutedLight,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                  ),
                  child: Row(
                    children: [
                      Text(
                        _backendConfigured ? 'Continue' : 'Next',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward_rounded, size: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4, left: 4),
      child: Text(
        title,
        style: AppFonts.body(
          size: 11,
          weight: FontWeight.w800,
          letterSpacing: 1.5,
          color: isDark
              ? AppColors.textSecondaryDark
              : AppColors.textSecondaryLight,
        ),
      ),
    );
  }

  Widget _buildPermissionCard(
    String title,
    String description,
    IconData icon,
    bool isGranted,
    VoidCallback onGrant,
    bool isDark,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isGranted
              ? AppColors.bull.withValues(alpha: 0.3)
              : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).primaryColor.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      icon,
                      size: 20,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      title,
                      style: AppFonts.body(
                        weight: FontWeight.w700,
                        size: 14,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                  if (isGranted)
                    const Icon(
                      Icons.check_circle_rounded,
                      color: AppColors.bull,
                      size: 24,
                    )
                  else
                    ElevatedButton(
                      onPressed: onGrant,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: AppColors.onAmber,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        minimumSize: const Size(60, 36),
                      ),
                      child: Text(
                        'Grant',
                        style: AppFonts.body(
                          size: 12,
                          weight: FontWeight.w700,
                          color: AppColors.onAmber,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                description,
                style: AppFonts.body(
                  size: 12.5,
                  height: 1.45,
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- STEP 3: MODEL SETUP SCREEN ---
  Widget _buildModelSetupPage(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          Text(
            'Configure AI Model',
            style: AppFonts.heading(
              size: 24,
              weight: FontWeight.w700,
              letterSpacing: -0.5,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Select a provider to prefill API details automatically. This '
            'powers chat as a fallback — when a trading backend is connected, '
            'it uses the backend\'s own AI.',
            style: AppFonts.body(
              size: 13,
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
            ),
          ),
          const SizedBox(height: 20),

          // Providers Grid/List
          SizedBox(
            height: 90,
            child: ListView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              children: [
                _buildProviderCard(
                  'deepseek',
                  'DeepSeek',
                  Icons.analytics_rounded,
                  isDark,
                ),
                const SizedBox(width: 10),
                _buildProviderCard('groq', 'Groq', Icons.speed_rounded, isDark),
                const SizedBox(width: 10),
                _buildProviderCard(
                  'nvidia',
                  'NVIDIA',
                  Icons.memory_rounded,
                  isDark,
                ),
                const SizedBox(width: 10),
                _buildProviderCard(
                  'openrouter',
                  'OpenRouter',
                  Icons.router_rounded,
                  isDark,
                ),
                const SizedBox(width: 10),
                _buildProviderCard(
                  'ollama',
                  'Ollama',
                  Icons.computer_rounded,
                  isDark,
                ),
                const SizedBox(width: 10),
                _buildProviderCard(
                  'local',
                  'Local Server',
                  Icons.dns_rounded,
                  isDark,
                ),
                const SizedBox(width: 10),
                _buildProviderCard(
                  'custom',
                  'Custom',
                  Icons.settings_suggest_rounded,
                  isDark,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          Expanded(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              children: [
                if (_selectedProvider != 'ollama' &&
                    _selectedProvider != 'local') ...[
                  _buildFormTextField(
                    controller: _apiKeyController,
                    label: 'API Key',
                    hint: 'sk-xxxxxxxxxxxx',
                    obscure: _obscureKey,
                    isDark: isDark,
                    suffix: IconButton(
                      icon: Icon(
                        _obscureKey
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        color: AppColors.textSecondaryDark,
                      ),
                      onPressed: () =>
                          setState(() => _obscureKey = !_obscureKey),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                _buildFormTextField(
                  controller: _baseUrlController,
                  label: 'API Base URL',
                  hint: 'https://api.deepseek.com',
                  isDark: isDark,
                ),
                const SizedBox(height: 16),
                _buildFormTextField(
                  controller: _modelController,
                  label: 'Model Name',
                  hint: 'deepseek-chat',
                  isDark: isDark,
                  suffix: IconButton(
                    icon: _isValidating
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: LogoLoader(
                              size: 18,
                              strokeWidth: 2,
                              showGlow: false,
                              ringColor: Theme.of(context).colorScheme.onSurface,
                            ),
                          )
                        : Icon(
                            Icons.sync_rounded,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                    tooltip: 'Fetch models list',
                    onPressed: _isValidating ? null : _fetchModels,
                  ),
                ),

                if (_validationError != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.bear.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.bear.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Text(
                      _validationError!,
                      style: AppFonts.body(
                        size: 13,
                        height: 1.4,
                        color: AppColors.bear,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 32),
              ],
            ),
          ),

          // Action Buttons Row
          Row(
            children: [
              TextButton(
                onPressed: _isValidating
                    ? null
                    : () {
                        _pageController.previousPage(
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeOutCubic,
                        );
                      },
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                ),
                child: const Text(
                  'Back',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              TextButton(
                onPressed: _isValidating ? null : _skipToHome,
                child: const Text(
                  'Skip for now',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const Spacer(),
              Container(
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: _isValidating
                      ? Theme.of(context).colorScheme.surfaceContainerHighest
                      : Theme.of(context).colorScheme.primary,
                  boxShadow: _isValidating
                      ? null
                      : [
                          BoxShadow(
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.25),
                            blurRadius: 12,
                            offset: const Offset(0, 5),
                          ),
                        ],
                ),
                child: ElevatedButton(
                  onPressed: _isValidating ? null : _testAndSave,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: AppColors.onAmber,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                  ),
                  child: _isValidating
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: LogoLoader(
                            size: 22,
                            strokeWidth: 2.5,
                            showGlow: false,
                            ringColor: AppColors.onAmber,
                          ),
                        )
                      : const Row(
                          children: [
                            Text(
                              'Finish Setup',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            SizedBox(width: 8),
                            Icon(Icons.check_circle_outline_rounded, size: 20),
                          ],
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildProviderCard(
    String id,
    String label,
    IconData icon,
    bool isDark,
  ) {
    final isSelected = _selectedProvider == id;

    return Container(
      width: 104,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08),
          width: isSelected ? 2 : 1.2,
        ),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.15),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Card(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        color: isSelected
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
            : Theme.of(context).colorScheme.surface,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _selectProvider(id),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 26,
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : (Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppFonts.body(
                  size: 11,
                  weight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : (Theme.of(context).colorScheme.onSurface),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFormTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    bool obscure = false,
    Widget? suffix,
    required bool isDark,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.onSurface.withValues(alpha: 0.08),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.02),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        style: AppFonts.body(size: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: AppFonts.body(
            size: 13,
            color: isDark
                ? AppColors.textSecondaryDark
                : AppColors.textSecondaryLight,
          ),
          hintText: hint,
          hintStyle: AppFonts.body(
            size: 13,
            color: Theme.of(
              context,
            ).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 16,
          ),
          border: InputBorder.none,
          suffixIcon: suffix,
        ),
      ),
    );
  }
}
