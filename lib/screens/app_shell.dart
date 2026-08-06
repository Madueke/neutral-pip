import 'dart:async';
import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/home_quick_action.dart';
import '../services/ai_service.dart';
import '../services/telegram_service.dart';
import '../services/trading_api_service.dart';
import '../services/voice_service.dart';
import '../services/notification_service.dart';
import 'home_screen.dart';
import 'home_dashboard.dart';
import 'journal_screen.dart';
import 'risk_dashboard_screen.dart';
import 'settings_screen.dart';

/// Top-level shell: owns the shared service instances and hosts the five
/// primary tabs behind a floating bottom navigation bar.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _tabIndex = 0;

  // Shared service instances — one per app lifetime, passed to every tab so
  // settings changes propagate everywhere.
  final AiService _aiService = AiService();
  final VoiceService _voiceService = VoiceService();
  final NotificationService _notificationService = NotificationService();
  late final TelegramService _telegramService;
  late final TradingApiService _tradingApiService;

  final GlobalKey<HomeScreenState> _homeKey = GlobalKey<HomeScreenState>();

  static const List<_TabSpec> _tabs = [
    _TabSpec(Icons.home_rounded, 'Home'),
    _TabSpec(Icons.auto_awesome_rounded, 'Analysis'),
    _TabSpec(Icons.menu_book_rounded, 'Journal'),
    _TabSpec(Icons.shield_rounded, 'Risk'),
    _TabSpec(Icons.settings_rounded, 'Settings'),
  ];

  @override
  void initState() {
    super.initState();
    _tradingApiService = TradingApiService(_aiService);
    _telegramService = TelegramService(_aiService, _tradingApiService);
    _initServices();
  }

  Future<void> _initServices() async {
    await _aiService.init();
    await _notificationService.requestPermission();
    await _voiceService.init();
    await _telegramService.init();
    await _tradingApiService.init();
    if (mounted) setState(() {});
  }

  void _goToTab(int index) {
    if (index == _tabIndex) return;
    setState(() => _tabIndex = index);
  }

  void _handleQuickAction(HomeQuickAction action) {
    switch (action) {
      case HomeQuickAction.askAi:
        _goToTab(1);
      case HomeQuickAction.pasteUrl:
        _goToTab(1);
        _homeKey.currentState?.runQuickAction(action);
      case HomeQuickAction.upload:
        _homeKey.currentState?.runQuickAction(action);
        _goToTab(1);
      case HomeQuickAction.voice:
        _goToTab(1);
        _homeKey.currentState?.runQuickAction(action);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          Positioned.fill(
            child: IndexedStack(
              index: _tabIndex,
              children: [
                HomeDashboard(
                  tradingApiService: _tradingApiService,
                  onQuickAction: _handleQuickAction,
                ),
                HomeScreen(
                  key: _homeKey,
                  aiService: _aiService,
                  voiceService: _voiceService,
                  notificationService: _notificationService,
                  telegramService: _telegramService,
                  tradingApiService: _tradingApiService,
                  onOpenSettings: () => _goToTab(4),
                ),
                JournalScreen(tradingApiService: _tradingApiService),
                RiskDashboardScreen(tradingApiService: _tradingApiService),
                SettingsScreen(
                  aiService: _aiService,
                  telegramService: _telegramService,
                  tradingApiService: _tradingApiService,
                ),
              ],
            ),
          ),
          _buildFloatingNav(context),
        ],
      ),
    );
  }

  Widget _buildFloatingNav(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;

    return Positioned(
      left: AppTokens.spaceXl,
      right: AppTokens.spaceXl,
      bottom: AppTokens.spaceLg,
      child: Container(
        height: 68,
        decoration: BoxDecoration(
          color: bg.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(AppTokens.radiusPill),
          border: Border.all(
            color: isDark ? AppColors.borderDark : AppColors.borderLight,
            width: AppTokens.borderWidth,
          ),
          boxShadow: [
            ...AppShadows.card,
            BoxShadow(
              color: AppColors.amber.withValues(
                alpha: isDark ? 0.08 : 0.04,
              ),
              blurRadius: 32,
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            for (var i = 0; i < _tabs.length; i++)
              _buildNavItem(context, i),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(BuildContext context, int index) {
    final spec = _tabs[index];
    final selected = _tabIndex == index;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: spec.label,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTokens.radiusPill),
          onTap: () => _goToTab(index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTokens.radiusPill),
              color: selected
                  ? AppColors.amber.withValues(alpha: 0.16)
                  : Colors.transparent,
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: AppColors.amber.withValues(
                          alpha: isDark ? 0.35 : 0.2,
                        ),
                        blurRadius: 18,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  spec.icon,
                  size: 24,
                  color: selected ? AppColors.amber : _muted(context),
                ),
                const SizedBox(height: 3),
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: selected ? 1 : 0.55,
                  child: Text(
                    spec.label,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: selected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: selected
                          ? AppColors.amber
                          : _muted(context),
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _muted(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondaryLight;
  }
}

class _TabSpec {
  final IconData icon;
  final String label;
  const _TabSpec(this.icon, this.label);
}
