import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/theme.dart';
import '../services/trading_api_service.dart';
import '../widgets/logo_loader.dart';

/// Connect Trading Accounts (Trading Mode only).
///
/// Two account types, both wired to the same backend base URL configured in
/// Settings (TradingApiService.tradingBackendUrl):
///
///  * **TradingView** (no login): pick watchlist symbols + timeframes and
///    sync them via POST /connect-account under the `tradingview` key.
///  * **MT5** (real funded account): account number / password / broker
///    server posted once via POST /connect-account under the `mt5` key. The
///    fields are cleared immediately after a successful response and are
///    never persisted locally — only the returned session token is stored.
///
/// Status per account comes from GET /account-status (Bearer session
/// token) on load; disconnects go through POST /disconnect-account. Identity
/// is resolved server-side from the session — the app never sends a raw
/// user_id.
///
/// TRADING MODE: never add tap-based execution here. Connecting an account
/// is a backend-only operation — the app never interacts with a broker
/// terminal or the accessibility engine.
class ConnectAccountsScreen extends StatefulWidget {
  final TradingApiService tradingApiService;

  const ConnectAccountsScreen({
    super.key,
    required this.tradingApiService,
  });

  @override
  State<ConnectAccountsScreen> createState() => _ConnectAccountsScreenState();
}

class _ConnectAccountsScreenState extends State<ConnectAccountsScreen> {
  static const List<String> _presetSymbols = [
    'EURUSD',
    'GBPUSD',
    'USDJPY',
    'XAUUSD',
    'XAGUSD',
    'US500',
    'US30',
    'NAS100',
    'BTCUSD',
    'ETHUSD',
  ];
  static const List<String> _timeframeOptions = ['M15', 'H1', 'H4', 'D1'];

  // --- Account status ------------------------------------------------------
  Map<String, dynamic> _accountsStatus = {};
  bool _loading = true;

  // --- TradingView watchlist ----------------------------------------------
  final List<String> _symbols = List.of(_presetSymbols);
  final Set<String> _selectedSymbols = {};
  final Set<String> _selectedTimeframes = {};
  final TextEditingController _symbolInputController = TextEditingController();
  bool _tvSaving = false;

