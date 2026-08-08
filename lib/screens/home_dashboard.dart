import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/theme.dart';
import '../models/home_quick_action.dart';
import '../models/trade_signal.dart';
import '../services/trading_api_service.dart'
  show TradingApiService; // avoid importing TradeSignal from here
import '../widgets/app_animations.dart';
import '../widgets/candle_sparkline.dart';
import '../widgets/trading_avatar.dart';
import 'chart_screen.dart';

/// Dashboard home: briefing, market pulse, watchlist, signals, and quick
/// actions. Presentational data is clearly marked; real data (recent
/// analyses) is read from the task history log.
class HomeDashboard extends StatefulWidget {
  final TradingApiService tradingApiService;
  final void Function(HomeQuickAction action) onQuickAction;
  final VoidCallback? onOpenSettings;
  final void Function(int tabIndex)? onGoToTab;

  const HomeDashboard({
    super.key,
    required this.tradingApiService,
    required this.onQuickAction,
    this.onOpenSettings,
    this.onGoToTab,
  });

  @override
  State<HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<HomeDashboard> {
  // --- Live data state ---
  List<Map<String, dynamic>> _recentAnalyses = const [];
  List<_WatchItem> _watchlist = const [];
  List<Map<String, dynamic>> _liveSignals = const [];
  Map<String, dynamic>? _briefing;
  Map<String, dynamic>? _accountSummary;

  // Loading/error states for each section
  bool _loading = true;
  bool _loadingQuotes = false;
  bool _loadingSignals = false;
  bool _loadingBriefing = false;
  bool _loadingAccount = false;
  String? _quotesError;
  String? _signalsError;
  String? _briefingError;
  String? _accountError;

  // Live market data
  Timer? _quoteTimer;
  final Map<String, Map<String, dynamic>> _liveQuotes = {};
  final Map<String, DateTime> _quoteTimestamps = {};
  bool _hasUnreadActivity = true;
  String _preferredTimeframe = 'H1';
  static const Duration _staleThreshold = Duration(seconds: 30);
  static const Duration _quotePollInterval = Duration(seconds: 10);

  @override
  void initState() {
    super.initState();
    _load();
    _refreshQuotes();
    _quoteTimer = Timer.periodic(_quotePollInterval, (_) => _refreshQuotes());
  }

  @override
  void dispose() {
    _quoteTimer?.cancel();
    super.dispose();
  }

  /// Load all live data for the dashboard.
  Future<void> _load() async {
    setState(() => _loading = true);

    // Load watchlist symbols from local storage (same as chart screen)
    final prefs = await SharedPreferences.getInstance();
    final storedSymbols = prefs.getStringList('watchlist_symbols');
    final storedTimeframes = prefs.getStringList('watchlist_timeframes');
    _preferredTimeframe = (storedTimeframes != null && storedTimeframes.isNotEmpty)
        ? storedTimeframes.first
        : 'H1';

    // Build _WatchItem list from stored symbols (with fallback defaults)
    final symbols = (storedSymbols != null && storedSymbols.isNotEmpty)
        ? storedSymbols
        : const ['EURUSD', 'XAUUSD', 'BTCUSD', 'ETHUSD', 'NAS100'];

    _watchlist = symbols.map((s) => _WatchItem.fromSymbol(s)).toList();

    if (!mounted) return;

    // Fetch all live data in parallel
    await Future.wait([
      _fetchSignals(),
      _fetchBriefing(),
      _fetchAccountSummary(),
    ]);

    if (!mounted) return;
    setState(() => _loading = false);
  }

  /// Fetch live quotes for all watchlist symbols using the batch endpoint.
  Future<void> _refreshQuotes() async {
    if (!widget.tradingApiService.isConfigured) return;
    if (_watchlist.isEmpty) return;

    setState(() {
      _loadingQuotes = true;
      _quotesError = null;
    });

    try {
      final result = await widget.tradingApiService.getWatchlistPrices();
      if (!mounted) return;
      if (result['status'] == 'error') {
        setState(() => _quotesError = result['message'] as String? ?? 'Failed to load quotes');
      } else if (result['quotes'] is List) {
        final quotes = (result['quotes'] as List).cast<Map<String, dynamic>>();
        for (final q in quotes) {
          if (q['status'] == 'ok' && q['symbol'] is String) {
            setState(() {
              _liveQuotes[q['symbol'] as String] = q;
              _quoteTimestamps[q['symbol'] as String] = DateTime.now();
            });
          }
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _quotesError = e.toString());
    } finally {
      if (mounted) setState(() => _loadingQuotes = false);
    }
  }

  Future<void> _fetchSignals() async {
    setState(() {
      _loadingSignals = true;
      _signalsError = null;
    });
    try {
      final result = await widget.tradingApiService.getWatchlistSignals();
      if (!mounted) return;
      if (result['status'] == 'error') {
        setState(() => _signalsError = result['message'] as String? ?? 'Failed to load signals');
      } else if (result['signals'] is List) {
        setState(() => _liveSignals = (result['signals'] as List).cast<Map<String, dynamic>>());
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _signalsError = e.toString());
    } finally {
      if (mounted) setState(() => _loadingSignals = false);
    }
  }

  Future<void> _fetchBriefing() async {
    setState(() {
      _loadingBriefing = true;
      _briefingError = null;
    });
    try {
      final result = await widget.tradingApiService.getDailyBriefing();
      if (!mounted) return;
      if (result['status'] == 'error') {
        setState(() => _briefingError = result['message'] as String? ?? 'Failed to load briefing');
      } else {
        setState(() => _briefing = result);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _briefingError = e.toString());
    } finally {
      if (mounted) setState(() => _loadingBriefing = false);
    }
  }

  Future<void> _fetchAccountSummary() async {
    setState(() {
      _loadingAccount = true;
      _accountError = null;
    });
    try {
      final result = await widget.tradingApiService.getAccountSummary();
      if (!mounted) return;
      if (result['status'] == 'error') {
        setState(() => _accountError = result['message'] as String? ?? 'Failed to load account');
      } else {
        setState(() => _accountSummary = result);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _accountError = e.toString());
    } finally {
      if (mounted) setState(() => _loadingAccount = false);
    }
  }

  /// Trigger a fresh analysis run for all watchlist symbols.
  Future<void> _refreshAllSignals() async {
    if (!widget.tradingApiService.isConfigured) return;
    setState(() {
      _loadingSignals = true;
      _signalsError = null;
    });
    try {
      final result = await widget.tradingApiService.refreshWatchlistSignals();
      if (!mounted) return;
      if (result['status'] == 'error') {
        setState(() => _signalsError = result['message'] as String? ?? 'Refresh failed');
      } else if (result['signals'] is List) {
        setState(() => _liveSignals = (result['signals'] as List).cast<Map<String, dynamic>>());
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _signalsError = e.toString());
    } finally {
      if (mounted) setState(() => _loadingSignals = false);
    }
  }

  /// Open the live TradingView chart for a watchlist symbol.
  Future<void> _openChart(_WatchItem item) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ChartScreen(
          initialSymbol: item.symbol,
          initialTimeframe: _preferredTimeframe,
        ),
      ),
    );
  }

  /// Whether a symbol has a fresh live quote (not older than [_staleThreshold]).
  bool _isQuoteFresh(String symbol) {
    final ts = _quoteTimestamps[symbol];
    if (ts == null) return false;
    return DateTime.now().difference(ts) < _staleThreshold;
  }

  /// Get live quote for a symbol if fresh; null if missing or stale.
  Map<String, dynamic>? _getFreshQuote(String symbol) {
    final q = _liveQuotes[symbol];
    if (q == null || q['status'] != 'ok') return null;
    return _isQuoteFresh(symbol) ? q : null;
  }

  Future<void> _openDefaultChart() async {
    final symbols = await loadWatchlistSymbols();
    final timeframe = await loadPreferredTimeframe();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ChartScreen(
          initialSymbol: symbols.first,
          initialTimeframe: timeframe,
        ),
      ),
    );
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  /// Open the activity sheet (journal entries + auto-execute status) and
  /// clear the unread dot.
  Future<void> _openActivitySheet() async {
    setState(() => _hasUnreadActivity = false);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ActivitySheet(
        tradingApiService: widget.tradingApiService,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Scaffold(
      backgroundColor: Colors.transparent,
      // Upper navigation bar matching the Analysis screen's AppBar: menu,
      // brand avatar + title, and the same action affordances.
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const TradingAvatar(size: 32),
            const SizedBox(width: AppTokens.spaceSm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Neutral Pip',
                  style: AppFonts.heading(
                    size: 17,
                    weight: FontWeight.w700,
                    letterSpacing: -0.3,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                Text(
                  'AI Trading Co-Pilot',
                  style: AppFonts.body(
                    size: 10,
                    weight: FontWeight.w600,
                    letterSpacing: 0.4,
                    color: AppColors.amber,
                  ),
                ),
              ],
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
          // Activity bell with unread dot.
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                onPressed: _openActivitySheet,
                icon: const Icon(Icons.notifications_rounded, size: 20),
                tooltip: 'Activity',
              ),
              if (_hasUnreadActivity)
                Positioned(
                  top: 9,
                  right: 9,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.amber,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.candlestick_chart_rounded),
            tooltip: 'Live chart',
            onPressed: _openDefaultChart,
          ),
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            tooltip: 'Settings',
            onPressed: () => widget.onOpenSettings?.call(),
          ),
        ],
      ),
      drawer: _buildDrawer(context, isDark),
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            _buildGlows(isDark),
            ListView(
              // The shell reserves space for the floating nav, so the list
              // only needs a small closing gap of its own.
              padding: const EdgeInsets.fromLTRB(
                AppTokens.spaceXl,
                AppTokens.spaceLg,
                AppTokens.spaceXl,
                AppTokens.spaceXl,
              ),
              children: [
                FadeInUp(child: _buildHeader(isDark, secondary)),
                const SizedBox(height: AppTokens.spaceXl),
                FadeInUp(
                  delay: const Duration(milliseconds: 80),
                  child: _buildHeroStat(isDark),
                ),
                const SizedBox(height: AppTokens.spaceXl),
                FadeInUp(
                  delay: const Duration(milliseconds: 120),
                  child: _buildQuickActions(isDark),
                ),
                const SizedBox(height: AppTokens.spaceXxl),
                FadeInUp(
                  delay: const Duration(milliseconds: 160),
                  child: _buildBriefingCard(context),
                ),
                const SizedBox(height: AppTokens.spaceXl),
                FadeInUp(
                  delay: const Duration(milliseconds: 200),
                  child: _buildStatGrid(isDark),
                ),
                const SizedBox(height: AppTokens.spaceXxl),
                FadeInUp(
                  delay: const Duration(milliseconds: 240),
                  child: _buildWatchlistTitle(secondary),
                ),
                const SizedBox(height: AppTokens.spaceLg),
                FadeInUp(
                  delay: const Duration(milliseconds: 280),
                  child: _buildWatchlist(isDark),
                ),
                const SizedBox(height: AppTokens.spaceXxl),
                FadeInUp(
                  delay: const Duration(milliseconds: 320),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildSectionTitle('Latest signals', secondary),
                      if (widget.tradingApiService.isConfigured)
                        TextButton.icon(
                          onPressed: _loadingSignals ? null : _refreshAllSignals,
                          icon: _loadingSignals
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.refresh_rounded, size: 16),
                          label: Text(_loadingSignals ? 'Refreshing...' : 'Refresh'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.amber,
                            textStyle: AppFonts.body(size: 11, weight: FontWeight.w600),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppTokens.spaceLg),
                _buildSignalsList(isDark),
                const SizedBox(height: AppTokens.spaceXl),
                FadeInUp(
                  child: _buildSectionTitle('Recent analyses', secondary),
                ),
                const SizedBox(height: AppTokens.spaceLg),
                FadeInUp(child: _buildRecentAnalyses(isDark)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlows(bool isDark) {
    if (!isDark) return const SizedBox.shrink();
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-0.9, -0.9),
              radius: 1.1,
              colors: [
                AppColors.amber.withValues(alpha: 0.07),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark, Color secondary) {
    // The brand block (avatar + Neutral Pip / AI Trading Co-Pilot) and the
    // activity bell now live in the AppBar; this header keeps the greeting
    // and the live market status chip.
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _greeting,
                style: AppFonts.body(
                  size: AppTokens.bodySize,
                  color: secondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                "Today's briefing",
                style: AppFonts.heading(
                  size: AppTokens.headlineSize,
                  weight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        _MarketStatusChip(isDark: isDark),
      ],
    );
  }

  /// The single dominant number on Home (Bybit "Total Assets" pattern):
  /// small label above, huge bold value, then a green/red change line.
  /// Falls back to a balance derived from the account summary when the
  /// backend is connected, otherwise shows Daily P/L or a neutral state.
  Widget _buildHeroStat(bool isDark) {
    final connected = _accountSummary?['connected'] == true;
    final isLoading = _loadingAccount;
    final hasError = _accountError != null;

    // Prefer account equity/balance as the primary stat when available.
    final rawBalance = _accountSummary?['balance'];
    final rawEquity = _accountSummary?['equity'];
    final num? equity = rawEquity is num
        ? rawEquity
        : (rawBalance is num ? rawBalance : null);
    final dailyPL = _accountSummary?['dailyPLPercent'] as num? ?? 0.0;
    final plColor = dailyPL >= 0 ? AppColors.bull : AppColors.bear;
    final plPrefix = dailyPL >= 0 ? '+' : '';

    String heroLabel;
    String heroValue;
    String heroChange;
    String heroChangeHint;
    Color changeColor;

    if (!connected && !isLoading && !hasError) {
      // No live account: show the daily P/L as the focal stat with a
      // neutral "connect" hint instead of a phantom balance.
      heroLabel = 'Daily P/L';
      heroValue = isLoading ? '—' : '$plPrefix${dailyPL.toStringAsFixed(2)}%';
      heroChange = 'Connect an account to see live P/L';
      heroChangeHint = '';
      changeColor = plColor;
    } else if (equity != null) {
      heroLabel = connected ? 'Account equity' : 'Account equity';
      heroValue = _fmtCurrency(equity.toDouble());
      heroChange = '${plPrefix}${dailyPL.toStringAsFixed(2)}% today';
      heroChangeHint = connected ? '● Live' : '● Stale';
      changeColor = plColor;
    } else {
      heroLabel = 'Daily P/L';
      heroValue = isLoading ? '—' : '$plPrefix${dailyPL.toStringAsFixed(2)}%';
      heroChange = 'No equity data yet';
      heroChangeHint = '';
      changeColor = plColor;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppTokens.spaceXl,
        AppTokens.spaceXxl,
        AppTokens.spaceXl,
        AppTokens.spaceXxl,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTokens.radiusCardLg),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [AppColors.surfaceElevatedDark, AppColors.surfaceDark]
              : const [Color(0xFFFFFFFF), Color(0xFFF4F6FA)],
        ),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            heroLabel.toUpperCase(),
            style: AppFonts.body(
              size: AppTokens.fontSizeTiny,
              weight: FontWeight.w700,
              letterSpacing: 1.2,
              color: isDark
                  ? AppColors.textMutedDark
                  : AppColors.textMutedLight,
            ),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          Text(
            heroValue,
            style: AppFonts.heading(
              size: 40,
              weight: FontWeight.w700,
              letterSpacing: -1.5,
              height: 1.05,
            ),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          Row(
            children: [
              Icon(
                Icons.trending_up_rounded,
                size: 16,
                color: changeColor,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  heroChange,
                  style: AppFonts.body(
                    size: AppTokens.bodySize,
                    weight: FontWeight.w600,
                    color: changeColor,
                  ),
                ),
              ),
              if (heroChangeHint.isNotEmpty) ...[
                const SizedBox(width: AppTokens.spaceSm),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.spaceSm,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.bull.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                  ),
                  child: Text(
                    heroChangeHint,
                    style: AppFonts.body(
                      size: AppTokens.fontSizeTiny,
                      weight: FontWeight.w700,
                      color: AppColors.bull,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// Format a monetary value compactly (e.g. 128,450.00 -> $128,450).
  static String _fmtCurrency(double v) {
    final negative = v < 0;
    final abs = v.abs();
    String out;
    if (abs >= 1000000) {
      out = '\$${(abs / 1000000).toStringAsFixed(2)}M';
    } else if (abs >= 1000) {
      out = '\$${(abs / 1000).toStringAsFixed(2)}k';
    } else {
      out = '\$${abs.toStringAsFixed(2)}';
    }
    return negative ? '-$out' : out;
  }

  /// Side navigation drawer mirroring the Analysis screen's drawer: same
  /// brand header, then a nav list routed through the shell's tab switcher.
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
    final iconColor = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondaryLight;

    void goTo(int tab) {
      Navigator.pop(context); // Close the drawer
      widget.onGoToTab?.call(tab);
    }

    return Drawer(
      backgroundColor: drawerBg,
      child: Column(
        children: [
          // Drawer header — same brand block as the Analysis screen's drawer.
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
                  Icons.candlestick_chart_rounded,
                  color: Theme.of(context).primaryColor,
                  size: 26,
                ),
                const SizedBox(width: 12),
                Text('Neutral Pip', style: headerStyle),
              ],
            ),
          ),
          const Divider(indent: 16, endIndent: 16, height: 20),
          ListTile(
            horizontalTitleGap: 8,
            leading: Icon(
              Icons.home_rounded,
              color: iconColor,
              size: 20,
            ),
            title: Text('Dashboard', style: textStyle),
            onTap: () => goTo(0),
          ),
          ListTile(
            horizontalTitleGap: 8,
            leading: Icon(
              Icons.candlestick_chart_rounded,
              color: iconColor,
              size: 20,
            ),
            title: Text('Analysis', style: textStyle),
            onTap: () => goTo(1),
          ),
          ListTile(
            horizontalTitleGap: 8,
            leading: Icon(
              Icons.menu_book_rounded,
              color: iconColor,
              size: 20,
            ),
            title: Text('Journal', style: textStyle),
            onTap: () => goTo(2),
          ),
          ListTile(
            horizontalTitleGap: 8,
            leading: Icon(
              Icons.shield_rounded,
              color: iconColor,
              size: 20,
            ),
            title: Text('Risk', style: textStyle),
            onTap: () => goTo(3),
          ),
          const Divider(indent: 16, endIndent: 16, height: 20),
          ListTile(
            horizontalTitleGap: 8,
            leading: Icon(
              Icons.settings_rounded,
              color: iconColor,
              size: 20,
            ),
            title: Text('Settings', style: textStyle),
            onTap: () => goTo(4),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildBriefingCard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final briefingText = _briefing?['text'] as String?;
    final isLoading = _loadingBriefing;
    final hasError = _briefingError != null;
    final displayText = hasError
        ? 'Briefing unavailable: $_briefingError'
        : (briefingText?.isNotEmpty == true
            ? briefingText!
            : (isLoading ? 'Loading briefing...' : 'No briefing available. Connect a watchlist to get started.'));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTokens.radiusCardLg),
        onTap: () => widget.onQuickAction(HomeQuickAction.askAi),
        child: Ink(
          padding: const EdgeInsets.all(AppTokens.spaceXl),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTokens.radiusCardLg),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF1C1C20),
                Color(0xFF131316),
              ],
            ),
            border: hasError
                ? Border.all(
                    color: AppColors.bear.withValues(alpha: 0.5),
                  )
                : null,
            boxShadow: AppShadows.card,
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: hasError
                      ? AppColors.bear.withValues(alpha: 0.14)
                      : AppColors.surfaceElevatedDark,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: hasError
                    ? const Icon(Icons.error_outline_rounded, color: AppColors.bear, size: 22)
                    : (isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.amber),
                          )
                        : Icon(Icons.auto_awesome_rounded, color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight, size: 22)),
              ),
              const SizedBox(width: AppTokens.spaceLg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Today's AI Briefing",
                      style: AppFonts.heading(
                        size: 15,
                        weight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      displayText,
                      style: AppFonts.body(
                        size: AppTokens.captionSize,
                        color: hasError
                            ? AppColors.bear
                            : AppColors.textSecondaryDark,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textSecondaryDark,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatGrid(bool isDark) {
    final connected = _accountSummary?['connected'] == true;
    final simulation = _accountSummary?['simulation'] == true;
    final openTrades = _accountSummary?['openTrades'] as int? ?? 0;
    final riskUsed = _accountSummary?['riskUsedPercent'] as int? ?? 0;
    final dailyPL = _accountSummary?['dailyPLPercent'] as double? ?? 0.0;
    final health = _accountSummary?['health'] as int? ?? 0;
    final isLoading = _loadingAccount;
    final hasError = _accountError != null;

    if (!connected && !isLoading && !hasError) {
      return _buildDisconnectedStatGrid(isDark);
    }

    final dailyPLColor = dailyPL >= 0 ? AppColors.bull : AppColors.bear;
    final dailyPLPrefix = dailyPL >= 0 ? '+' : '';

    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: 'Open trades',
            value: isLoading ? '—' : openTrades.toString(),
            icon: Icons.layers_rounded,
            accent: AppColors.textMutedDark,
            isLoading: isLoading,
          ),
        ),
        const SizedBox(width: AppTokens.spaceMd),
        Expanded(
          child: _StatCard(
            label: 'Risk used',
            value: isLoading ? '—' : '$riskUsed%',
            icon: Icons.speed_rounded,
            accent: riskUsed > 80 ? AppColors.bear : AppColors.warning,
            isLoading: isLoading,
          ),
        ),
        const SizedBox(width: AppTokens.spaceMd),
        Expanded(
          child: _StatCard(
            label: 'Daily P/L',
            value: isLoading ? '—' : '$dailyPLPrefix${dailyPL.toStringAsFixed(2)}%',
            icon: Icons.trending_up_rounded,
            accent: dailyPLColor,
            isLoading: isLoading,
          ),
        ),
        const SizedBox(width: AppTokens.spaceMd),
        Expanded(
          child: _StatCard(
            label: 'Health',
            value: isLoading ? '—' : health.toString(),
            icon: Icons.favorite_rounded,
            accent: health >= 70 ? AppColors.bull : (health >= 40 ? AppColors.warning : AppColors.bear),
            isLoading: isLoading,
            subtitle: simulation ? 'Simulation' : null,
          ),
        ),
      ],
    );
  }

  Widget _buildDisconnectedStatGrid(bool isDark) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: 'Open trades',
            value: '—',
            icon: Icons.layers_rounded,
            accent: AppColors.textMutedDark,
            subtitle: 'Connect MT5',
          ),
        ),
        const SizedBox(width: AppTokens.spaceMd),
        Expanded(
          child: _StatCard(
            label: 'Risk used',
            value: '—',
            icon: Icons.speed_rounded,
            accent: AppColors.textMutedDark,
            subtitle: 'Connect MT5',
          ),
        ),
        const SizedBox(width: AppTokens.spaceMd),
        Expanded(
          child: _StatCard(
            label: 'Daily P/L',
            value: '—',
            icon: Icons.trending_up_rounded,
            accent: AppColors.textMutedDark,
            subtitle: 'Connect MT5',
          ),
        ),
        const SizedBox(width: AppTokens.spaceMd),
        Expanded(
          child: _StatCard(
            label: 'Health',
            value: '—',
            icon: Icons.favorite_rounded,
            accent: AppColors.textMutedDark,
            subtitle: 'Connect MT5',
          ),
        ),
      ],
    );
  }

  Widget _buildSignalsList(bool isDark) {
    if (_signalsError != null) {
      return _SignalsErrorCard(
        message: 'Failed to load signals: $_signalsError',
        onRetry: _refreshAllSignals,
      );
    }

    if (_liveSignals.isEmpty && !_loadingSignals) {
      return _SignalsEmptyCard(
        message: widget.tradingApiService.isConfigured
            ? 'No signals match your strategy right now. Pull to refresh or wait for the next analysis cycle.'
            : 'Connect a TradingView watchlist to get live signals.',
        onConfigure: widget.tradingApiService.isConfigured ? null : () => widget.onQuickAction(HomeQuickAction.askAi),
      );
    }

    return Column(
      children: [
        for (int i = 0; i < _liveSignals.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppTokens.spaceLg),
            child: FadeInUp(
              delay: Duration(milliseconds: 100 * i),
              child: _buildSignalCard(_liveSignals[i], isDark),
            ),
          ),
        if (_loadingSignals)
          Padding(
            padding: const EdgeInsets.all(AppTokens.spaceMd),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.amber.withValues(alpha: 0.7),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSignalCard(Map<String, dynamic> data, bool isDark) {
    // Convert live signal data to TradeSignal for the TradeCard widget
    final signal = TradeSignal(
      pair: data['pair'] as String? ?? 'UNKNOWN',
      timeframe: data['timeframe'] as String? ?? 'H1',
      bias: (data['bias'] as String? ?? 'NEUTRAL').toUpperCase(),
      entry: (data['entry'] as num?)?.toDouble() ?? 0.0,
      stopLoss: (data['stopLoss'] as num?)?.toDouble() ?? 0.0,
      takeProfit: (data['takeProfit'] as num?)?.toDouble() ?? 0.0,
      riskPercent: (data['riskPercent'] as num?)?.toDouble() ?? 0.0,
      riskReward: (data['riskReward'] as num?)?.toDouble() ?? 0.0,
      confidence: (data['confidence'] as int?) ?? 0,
      confidenceReason: data['confidenceReason'] as String? ?? '',
      marketStructure: data['marketStructure'] as String? ?? '',
      liquidity: data['liquidity'] as String? ?? '',
      trend: data['trend'] as String? ?? '',
      newsImpact: data['newsImpact'] as String? ?? '',
      strategyMatch: data['strategyMatch'] as String? ?? '',
    );

    // Determine if this is a neutral/no-trade signal
    final isNeutral = signal.bias == 'NEUTRAL' || signal.bias == 'ERROR';
    final hasError = signal.bias == 'ERROR';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTokens.radiusCardLg),
        onTap: isNeutral
            ? null
            : () => widget.onQuickAction(HomeQuickAction.askAi),
        child: Ink(
          padding: const EdgeInsets.all(AppTokens.spaceLg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTokens.radiusCardLg),
            color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
            border: hasError
                ? Border.all(
                    color: AppColors.bear.withValues(alpha: 0.5),
                  )
                : null,
            boxShadow: AppShadows.card,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: hasError
                          ? AppColors.bear.withValues(alpha: 0.15)
                          : (signal.bias == 'LONG'
                              ? AppColors.bull.withValues(alpha: 0.15)
                              : (signal.bias == 'SHORT'
                                  ? AppColors.bear.withValues(alpha: 0.15)
                                  : AppColors.textMutedDark.withValues(alpha: 0.15))),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      signal.pair,
                      style: AppFonts.body(
                        size: 11,
                        weight: FontWeight.w700,
                        color: hasError
                            ? AppColors.bear
                            : (signal.bias == 'LONG'
                                ? AppColors.bull
                                : (signal.bias == 'SHORT'
                                    ? AppColors.bear
                                    : AppColors.textMutedDark)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: hasError
                          ? AppColors.bear.withValues(alpha: 0.15)
                          : (signal.bias == 'LONG'
                              ? AppColors.bull.withValues(alpha: 0.15)
                              : (signal.bias == 'SHORT'
                                  ? AppColors.bear.withValues(alpha: 0.15)
                                  : AppColors.textMutedDark.withValues(alpha: 0.15))),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      signal.bias,
                      style: AppFonts.body(
                        size: 11,
                        weight: FontWeight.w700,
                        color: hasError
                            ? AppColors.bear
                            : (signal.bias == 'LONG'
                                ? AppColors.bull
                                : (signal.bias == 'SHORT'
                                    ? AppColors.bear
                                    : AppColors.textMutedDark)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    signal.timeframe,
                    style: AppFonts.body(
                      size: 11,
                      color: AppColors.textMutedDark,
                      weight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  if (signal.confidence > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.amber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${signal.confidence}%',
                        style: AppFonts.body(
                          size: 10,
                          weight: FontWeight.w700,
                          color: AppColors.amber,
                        ),
                      ),
                    ),
                ],
              ),
              if (!isNeutral) ...[
                const SizedBox(height: AppTokens.spaceMd),
                Row(
                  children: [
                    _SignalDetail(
                      label: 'Entry',
                      value: _fmtPrice(signal.entry),
                      color: AppColors.textPrimaryDark,
                    ),
                    const SizedBox(width: AppTokens.spaceLg),
                    _SignalDetail(
                      label: 'Stop',
                      value: _fmtPrice(signal.stopLoss),
                      color: AppColors.bear,
                    ),
                    const SizedBox(width: AppTokens.spaceLg),
                    _SignalDetail(
                      label: 'Target',
                      value: _fmtPrice(signal.takeProfit),
                      color: AppColors.bull,
                    ),
                    const Spacer(),
                    if (signal.riskReward != null)
                      _SignalDetail(
                        label: 'R:R',
                        value: signal.riskReward!.toStringAsFixed(1),
                        color: AppColors.amber,
                      ),
                  ],
                ),
              ],
              if (signal.confidenceReason.isNotEmpty) ...[
                const SizedBox(height: AppTokens.spaceMd),
                Text(
                  signal.confidenceReason,
                  style: AppFonts.body(
                    size: AppTokens.captionSize,
                    color: AppColors.textSecondaryDark,
                    height: 1.35,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (isNeutral && !hasError) ...[
                const SizedBox(height: AppTokens.spaceSm),
                Text(
                  'No trade setup matched your strategy for this symbol.',
                  style: AppFonts.body(
                    size: AppTokens.captionSize,
                    color: AppColors.textMutedDark,
                  ).copyWith(fontStyle: FontStyle.italic),
                ),
              ],
              if (hasError) ...[
                const SizedBox(height: AppTokens.spaceSm),
                Text(
                  'Error: ${data['error'] ?? 'Analysis failed'}',
                  style: AppFonts.body(
                    size: AppTokens.captionSize,
                    color: AppColors.bear,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, Color secondary) {
    return Text(
      title.toUpperCase(),
      style: AppFonts.body(
        size: AppTokens.fontSizeTiny,
        weight: FontWeight.w700,
        color: secondary,
        height: 1,
      ),
    );
  }

  Widget _buildWatchlistTitle(Color secondary) {
    final isConfigured = widget.tradingApiService.isConfigured;
    final hasAnyFresh = _liveQuotes.keys.any(_isQuoteFresh);
    final hasAnyStale = _liveQuotes.keys.any((s) => _liveQuotes[s] != null && !_isQuoteFresh(s));
    String title;
    Color statusColor;
    IconData statusIcon;
    String statusText;
    if (!isConfigured) {
      title = 'Watchlist';
      statusIcon = Icons.cloud_off_rounded;
      statusColor = AppColors.textMutedDark;
      statusText = 'Backend not configured';
    } else if (hasAnyFresh) {
      title = 'Live markets';
      statusIcon = Icons.circle;
      statusColor = AppColors.bull;
      statusText = hasAnyStale ? 'Partial feed' : 'Updating live';
    } else if (_liveQuotes.isNotEmpty) {
      // Has quotes but all stale
      title = 'Live markets';
      statusIcon = Icons.access_time_rounded;
      statusColor = AppColors.warning;
      statusText = 'Feed stale — retrying...';
    } else {
      title = 'Live markets';
      statusIcon = Icons.sync_rounded;
      statusColor = secondary;
      statusText = 'Connecting...';
    }
    return Row(
      children: [
        Expanded(
          child: _buildSectionTitle(title, secondary),
        ),
        if (isConfigured) ...[
          Icon(statusIcon, size: 10, color: statusColor),
          const SizedBox(width: 4),
          Text(
            statusText,
            style: AppFonts.body(
              size: AppTokens.fontSizeTiny,
              weight: FontWeight.w700,
              color: statusColor,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildWatchlist(bool isDark) {
      return Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(AppTokens.radiusCard),
          boxShadow: AppShadows.card,
        ),
        child: Column(
          children: [
            for (var i = 0; i < _watchlist.length; i++)
              if (i > 0)
                Divider(
                  height: 1,
                  color: (isDark ? AppColors.borderDark : AppColors.borderLight)
                      .withValues(alpha: 0.5),
                )
              else
                const SizedBox.shrink(),
            for (final item in _watchlist)
              _buildWatchRow(item, isDark),
          ],
        ),
      );
    }

    /// One watchlist row. When the backend has delivered a fresh live quote
    /// for the symbol it renders the fresh price/change/candles with animated
    /// transitions; otherwise the curated static snapshot is shown with a
    /// subtle stale indicator.
    Widget _buildWatchRow(_WatchItem item, bool isDark) {
      final quote = _getFreshQuote(item.symbol);
      final hasStaleQuote = _liveQuotes[item.symbol] != null && quote == null;
      final price = quote != null
          ? ((quote['last_close'] as num?) ?? item.price).toDouble()
          : item.price;
      final change = quote != null
          ? ((quote['change_percent'] as num?) ?? item.change).toDouble()
          : item.change;
      final spark = quote != null ? quote['spark'] : null;
      final List<List<double>> candles =
          spark is List && spark.isNotEmpty
              ? spark
                    .map(
                      (c) => (c as List)
                          .map((v) => (v as num).toDouble())
                          .toList(),
                    )
                    .toList()
              : item.candles;
      final changeUp = change >= 0;
      final changeColor = changeUp ? AppColors.bull : AppColors.bear;
      final priceText = _fmtPrice(price);

      // Tapping a row opens the live TradingView chart for that symbol.
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openChart(item),
          borderRadius: BorderRadius.circular(AppTokens.radiusCard),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.spaceLg,
              vertical: AppTokens.spaceMd,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 92,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.pair,
                        style: AppFonts.heading(
                          size: 13,
                          weight: FontWeight.w600,
                        ),
                      ),
                      if (quote != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          'LIVE',
                          style: AppFonts.body(
                            size: AppTokens.fontSizeTiny,
                            weight: FontWeight.w700,
                            color: AppColors.bull,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ] else if (hasStaleQuote) ...[
                        const SizedBox(height: 2),
                        Text(
                          'STALE',
                          style: AppFonts.body(
                            size: AppTokens.fontSizeTiny,
                            weight: FontWeight.w700,
                            color: AppColors.warning,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: CandleSparkline(candles: candles, height: 34),
          ),
          const SizedBox(width: AppTokens.spaceMd),
          SizedBox(
            width: 82,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 450),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.25),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: Text(
                    priceText,
                    key: ValueKey('price_${item.symbol}_$priceText'),
                    style: AppFonts.body(
                      size: AppTokens.captionSize,
                      weight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: changeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                  ),
                  child: Text(
                    '${change >= 0 ? '+' : ''}'
                    '${change.toStringAsFixed(2)}%',
                    style: AppFonts.body(
                      size: AppTokens.fontSizeTiny,
                      weight: FontWeight.w700,
                      color: changeColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    ),
  );
  }

  Widget _buildRecentAnalyses(bool isDark) {
    if (_loading) {
      return Column(
        children: const [
          ShimmerBox(height: 64),
          SizedBox(height: AppTokens.spaceSm),
          ShimmerBox(height: 64),
          SizedBox(height: AppTokens.spaceSm),
          ShimmerBox(height: 64),
        ],
      );
    }
    if (_recentAnalyses.isEmpty) {
      return _EmptyCard(
        icon: Icons.analytics_rounded,
        title: 'No analyses yet',
        message: 'Ask the AI to read a chart or paste a TradingView URL.',
        onTap: () => widget.onQuickAction(HomeQuickAction.askAi),
        isDark: isDark,
      );
    }

    final border = isDark ? AppColors.borderDark : AppColors.borderLight;
    final secondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        children: [
          for (var i = 0; i < _recentAnalyses.length; i++) ...[
            if (i > 0)
              Divider(height: 1, color: border.withValues(alpha: 0.5))
            else
              const SizedBox.shrink(),
            _AnalysisTile(
              goal: _recentAnalyses[i]['goal']?.toString() ?? 'Task',
              status: _recentAnalyses[i]['status']?.toString() ?? '',
              timestamp:
                  _recentAnalyses[i]['timestamp']?.toString() ?? '',
              secondary: secondary,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickActions(bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _QuickAction(
          icon: Icons.mic_rounded,
          label: 'Voice Chat',
          accent: null,
          onTap: () => widget.onQuickAction(HomeQuickAction.voice),
        ),
        _QuickAction(
          icon: Icons.link_rounded,
          label: 'Chart URL',
          accent: null,
          onTap: () => widget.onQuickAction(HomeQuickAction.pasteUrl),
        ),
        _QuickAction(
          icon: Icons.auto_awesome_rounded,
          label: 'Ask AI',
          accent: AppColors.amber,
          onTap: () => widget.onQuickAction(HomeQuickAction.askAi),
        ),
        _QuickAction(
          icon: Icons.image_rounded,
          label: 'Upload',
          accent: null,
          onTap: () => widget.onQuickAction(HomeQuickAction.upload),
        ),
      ],
    );
  }

  static String _fmtPrice(double v) {
    if (v >= 1000) return v.toStringAsFixed(0);
    if (v >= 100) return v.toStringAsFixed(1);
    return v.toStringAsFixed(2);
  }
}

class _MarketStatusChip extends StatelessWidget {
  final bool isDark;
  const _MarketStatusChip({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceMd,
        vertical: AppTokens.spaceSm,
      ),
      decoration: BoxDecoration(
        color: AppColors.bull.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
        border: Border.all(
          color: AppColors.bull.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PulseDot(),
          const SizedBox(width: 6),
          Text(
            'Live',
            style: AppFonts.body(
              size: AppTokens.fontSizeTiny,
              weight: FontWeight.w700,
              color: AppColors.bull,
            ),
          ),
        ],
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.4, end: 1).animate(_controller),
      child: const DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.bull,
          shape: BoxShape.circle,
        ),
        child: SizedBox(width: 7, height: 7),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color accent;
  final bool isLoading;
  final String? subtitle;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    this.isLoading = false,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final displayValue = isLoading ? '—' : value;
    final displayAccent = isLoading
        ? (isDark ? AppColors.textMutedDark : AppColors.textSecondaryLight)
        : accent;
    final displayLabel = isLoading && subtitle != null ? subtitle! : label;

    return Container(
      padding: const EdgeInsets.all(AppTokens.spaceLg),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: displayAccent),
          const SizedBox(height: AppTokens.spaceSm),
          Text(
            displayValue,
            style: AppFonts.heading(
              size: 16,
              weight: FontWeight.w700,
              color: displayAccent,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            displayLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppFonts.body(
              size: AppTokens.fontSizeTiny,
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalysisTile extends StatelessWidget {
  final String goal;
  final String status;
  final String timestamp;
  final Color secondary;

  const _AnalysisTile({
    required this.goal,
    required this.status,
    required this.timestamp,
    required this.secondary,
  });

  @override
  Widget build(BuildContext context) {
    final ok = status == 'Success';
    return ListTile(
      dense: true,
      leading: Icon(
        ok ? Icons.check_circle_rounded : Icons.error_rounded,
        color: ok ? AppColors.bull : AppColors.warning,
        size: 20,
      ),
      title: Text(
        goal,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppFonts.body(
          size: AppTokens.bodySize,
          weight: FontWeight.w600,
        ),
      ),
      trailing: Text(
        _shortTime(timestamp),
        style: AppFonts.body(size: AppTokens.fontSizeTiny, color: secondary),
      ),
    );
  }

  static String _shortTime(String iso) {
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return '';
    final local = parsed.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _EmptyCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final VoidCallback onTap;
  final bool isDark;

  const _EmptyCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppTokens.radiusCard),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppTokens.spaceXl),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(AppTokens.radiusCard),
          boxShadow: AppShadows.card,
        ),
        child: Column(
          children: [
            Icon(icon, size: 30, color: AppColors.amber),
            const SizedBox(height: AppTokens.spaceSm),
            Text(
              title,
              style: AppFonts.heading(
                size: 14,
                weight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppFonts.body(
                size: AppTokens.captionSize,
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? accent;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color iconColor = accent ??
        (isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight);
    final Color circleBg = accent != null
        ? accent!.withValues(alpha: 0.16)
        : (isDark
            ? AppColors.surfaceElevatedDark
            : AppColors.surfaceElevatedLight);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTokens.radiusPill),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spaceSm,
          vertical: AppTokens.spaceSm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: circleBg,
                shape: BoxShape.circle,
                boxShadow: AppShadows.card,
              ),
              child: Icon(icon, size: 22, color: iconColor),
            ),
            const SizedBox(height: AppTokens.spaceSm),
            Text(
              label,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: AppFonts.body(
                size: AppTokens.fontSizeTiny,
                weight: FontWeight.w600,
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WatchItem {
  final String pair;
  final String symbol;
  final double price;
  final double change;
  final List<List<double>> candles;

  const _WatchItem(this.pair, this.symbol, this.price, this.change, this.candles);

  /// Create a _WatchItem from a symbol string with sensible defaults.
  /// The price/change/candles will be replaced by live data when available.
  factory _WatchItem.fromSymbol(String symbol) {
    // Default static fallbacks per symbol (matching the old static watchlist)
    final defaults = <String, _WatchItemDefaults>{
      'BTCUSD': _WatchItemDefaults('BTC/USD', 108412.0, 2.34, [
        [104200, 104900, 103800, 104650],
        [104650, 105800, 104400, 105700],
        [105700, 105200, 104900, 105350],
        [105350, 106400, 105100, 106250],
        [106250, 107100, 105900, 106800],
        [106800, 106400, 106050, 106520],
        [106520, 107800, 106300, 107650],
        [107650, 108412, 107200, 108412],
      ]),
      'ETHUSD': _WatchItemDefaults('ETH/USD', 3892.5, -0.87, [
        [3900, 3940, 3880, 3935],
        [3935, 3920, 3875, 3890],
        [3890, 3905, 3860, 3872],
        [3872, 3885, 3840, 3848],
        [3848, 3860, 3825, 3835],
        [3835, 3872, 3820, 3865],
        [3865, 3900, 3850, 3892],
        [3892, 3912, 3880, 3892],
      ]),
      'XAUUSD': _WatchItemDefaults('XAU/USD', 2418.5, 0.42, [
        [2401, 2408, 2394, 2406],
        [2406, 2402, 2392, 2398],
        [2398, 2404, 2390, 2402],
        [2402, 2409, 2398, 2407],
        [2407, 2414, 2402, 2411],
        [2411, 2408, 2400, 2405],
        [2405, 2414, 2401, 2412],
        [2412, 2418, 2409, 2418],
      ]),
      'NAS100': _WatchItemDefaults('NAS100', 21482.0, -0.31, [
        [21600, 21680, 21560, 21650],
        [21650, 21610, 21520, 21580],
        [21580, 21620, 21490, 21530],
        [21530, 21570, 21460, 21490],
        [21490, 21540, 21430, 21480],
        [21480, 21510, 21390, 21430],
        [21430, 21490, 21400, 21460],
        [21460, 21500, 21440, 21482],
      ]),
      'EURUSD': _WatchItemDefaults('EUR/USD', 1.0850, 0.12, [
        [1.0820, 1.0860, 1.0810, 1.0845],
        [1.0845, 1.0870, 1.0835, 1.0865],
        [1.0865, 1.0880, 1.0855, 1.0875],
        [1.0875, 1.0890, 1.0865, 1.0885],
        [1.0885, 1.0900, 1.0875, 1.0895],
        [1.0895, 1.0910, 1.0885, 1.0905],
        [1.0905, 1.0920, 1.0895, 1.0915],
        [1.0915, 1.0925, 1.0905, 1.0920],
      ]),
      'GBPUSD': _WatchItemDefaults('GBP/USD', 1.2750, -0.05, [
        [1.2740, 1.2780, 1.2730, 1.2760],
        [1.2760, 1.2770, 1.2745, 1.2755],
        [1.2755, 1.2765, 1.2740, 1.2750],
        [1.2750, 1.2760, 1.2735, 1.2745],
        [1.2745, 1.2755, 1.2730, 1.2740],
        [1.2740, 1.2750, 1.2725, 1.2735],
        [1.2735, 1.2745, 1.2720, 1.2730],
        [1.2730, 1.2740, 1.2715, 1.2725],
      ]),
      'USDJPY': _WatchItemDefaults('USD/JPY', 151.50, 0.33, [
        [151.20, 151.60, 151.10, 151.45],
        [151.45, 151.70, 151.35, 151.65],
        [151.65, 151.80, 151.55, 151.75],
        [151.75, 151.90, 151.65, 151.85],
        [151.85, 152.00, 151.75, 151.95],
        [151.95, 152.10, 151.85, 152.05],
        [152.05, 152.20, 151.95, 152.15],
        [152.15, 152.25, 152.05, 152.20],
      ]),
      'US500': _WatchItemDefaults('US500', 5450.0, 0.45, [
        [5400, 5460, 5390, 5445],
        [5445, 5470, 5430, 5465],
        [5465, 5480, 5455, 5475],
        [5475, 5490, 5465, 5485],
        [5485, 5500, 5475, 5495],
        [5495, 5510, 5485, 5505],
        [5505, 5520, 5495, 5515],
        [5515, 5530, 5505, 5525],
      ]),
      'US30': _WatchItemDefaults('US30', 39500.0, -0.22, [
        [39300, 39600, 39200, 39450],
        [39450, 39550, 39350, 39500],
        [39500, 39580, 39420, 39540],
        [39540, 39600, 39480, 39560],
        [39560, 39620, 39500, 39580],
        [39580, 39640, 39520, 39600],
        [39600, 39660, 39540, 39620],
        [39620, 39680, 39560, 39640],
      ]),
    };

    final d = defaults[symbol] ??
        _WatchItemDefaults(
            symbol.length == 6 ? '${symbol.substring(0, 3)}/${symbol.substring(3)}' : symbol,
            0.0,
            0.0,
            []);
    return _WatchItem(d.pair, symbol, d.price, d.change, d.candles);
  }
}

class _WatchItemDefaults {
  final String pair;
  final double price;
  final double change;
  final List<List<double>> candles;

  const _WatchItemDefaults(this.pair, this.price, this.change, this.candles);
}

/// Detail widget for signal parameters (entry, stop, target, R:R).
class _SignalDetail extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _SignalDetail({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppFonts.body(
            size: AppTokens.fontSizeTiny,
            weight: FontWeight.w600,
            color: AppColors.textMutedDark,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: AppFonts.body(
            size: 12,
            weight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// Error state card for signals section.
class _SignalsErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _SignalsErrorCard({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTokens.radiusCardLg),
        onTap: onRetry,
        child: Ink(
          padding: const EdgeInsets.all(AppTokens.spaceLg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTokens.radiusCardLg),
            color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
            border: Border.all(color: AppColors.bear.withValues(alpha: 0.5)),
            boxShadow: AppShadows.card,
          ),
          child: Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: AppColors.bear, size: 24),
              const SizedBox(width: AppTokens.spaceMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Failed to load signals',
                      style: AppFonts.heading(size: 13, weight: FontWeight.w700, color: AppColors.bear),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      message,
                      style: AppFonts.body(size: AppTokens.captionSize, color: AppColors.textSecondaryDark),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: onRetry,
                child: Text('Retry', style: AppFonts.body(size: 12, weight: FontWeight.w600, color: AppColors.amber)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Empty state card for signals section.
class _SignalsEmptyCard extends StatelessWidget {
  final String message;
  final VoidCallback? onConfigure;

  const _SignalsEmptyCard({
    required this.message,
    this.onConfigure,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTokens.radiusCardLg),
        onTap: onConfigure,
        child: Ink(
          padding: const EdgeInsets.all(AppTokens.spaceXl),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTokens.radiusCardLg),
            color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
            boxShadow: AppShadows.card,
          ),
          child: Column(
            children: [
              Icon(
                Icons.analytics_outlined,
                size: 30,
                color: AppColors.textMutedDark,
              ),
              const SizedBox(height: AppTokens.spaceSm),
              Text(
                'No signals yet',
                style: AppFonts.heading(size: 14, weight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppFonts.body(
                  size: AppTokens.captionSize,
                  color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                ),
              ),
              if (onConfigure != null) ...[
                const SizedBox(height: AppTokens.spaceMd),
                TextButton.icon(
                  onPressed: onConfigure,
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: Text('Configure Watchlist', style: AppFonts.body(size: 12, weight: FontWeight.w600)),
                  style: TextButton.styleFrom(foregroundColor: AppColors.amber),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet surfacing recent activity: journal entries from the trading
/// backend plus the auto-execute setting. Read-only view of backend state.
class _ActivitySheet extends StatefulWidget {
  final TradingApiService tradingApiService;

  const _ActivitySheet({required this.tradingApiService});

  @override
  State<_ActivitySheet> createState() => _ActivitySheetState();
}

class _ActivitySheetState extends State<_ActivitySheet> {
  List<Map<String, dynamic>> _entries = const [];
  bool _loading = true;
  bool _autoExecute = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final journal = await widget.tradingApiService.getJournal();
    final settings = await widget.tradingApiService.getSettings();
    if (!mounted) return;
    setState(() {
      final raw = journal['entries'];
      _entries = raw is List
          ? raw.whereType<Map<String, dynamic>>().toList()
          : const [];
      _autoExecute = settings['auto_execute'] == true;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.secondaryBgDark : AppColors.bgLight,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppTokens.radiusCardLg),
        ),
      ),
      padding: EdgeInsets.only(bottom: bottom + AppTokens.spaceXl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: AppTokens.spaceMd),
              decoration: BoxDecoration(
                color: (isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight)
                    .withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(AppTokens.radiusPill),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.spaceXl,
              AppTokens.spaceLg,
              AppTokens.spaceXl,
              AppTokens.spaceMd,
            ),
            child: Row(
              children: [
                Text(
                  'Activity',
                  style: AppFonts.heading(
                    size: AppTokens.titleSize,
                    weight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.spaceMd,
                    vertical: AppTokens.spaceXs,
                  ),
                  decoration: BoxDecoration(
                    color: (_autoExecute
                            ? AppColors.amber
                            : (isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondaryLight))
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _autoExecute
                            ? Icons.bolt_rounded
                            : Icons.shield_outlined,
                        size: 14,
                        color: _autoExecute
                            ? AppColors.amber
                            : (isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondaryLight),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _autoExecute ? 'Auto-execute on' : 'Auto-execute off',
                        style: AppFonts.body(
                          size: AppTokens.fontSizeTiny,
                          weight: FontWeight.w700,
                          color: _autoExecute
                              ? AppColors.amber
                              : (isDark
                                    ? AppColors.textSecondaryDark
                                    : AppColors.textSecondaryLight),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: (isDark ? AppColors.borderDark : AppColors.borderLight)),
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.55,
              ),
              child: _loading
                  ? Padding(
                      padding: const EdgeInsets.all(AppTokens.spaceXl),
                      child: Column(
                        children: const [
                          ShimmerBox(height: 56),
                          SizedBox(height: AppTokens.spaceSm),
                          ShimmerBox(height: 56),
                          SizedBox(height: AppTokens.spaceSm),
                          ShimmerBox(height: 56),
                        ],
                      ),
                    )
                  : _entries.isEmpty
                      ? _ActivityEmpty(isDark: isDark)
                      : ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(
                            vertical: AppTokens.spaceSm,
                          ),
                          itemCount: _entries.length,
                          separatorBuilder: (_, _) => Divider(
                            height: 1,
                            indent: AppTokens.spaceXl,
                            endIndent: AppTokens.spaceXl,
                            color: (isDark
                                    ? AppColors.borderDark
                                    : AppColors.borderLight)
                                .withValues(alpha: 0.6),
                          ),
                          itemBuilder: (context, index) =>
                              _ActivityTile(entry: _entries[index]),
                        ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  final Map<String, dynamic> entry;

  const _ActivityTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final symbol = entry['symbol']?.toString() ?? 'Market';
    final timeframe = entry['timeframe']?.toString() ?? '';
    final action = entry['action_taken'];
    final executed = action is Map && action['executed'] == true;
    final analysis = entry['analysis'];
    final snippet = analysis is Map
        ? (analysis['chart_summary']?.toString() ??
            analysis['reasoning_text']?.toString() ??
            '')
        : '';

    return ListTile(
      dense: true,
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: (executed
                  ? AppColors.amber
                  : (isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight))
              .withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          executed ? Icons.bolt_rounded : Icons.insights_rounded,
          size: 18,
          color: executed
              ? AppColors.amber
              : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight),
        ),
      ),
      title: Text(
        executed ? 'Trade executed' : 'Analysis',
        style: AppFonts.body(
          size: AppTokens.bodySize,
          weight: FontWeight.w700,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            snippet.isNotEmpty ? snippet : '${symbol.trim()} ${timeframe.trim()}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppFonts.body(size: AppTokens.captionSize, color: secondary),
          ),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            _pairLabel(symbol, timeframe),
            style: AppFonts.body(
              size: AppTokens.fontSizeTiny,
              weight: FontWeight.w700,
              color: executed ? AppColors.amber : secondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _relativeTime(entry['timestamp']?.toString() ?? ''),
            style: AppFonts.body(size: AppTokens.fontSizeTiny, color: secondary),
          ),
        ],
      ),
    );
  }

  static String _pairLabel(String symbol, String timeframe) {
    final s = symbol.trim();
    final t = timeframe.trim();
    if (s.isEmpty && t.isEmpty) return '';
    if (s.isEmpty) return t;
    if (t.isEmpty) return s;
    return '$s $t';
  }

  static String _relativeTime(String iso) {
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return '';
    final diff = DateTime.now().difference(parsed.toLocal());
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _ActivityEmpty extends StatelessWidget {
  final bool isDark;

  const _ActivityEmpty({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final secondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    return Padding(
      padding: const EdgeInsets.all(AppTokens.spaceXxl),
      child: Column(
        children: [
          Icon(
            Icons.notifications_none_rounded,
            size: 32,
            color: secondary.withValues(alpha: 0.7),
          ),
          const SizedBox(height: AppTokens.spaceMd),
          Text(
            'No activity yet',
            style: AppFonts.heading(size: 14, weight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Runs from the Analysis screen will show up here.',
            textAlign: TextAlign.center,
            style: AppFonts.body(size: AppTokens.captionSize, color: secondary),
          ),
        ],
      ),
    );
  }
}
