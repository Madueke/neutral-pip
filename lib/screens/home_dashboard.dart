import 'dart:async';
import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/home_quick_action.dart';
import '../models/trade_signal.dart';
import '../services/task_history_logger.dart';
import '../services/trading_api_service.dart';
import '../widgets/app_animations.dart';
import '../widgets/candle_sparkline.dart';
import '../widgets/trade_card.dart';
import '../widgets/trading_avatar.dart';

/// Dashboard home: briefing, market pulse, watchlist, signals, and quick
/// actions. Presentational data is clearly marked; real data (recent
/// analyses) is read from the task history log.
class HomeDashboard extends StatefulWidget {
  final TradingApiService tradingApiService;
  final void Function(HomeQuickAction action) onQuickAction;

  const HomeDashboard({
    super.key,
    required this.tradingApiService,
    required this.onQuickAction,
  });

  @override
  State<HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<HomeDashboard> {
  List<Map<String, dynamic>> _recentAnalyses = const [];
  bool _loading = true;

  // Live market data: latest quote per watchlist symbol, refreshed by a
  // short poll timer when a trading backend is configured. When no backend
  // is configured the watchlist falls back to the curated static data.
  Timer? _quoteTimer;
  final Map<String, Map<String, dynamic>> _liveQuotes = {};
  bool _hasUnreadActivity = true;

  static const Duration _quotePollInterval = Duration(seconds: 6);

  static const List<_WatchItem> _watchlist = [
    _WatchItem(
      'BTC/USD',
      'BTCUSD',
      108412.0,
      2.34,
      [
        [104200, 104900, 103800, 104650],
        [104650, 105800, 104400, 105700],
        [105700, 105200, 104900, 105350],
        [105350, 106400, 105100, 106250],
        [106250, 107100, 105900, 106800],
        [106800, 106400, 106050, 106520],
        [106520, 107800, 106300, 107650],
        [107650, 108412, 107200, 108412],
      ],
    ),
    _WatchItem(
      'ETH/USD',
      'ETHUSD',
      3892.5,
      -0.87,
      [
        [3900, 3940, 3880, 3935],
        [3935, 3920, 3875, 3890],
        [3890, 3905, 3860, 3872],
        [3872, 3885, 3840, 3848],
        [3848, 3860, 3825, 3835],
        [3835, 3872, 3820, 3865],
        [3865, 3900, 3850, 3892],
        [3892, 3912, 3880, 3892],
      ],
    ),
    _WatchItem(
      'XAU/USD',
      'XAUUSD',
      2418.5,
      0.42,
      [
        [2401, 2408, 2394, 2406],
        [2406, 2402, 2392, 2398],
        [2398, 2404, 2390, 2402],
        [2402, 2409, 2398, 2407],
        [2407, 2414, 2402, 2411],
        [2411, 2408, 2400, 2405],
        [2405, 2414, 2401, 2412],
        [2412, 2418, 2409, 2418],
      ],
    ),
    _WatchItem(
      'NAS100',
      'NAS100',
      21482.0,
      -0.31,
      [
        [21600, 21680, 21560, 21650],
        [21650, 21610, 21520, 21580],
        [21580, 21620, 21490, 21530],
        [21530, 21570, 21460, 21490],
        [21490, 21540, 21430, 21480],
        [21480, 21510, 21390, 21430],
        [21430, 21490, 21400, 21460],
        [21460, 21500, 21440, 21482],
      ],
    ),
  ];

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

  Future<void> _refreshQuotes() async {
    // No-op until a trading backend is configured; the periodic timer keeps
    // checking so quotes start flowing as soon as the user saves one.
    if (!widget.tradingApiService.isConfigured) return;
    for (final item in _watchlist) {
      final quote = await widget.tradingApiService.getQuote(item.symbol);
      if (!mounted) return;
      if (quote['status'] == 'ok') {
        setState(() => _liveQuotes[item.symbol] = quote);
      }
    }
  }

  Future<void> _load() async {
    final history = await TaskHistoryLogger.readHistory();
    if (!mounted) return;
    setState(() {
      _recentAnalyses = history.take(3).toList();
      _loading = false;
    });
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
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            _buildGlows(isDark),
            ListView(
              // The shell reserves space for the floating nav, so the list
              // only needs a small closing gap of its own.
              padding: const EdgeInsets.fromLTRB(
                AppTokens.spaceLg,
                AppTokens.spaceLg,
                AppTokens.spaceLg,
                AppTokens.spaceXl,
              ),
              children: [
                FadeInUp(child: _buildHeader(isDark, secondary)),
                const SizedBox(height: AppTokens.spaceXl),
                FadeInUp(
                  delay: const Duration(milliseconds: 80),
                  child: _buildBriefingCard(context),
                ),
                const SizedBox(height: AppTokens.spaceXl),
                FadeInUp(
                  delay: const Duration(milliseconds: 140),
                  child: _buildStatGrid(isDark),
                ),
                const SizedBox(height: AppTokens.spaceXl),
                FadeInUp(
                  delay: const Duration(milliseconds: 200),
                  child: _buildWatchlistTitle(secondary),
                ),
                const SizedBox(height: AppTokens.spaceMd),
                FadeInUp(
                  delay: const Duration(milliseconds: 240),
                  child: _buildWatchlist(isDark),
                ),
                const SizedBox(height: AppTokens.spaceXl),
                FadeInUp(
                  delay: const Duration(milliseconds: 280),
                  child: _buildSectionTitle('Latest signals', secondary),
                ),
                const SizedBox(height: AppTokens.spaceMd),
                for (final signal in TradeSignal.samples)
                  Padding(
                    padding:
                        const EdgeInsets.only(bottom: AppTokens.spaceLg),
                    child: FadeInUp(
                      child: TradeCard(
                        signal: signal,
                        onTap: () =>
                            widget.onQuickAction(HomeQuickAction.askAi),
                      ),
                    ),
                  ),
                const SizedBox(height: AppTokens.spaceXs),
                FadeInUp(
                  child: _buildSectionTitle('Recent analyses', secondary),
                ),
                const SizedBox(height: AppTokens.spaceMd),
                FadeInUp(child: _buildRecentAnalyses(isDark)),
                const SizedBox(height: AppTokens.spaceXl),
                FadeInUp(
                  child: _buildSectionTitle('Quick actions', secondary),
                ),
                const SizedBox(height: AppTokens.spaceMd),
                FadeInUp(child: _buildQuickActions(isDark)),
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
                'Neutral Pip',
                style: AppFonts.heading(
                  size: AppTokens.headlineSize,
                  weight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        _MarketStatusChip(isDark: isDark),
        const SizedBox(width: AppTokens.spaceMd),
        Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton.filledTonal(
              onPressed: _openActivitySheet,
              icon: const Icon(Icons.notifications_rounded, size: 20),
              tooltip: 'Activity',
              style: IconButton.styleFrom(
                backgroundColor:
                    isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                foregroundColor:
                    isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
              ),
            ),
            if (_hasUnreadActivity)
              Positioned(
                top: 6,
                right: 6,
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
        const SizedBox(width: AppTokens.spaceSm),
        const TradingAvatar(size: 42),
      ],
    );
  }

  Widget _buildBriefingCard(BuildContext context) {
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
                Color(0xFF1D2740),
                Color(0xFF161D2F),
              ],
            ),
            border: Border.all(
              color: AppColors.amber.withValues(alpha: 0.25),
            ),
            boxShadow: AppShadows.card,
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.amber.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: AppShadows.glow,
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: AppColors.amber,
                  size: 22,
                ),
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
                      'Markets are range-bound overnight. Gold holds '
                      'support; crypto momentum cooling.',
                      style: AppFonts.body(
                        size: AppTokens.captionSize,
                        color: AppColors.textSecondaryDark,
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
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: 'Open trades',
            value: '3',
            icon: Icons.layers_rounded,
            accent: AppColors.info,
          ),
        ),
        const SizedBox(width: AppTokens.spaceMd),
        Expanded(
          child: _StatCard(
            label: 'Risk used',
            value: '42%',
            icon: Icons.speed_rounded,
            accent: AppColors.warning,
          ),
        ),
        const SizedBox(width: AppTokens.spaceMd),
        Expanded(
          child: _StatCard(
            label: 'Daily P/L',
            value: '+1.24%',
            icon: Icons.trending_up_rounded,
            accent: AppColors.bull,
          ),
        ),
        const SizedBox(width: AppTokens.spaceMd),
        Expanded(
          child: _StatCard(
            label: 'Health',
            value: '88',
            icon: Icons.favorite_rounded,
            accent: AppColors.bull,
          ),
        ),
      ],
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
    final live = _liveQuotes.isNotEmpty;
    return Row(
      children: [
        Expanded(
          child: _buildSectionTitle(
            live ? 'Live markets' : 'Watchlist',
            secondary,
          ),
        ),
        if (live) ...[
          _PulseDot(),
          const SizedBox(width: 6),
          Text(
            'Updating live',
            style: AppFonts.body(
              size: AppTokens.fontSizeTiny,
              weight: FontWeight.w700,
              color: AppColors.bull,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildWatchlist(bool isDark) {
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;
    final live = _liveQuotes.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        border: Border.all(color: border),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        children: [
          for (var i = 0; i < _watchlist.length; i++)
            if (i > 0)
              Divider(height: 1, color: border.withValues(alpha: 0.6))
            else
              const SizedBox.shrink(),
          for (final item in _watchlist)
            _buildWatchRow(item, live, isDark),
        ],
      ),
    );
  }

  /// One watchlist row. When the backend has delivered a live quote for the
  /// symbol it renders the fresh price/change/candles with animated
  /// transitions; otherwise the curated static snapshot is shown.
  Widget _buildWatchRow(_WatchItem item, bool live, bool isDark) {
    final quote = live ? _liveQuotes[item.symbol] : null;
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

    return Padding(
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
                if (live) ...[
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
        border: Border.all(color: border),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        children: [
          for (var i = 0; i < _recentAnalyses.length; i++) ...[
            if (i > 0)
              Divider(height: 1, color: border.withValues(alpha: 0.6))
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
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppTokens.spaceMd,
      crossAxisSpacing: AppTokens.spaceMd,
      childAspectRatio: 0.92,
      children: [
        _QuickAction(
          icon: Icons.mic_rounded,
          label: 'Voice Chat',
          accent: AppColors.bull,
          onTap: () => widget.onQuickAction(HomeQuickAction.voice),
        ),
        _QuickAction(
          icon: Icons.link_rounded,
          label: 'TradingView URL',
          accent: AppColors.info,
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
          accent: AppColors.warning,
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

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(AppTokens.spaceMd),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
        ),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: accent),
          const SizedBox(height: AppTokens.spaceSm),
          Text(
            value,
            style: AppFonts.heading(
              size: 16,
              weight: FontWeight.w700,
              color: accent,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
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
          border: Border.all(
            color: isDark ? AppColors.borderDark : AppColors.borderLight,
          ),
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
  final Color accent;
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(AppTokens.radiusCard),
            border: Border.all(
              color: isDark ? AppColors.borderDark : AppColors.borderLight,
            ),
            boxShadow: AppShadows.card,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, size: 20, color: accent),
              ),
              const SizedBox(height: AppTokens.spaceSm),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
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
              ),
            ],
          ),
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
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
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
                    color: (_autoExecute ? AppColors.amber : AppColors.info)
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
                        color: _autoExecute ? AppColors.amber : AppColors.info,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _autoExecute ? 'Auto-execute on' : 'Auto-execute off',
                        style: AppFonts.body(
                          size: AppTokens.fontSizeTiny,
                          weight: FontWeight.w700,
                          color:
                              _autoExecute ? AppColors.amber : AppColors.info,
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
          color: (executed ? AppColors.amber : AppColors.info)
              .withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          executed ? Icons.bolt_rounded : Icons.insights_rounded,
          size: 18,
          color: executed ? AppColors.amber : AppColors.info,
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