  // --- MT5 -----------------------------------------------------------------
  final TextEditingController _accountController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _brokerController = TextEditingController();
  bool _riskAcknowledged = false;
  bool _obscurePassword = true;
  bool _mt5Saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _symbolInputController.dispose();
    _accountController.dispose();
    _passwordController.dispose();
    _brokerController.dispose();
    super.dispose();
  }

  /// Load account status and restore any previously saved watchlist.
  Future<void> _load() async {
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();

    final storedSymbols = prefs.getStringList('watchlist_symbols');
    if (storedSymbols != null && storedSymbols.isNotEmpty) {
      _symbols
        ..clear()
        ..addAll(storedSymbols);
      _selectedSymbols
        ..clear()
        ..addAll(storedSymbols);
    } else {
      _selectedSymbols
        ..clear()
        ..addAll(const ['EURUSD', 'XAUUSD']);
    }

    final storedTimeframes = prefs.getStringList('watchlist_timeframes');
    _selectedTimeframes
      ..clear()
      ..addAll(storedTimeframes ?? const ['H1', 'D1']);

    final status = await widget.tradingApiService.getAccountStatus();
    if (!mounted) return;
    setState(() {
      _accountsStatus =
          status['accounts'] is Map<String, dynamic>
              ? status['accounts'] as Map<String, dynamic>
              : <String, dynamic>{};
      _loading = false;
    });
  }

  Future<void> _refresh() => _load();

  Map<String, dynamic> _statusFor(String key) =>
      _accountsStatus[key] is Map<String, dynamic>
          ? _accountsStatus[key] as Map<String, dynamic>
          : <String, dynamic>{};

  String _statusLabel(String key) =>
      (_statusFor(key)['status'] as String?) ?? 'not_connected';

  // --- Actions -------------------------------------------------------------

  Future<void> _saveTradingView() async {
    if (_selectedSymbols.isEmpty || _selectedTimeframes.isEmpty) {
      _showSnack('Select at least one symbol and one timeframe.');
      return;
    }
    setState(() => _tvSaving = true);
    try {
      final response = await widget.tradingApiService.connectTradingView(
        symbols: _selectedSymbols.toList(),
        timeframes: _selectedTimeframes.toList(),
      );
      if (!mounted) return;
      if (response['status'] == 'ok') {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList('watchlist_symbols', _symbols);
        await prefs.setStringList(
          'watchlist_timeframes',
          _selectedTimeframes.toList(),
        );
        _showSnack('TradingView watchlist synced.');
        await _load();
      } else {
        _showSnack(
          'Sync failed: ${response['message'] ?? 'unknown error'}',
          isError: true,
        );
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Sync failed: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _tvSaving = false);
    }
  }

  Future<void> _connectMt5() async {
    if (!_riskAcknowledged) return;
    if (_accountController.text.trim().isEmpty ||
        _passwordController.text.isEmpty ||
        _brokerController.text.trim().isEmpty) {
      _showSnack('Fill in account number, password and broker server.');
      return;
    }
    setState(() => _mt5Saving = true);
    try {
      final response = await widget.tradingApiService.connectMt5(
        accountNumber: _accountController.text,
        password: _passwordController.text,
        brokerServer: _brokerController.text,
      );
      if (!mounted) return;
      if (response['status'] == 'ok') {
        // Credentials must never be kept: clear local state immediately.
        _accountController.clear();
        _passwordController.clear();
        _brokerController.clear();
        _riskAcknowledged = false;
        _showSnack('MT5 account connected.');
        await _load();
      } else {
        _showSnack(
          'Connection failed: ${response['message'] ?? 'unknown error'}',
          isError: true,
        );
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Connection failed: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _mt5Saving = false);
    }
  }

  Future<void> _disconnect(String accountKey, String label) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        ),
        title: Text('Disconnect $label?'),
        content: Text(
          accountKey == TradingApiService.mt5AccountKey
              ? 'This will disconnect your real funded MT5 account. '
                    'The stored session token will be removed.'
              : 'Your watchlist will be disconnected from the co-pilot.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.bear),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final response =
        await widget.tradingApiService.disconnectAccount(accountKey);
    if (!mounted) return;
    if (response['status'] == 'ok') {
      _showSnack('$label disconnected.');
    } else {
      _showSnack(
        'Disconnect failed: ${response['message'] ?? 'unknown error'}',
        isError: true,
      );
    }
    await _load();
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: isError ? AppColors.bear : AppColors.bullDim,
          content: Text(message),
        ),
      );
  }

  void _addCustomSymbol() {
    final value = _symbolInputController.text.trim().toUpperCase();
    if (value.isEmpty) return;
    setState(() {
      if (!_symbols.contains(value)) _symbols.add(value);
      _selectedSymbols.add(value);
      _symbolInputController.clear();
    });
  }

  void _removeCustomSymbol(String symbol) {
    if (!_presetSymbols.contains(symbol)) {
      setState(() {
        _symbols.remove(symbol);
        _selectedSymbols.remove(symbol);
      });
    } else {
      setState(() => _selectedSymbols.remove(symbol));
    }
  }

  // --- UI ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Trading Accounts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh status',
            onPressed: _loading ? null : _refresh,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: LogoLoader())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  AppTokens.spaceLg,
                  AppTokens.spaceSm,
                  AppTokens.spaceLg,
                  AppTokens.spaceXxl,
                ),
                children: [
                  _buildStatusSection(scheme),
                  const SizedBox(height: AppTokens.spaceXl),
                  _buildTradingViewCard(scheme),
                  const SizedBox(height: AppTokens.spaceXl),
                  _buildMt5Card(scheme),
                ],
              ),
            ),
    );
  }

  Widget _buildStatusSection(ColorScheme scheme) {
    return Container(
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
          Text(
            'CONNECTED ACCOUNTS',
            style: AppFonts.body(
              size: AppTokens.fontSizeTiny,
              weight: FontWeight.w800,
              letterSpacing: 1.2,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          _buildAccountRow(
            scheme,
            key: TradingApiService.tradingViewAccountKey,
            label: 'TradingView',
            icon: Icons.show_chart_rounded,
            subtitle: 'Watchlist & alerts',
          ),
          Divider(height: AppTokens.spaceXl, color: scheme.outlineVariant),
          _buildAccountRow(
            scheme,
            key: TradingApiService.mt5AccountKey,
            label: 'MetaTrader 5',
            icon: Icons.account_balance_wallet_rounded,
            subtitle: 'Live funded account',
          ),
        ],
      ),
    );
  }

  Widget _buildAccountRow(
    ColorScheme scheme, {
    required String key,
    required String label,
    required IconData icon,
    required String subtitle,
  }) {
    final status = _statusLabel(key);
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.amber.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppTokens.radiusControl),
          ),
          child: Icon(icon, color: AppColors.amber, size: 18),
        ),
        const SizedBox(width: AppTokens.spaceMd),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppFonts.body(
                  size: AppTokens.bodySize,
                  weight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
              Text(
                subtitle,
                style: AppFonts.body(
                  size: AppTokens.captionSize,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (status == 'connected')
          TextButton(
            onPressed: () => _disconnect(key, label),
            child: const Text('Disconnect'),
          )
        else
          const SizedBox(width: AppTokens.spaceSm),
        const SizedBox(width: AppTokens.spaceSm),
        _StatusPill(status: status),
      ],
    );
  }

  Widget _buildTradingViewCard(ColorScheme scheme) {
    return Container(
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
              Icon(Icons.show_chart_rounded, color: AppColors.amber, size: 20),
              const SizedBox(width: AppTokens.spaceSm),
              Text(
                'TRADINGVIEW WATCHLIST',
                style: AppFonts.body(
                  size: 13,
                  weight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceXxs),
          Text(
            'No login required — pick symbols and timeframes to sync.',
            style: AppFonts.body(
              size: AppTokens.captionSize,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTokens.spaceLg),
          Text(
            'SYMBOLS',
            style: AppFonts.body(
              size: AppTokens.fontSizeTiny,
              weight: FontWeight.w700,
              letterSpacing: 0.8,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final symbol in _symbols)
                FilterChip(
                  label: Text(symbol),
                  selected: _selectedSymbols.contains(symbol),
                  onSelected: (_) => setState(() {
                    if (_selectedSymbols.contains(symbol)) {
                      _selectedSymbols.remove(symbol);
                    } else {
                      _selectedSymbols.add(symbol);
                    }
                  }),
                  deleteIcon: _presetSymbols.contains(symbol)
                      ? null
                      : const Icon(Icons.close, size: 14),
                  onDeleted: _presetSymbols.contains(symbol)
                      ? null
                      : () => _removeCustomSymbol(symbol),
                ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceSm),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _symbolInputController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    hintText: 'Add symbol, e.g. USOIL',
                    prefixIcon: Icon(Icons.add_rounded, size: 18),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _addCustomSymbol(),
                ),
              ),
              const SizedBox(width: AppTokens.spaceSm),
              IconButton.filledTonal(
                onPressed: _addCustomSymbol,
                icon: const Icon(Icons.add_rounded, size: 18),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceLg),
          Text(
            'TIMEFRAMES',
            style: AppFonts.body(
              size: AppTokens.fontSizeTiny,
              weight: FontWeight.w700,
              letterSpacing: 0.8,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final tf in _timeframeOptions)
                FilterChip(
                  label: Text(tf),
                  selected: _selectedTimeframes.contains(tf),
                  onSelected: (_) => setState(() {
                    if (_selectedTimeframes.contains(tf)) {
                      _selectedTimeframes.remove(tf);
                    } else {
                      _selectedTimeframes.add(tf);
                    }
                  }),
                ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceLg),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _tvSaving ? null : _saveTradingView,
              icon: _tvSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_sync_outlined, size: 18),
              label: Text(_tvSaving ? 'Syncing...' : 'Save Watchlist'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMt5Card(ColorScheme scheme) {
    final canConnect =
        _riskAcknowledged &&
        !_mt5Saving &&
        _accountController.text.trim().isNotEmpty &&
        _passwordController.text.isNotEmpty &&
        _brokerController.text.trim().isNotEmpty;
    return Container(
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
              Icon(
                Icons.account_balance_wallet_rounded,
                color: AppColors.amber,
                size: 20,
              ),
              const SizedBox(width: AppTokens.spaceSm),
              Text(
                'METATRADER 5',
                style: AppFonts.body(
                  size: 13,
                  weight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceXxs),
          Text(
            'Real account — credentials are sent to your backend once and '
            'never stored on this device.',
            style: AppFonts.body(
              size: AppTokens.captionSize,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTokens.spaceLg),
          TextField(
            controller: _accountController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Account Number',
              prefixIcon: Icon(Icons.numbers_rounded, size: 18),
            ),
          ),
          const SizedBox(height: AppTokens.spaceMd),
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 18,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
          ),
          const SizedBox(height: AppTokens.spaceMd),
          TextField(
            controller: _brokerController,
            decoration: const InputDecoration(
              labelText: 'Broker Server',
              hintText: 'e.g. ICMarkets-Live',
              prefixIcon: Icon(Icons.dns_rounded, size: 18),
            ),
          ),
          const SizedBox(height: AppTokens.spaceLg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 28,
                child: Checkbox(
                  value: _riskAcknowledged,
                  onChanged: (value) =>
                      setState(() => _riskAcknowledged = value ?? false),
                ),
              ),
              const SizedBox(width: AppTokens.spaceXs),
              Expanded(
                child: Text(
                  'I understand this connects a real funded account with '
                  'real money.',
                  style: AppFonts.body(
                    size: AppTokens.bodySize,
                    weight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceLg),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.amber,
                foregroundColor: AppColors.onAmber,
                disabledBackgroundColor: scheme.surfaceContainerHighest,
                disabledForegroundColor: scheme.onSurfaceVariant,
              ),
              onPressed: canConnect ? _connectMt5 : null,
              icon: _mt5Saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.link_rounded, size: 18),
              label: Text(_mt5Saving ? 'Connecting...' : 'Connect Account'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small colored status pill (Connected / Not Connected / Error) matching the
/// SignalChip aesthetic. Colors are semantic: green = connected, grey =
/// not connected, red = error.
class _StatusPill extends StatelessWidget {
  final String status;

  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'connected' => ('CONNECTED', AppColors.bull),
      'error' => ('ERROR', AppColors.bear),
      _ => ('NOT CONNECTED', AppColors.textSecondaryDark),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceSm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppTokens.radiusChip),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppFonts.body(
              size: AppTokens.fontSizeTiny,
              weight: FontWeight.w700,
              letterSpacing: 0.6,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
