import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../config/theme.dart';
import '../services/trading_api_service.dart';
import '../widgets/logo_loader.dart';
import '../widgets/signal_chip.dart';
import '../widgets/stat_card.dart';

/// Train My Strategy (Trading Mode only).
///
/// Lets the user define their trading strategy — rules, indicators, pairs,
/// timeframes, risk tolerance and an "A+ setup" description — and save it to
/// the backend (POST /strategy). The backend stores it versioned + encrypted,
/// re-runs the backtest automatically, and returns real computed stats
/// (win_rate / sample_size) which this screen displays read-only via
/// GET /strategy. Optional chart screenshots can be attached as reference
/// examples; only their names are sent, nothing sensitive stays on-device.
///
/// TRADING MODE: never add tap-based execution here. All strategy data and
/// execution decisions live server-side.
class StrategyTrainingScreen extends StatefulWidget {
  final TradingApiService tradingApiService;

  const StrategyTrainingScreen({
    super.key,
    required this.tradingApiService,
  });

  @override
  State<StrategyTrainingScreen> createState() => _StrategyTrainingScreenState();
}

class _StrategyTrainingScreenState extends State<StrategyTrainingScreen> {
  static const List<String> _presetIndicators = [
    'RSI',
    'MACD',
    'EMA20',
    'EMA50',
    'EMA200',
    'ATR',
    'Stochastic',
  ];
  static const List<String> _presetPairs = [
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
    'USOIL',
  ];
  static const List<String> _timeframeOptions = ['M15', 'H1', 'H4', 'D1'];

  final ImagePicker _picker = ImagePicker();

  // --- Load / save state ---------------------------------------------------
  bool _loading = true;
  bool _saving = false;
  bool _backtesting = false;
  String? _loadError;

  // --- Form fields ---------------------------------------------------------
  final TextEditingController _rulesController = TextEditingController();
  final TextEditingController _setupController = TextEditingController();
  final TextEditingController _maxRiskController = TextEditingController();
  final TextEditingController _maxDailyLossController = TextEditingController();
  final TextEditingController _indicatorInputController = TextEditingController();
  final TextEditingController _pairInputController = TextEditingController();

  final List<String> _indicators = List.of(_presetIndicators);
  final Set<String> _selectedIndicators = {};
  final List<String> _pairs = List.of(_presetPairs);
  final Set<String> _selectedPairs = {};
  final Set<String> _selectedTimeframes = {};

  // Reference screenshots: names go to the backend, paths render thumbnails.
  final List<String> _exampleNames = [];
  final List<String> _examplePaths = [];

  // --- Backtest display ----------------------------------------------------
  Map<String, dynamic>? _backtest;
  int? _version;
  String? _updatedAt;

  bool get _backendConfigured => widget.tradingApiService.isConfigured;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _rulesController.dispose();
    _setupController.dispose();
    _maxRiskController.dispose();
    _maxDailyLossController.dispose();
    _indicatorInputController.dispose();
    _pairInputController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final data = await widget.tradingApiService.getStrategy();
    if (!mounted) return;
    if (data['status'] == 'ok') {
      final profile = data['profile'];
      if (profile is Map<String, dynamic>) {
        _rulesController.text = profile['rules'] is String
            ? profile['rules'] as String
            : '';
        _setupController.text = profile['setup_description'] is String
            ? profile['setup_description'] as String
            : '';
        final risk = profile['risk_tolerance'];
        if (risk is Map<String, dynamic>) {
          _maxRiskController.text = (risk['max_risk_percent'] ?? '').toString();
          _maxDailyLossController.text =
              (risk['max_daily_loss_percent'] ?? '').toString();
        }
        _selectedIndicators
          ..clear()
          ..addAll(_strList(profile['indicators']));
        _selectedPairs
          ..clear()
          ..addAll(_strList(profile['preferred_pairs']));
        _selectedTimeframes
          ..clear()
          ..addAll(_strList(profile['timeframes']));
        _exampleNames
          ..clear()
          ..addAll(_strList(profile['reference_examples']));
        _examplePaths.clear();
      }
      setState(() {
        _backtest = data['backtest'] is Map<String, dynamic>
            ? data['backtest'] as Map<String, dynamic>
            : null;
        _version = data['version'] is int ? data['version'] as int : null;
        _updatedAt = data['updated_at'] is String
            ? data['updated_at'] as String
            : null;
        _loading = false;
      });
    } else if (data['status'] == 'not_found') {
      setState(() {
        _backtest = null;
        _loading = false;
      });
    } else {
      setState(() {
        _loadError = data['message'] is String
            ? data['message'] as String
            : 'Could not load your strategy.';
        _loading = false;
      });
    }
  }

  List<String> _strList(dynamic value) {
    if (value is List) return value.whereType<String>().toList();
    return <String>[];
  }

  bool get _canSave {
    final hasRules = _rulesController.text.trim().isNotEmpty ||
        _setupController.text.trim().isNotEmpty;
    return _backendConfigured &&
        hasRules &&
        _selectedPairs.isNotEmpty &&
        _selectedTimeframes.isNotEmpty;
  }

  Map<String, dynamic> _buildProfile() {
    return {
      'rules': _rulesController.text.trim(),
      'indicators': _selectedIndicators.toList(),
      'preferred_pairs': _selectedPairs.toList(),
      'timeframes': _selectedTimeframes.toList(),
      'risk_tolerance': {
        'max_risk_percent':
            double.tryParse(_maxRiskController.text.trim()) ?? 2,
        'max_daily_loss_percent':
            double.tryParse(_maxDailyLossController.text.trim()) ?? 5,
      },
      'setup_description': _setupController.text.trim(),
      'reference_examples': _exampleNames,
    };
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    final response = await widget.tradingApiService.saveStrategy(_buildProfile());
    if (!mounted) return;
    setState(() => _saving = false);
    if (response['status'] == 'ok') {
      _showSnack(
        'Strategy saved. Backtest is re-running — results appear in a moment.',
      );
      // The backend re-runs the backtest in the background; pull the fresh
      // stats shortly after so the read-only display updates.
      await Future<void>.delayed(const Duration(seconds: 10));
      if (mounted) await _load();
    } else {
      _showSnack(
        'Save failed: ${response['message'] ?? 'unknown error'}',
        isError: true,
      );
    }
  }

  Future<void> _rerunBacktest() async {
    if (!_backendConfigured) return;
    setState(() => _backtesting = true);
    final response = await widget.tradingApiService.runBacktest();
    if (!mounted) return;
    setState(() => _backtesting = false);
    if (response['status'] == 'ok') {
      _showSnack('Backtest complete.');
      await _load();
    } else {
      _showSnack(
        'Backtest failed: ${response['message'] ?? 'unknown error'}',
        isError: true,
      );
    }
  }

  Future<void> _attachScreenshot() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    setState(() {
      _exampleNames.add(picked.name);
      _examplePaths.add(picked.path);
    });
  }

  void _addCustom(
    List<String> source,
    Set<String> selected,
    TextEditingController input,
  ) {
    final value = input.text.trim().toUpperCase();
    if (value.isEmpty) return;
    setState(() {
      if (!source.contains(value)) source.add(value);
      selected.add(value);
      input.clear();
    });
  }

  void _removeExample(int index) {
    setState(() {
      _exampleNames.removeAt(index);
      _examplePaths.removeAt(index);
    });
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

  // --- UI ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Train My Strategy'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: LogoLoader())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  AppTokens.spaceLg,
                  AppTokens.spaceSm,
                  AppTokens.spaceLg,
                  AppTokens.spaceXxl,
                ),
                children: [
                  if (!_backendConfigured) ...[
                    _buildNotice(
                      scheme,
                      icon: Icons.link_off_rounded,
                      text:
                          'Set your Trading Backend URL in Settings to train '
                          'and backtest a strategy. No data is sent anywhere '
                          'until a backend is configured.',
                    ),
                    const SizedBox(height: AppTokens.spaceLg),
                  ] else if (_loadError != null) ...[
                    _buildNotice(
                      scheme,
                      icon: Icons.cloud_off_outlined,
                      text: _loadError!,
                      isError: true,
                    ),
                    const SizedBox(height: AppTokens.spaceLg),
                  ],
                  _buildBacktestCard(scheme),
                  const SizedBox(height: AppTokens.spaceXl),
                  _buildStrategyCard(scheme),
                ],
              ),
            ),
    );
  }

  Widget _buildNotice(
    ColorScheme scheme, {
    required IconData icon,
    required String text,
    bool isError = false,
  }) {
    final color = isError ? AppColors.bear : AppColors.amber;
    return Container(
      padding: const EdgeInsets.all(AppTokens.spaceMd),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTokens.radiusControl),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: AppTokens.spaceSm),
          Expanded(
            child: Text(
              text,
              style: AppFonts.body(
                size: AppTokens.captionSize,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBacktestCard(ColorScheme scheme) {
    final bt = _backtest;
    final hasData =
        bt != null && bt['sample_size'] is num && (bt['sample_size'] as num) > 0;
    final winRate =
        hasData ? ((bt['win_rate'] as num) * 100).toStringAsFixed(1) : '--';
    final sample = hasData ? '${bt['sample_size']}' : '--';
    final avgRr = hasData ? (bt['avg_rr'] as num).toStringAsFixed(2) : '--';
    final wins = hasData ? '${bt['wins']}' : '--';
    final losses = hasData ? '${bt['losses']}' : '--';

    return Container(
      padding: const EdgeInsets.all(AppTokens.spaceLg),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.science_outlined,
                  color: scheme.onSurfaceVariant, size: 20),
              const SizedBox(width: AppTokens.spaceSm),
              Text(
                'BACKTEST RESULTS',
                style: AppFonts.body(
                  size: 13,
                  weight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: scheme.onSurface,
                ),
              ),
              const Spacer(),
              if (hasData)
                SignalChip.neutral('REAL DATA')
              else
                SignalChip.neutral('NO DATA YET'),
            ],
          ),
          const SizedBox(height: AppTokens.spaceMd),
          Row(
            children: [
              Expanded(
                child: StatCard(
                  label: 'Win Rate',
                  value: '$winRate%',
                  valueColor: hasData && (bt['win_rate'] as num) >= 0.5
                      ? AppColors.bull
                      : AppColors.amber,
                ),
              ),
              const SizedBox(width: AppTokens.spaceSm),
              Expanded(
                child: StatCard(
                  label: 'Sample Size',
                  value: sample,
                  valueColor: scheme.onSurface,
                ),
              ),
              const SizedBox(width: AppTokens.spaceSm),
              Expanded(
                child: StatCard(
                  label: 'Avg R:R',
                  value: avgRr,
                  valueColor: hasData && (bt['avg_rr'] as num) >= 1
                      ? AppColors.bull
                      : AppColors.bear,
                ),
              ),
            ],
          ),
          if (hasData) ...[
            const SizedBox(height: AppTokens.spaceSm),
            Text(
              'Wins $wins · Losses $losses'
              '${_version != null ? ' · Strategy v$_version' : ''}'
              '${_updatedAt != null ? ' · ${_updatedAt!.split('T').first}' : ''}',
              style: AppFonts.body(
                size: AppTokens.captionSize,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          if (!hasData && _backendConfigured) ...[
            const SizedBox(height: AppTokens.spaceSm),
            Text(
              'Save your strategy to run the first backtest. Results are '
              'computed from real market data — never guessed.',
              style: AppFonts.body(
                size: AppTokens.captionSize,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: AppTokens.spaceMd),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _backendConfigured && !_backtesting
                  ? _rerunBacktest
                  : null,
              icon: _backtesting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow_rounded, size: 18),
              label: Text(_backtesting ? 'Backtesting...' : 'Re-run Backtest'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChipField(
    ColorScheme scheme, {
    required String label,
    required List<String> options,
    required Set<String> selected,
    TextEditingController? inputController,
    String? hint,
    VoidCallback? onAdd,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
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
            for (final option in options)
              FilterChip(
                label: Text(option),
                selected: selected.contains(option),
                onSelected: (_) => setState(() {
                  if (selected.contains(option)) {
                    selected.remove(option);
                  } else {
                    selected.add(option);
                  }
                }),
              ),
          ],
        ),
        if (inputController != null && hint != null && onAdd != null) ...[
          const SizedBox(height: AppTokens.spaceSm),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: inputController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    hintText: hint,
                    prefixIcon: const Icon(Icons.add_rounded, size: 18),
                    isDense: true,
                  ),
                  onSubmitted: (_) => onAdd(),
                ),
              ),
              const SizedBox(width: AppTokens.spaceSm),
              IconButton.filledTonal(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded, size: 18),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildStrategyCard(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(AppTokens.spaceLg),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune_rounded, color: scheme.onSurfaceVariant, size: 20),
              const SizedBox(width: AppTokens.spaceSm),
              Text(
                'STRATEGY PROFILE',
                style: AppFonts.body(
                  size: 13,
                  weight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceLg),
          TextField(
            controller: _rulesController,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Entry & Exit Rules',
              hintText: 'e.g. Enter long when RSI reclaims 50 with EMA20 '
                  'above EMA50; exit on RSI > 70 or 2R target...',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: AppTokens.spaceMd),
          _buildChipField(
            scheme,
            label: 'INDICATORS',
            options: _indicators,
            selected: _selectedIndicators,
            inputController: _indicatorInputController,
            hint: 'Add indicator, e.g. VWAP',
            onAdd: () => _addCustom(
              _indicators,
              _selectedIndicators,
              _indicatorInputController,
            ),
          ),
          const SizedBox(height: AppTokens.spaceLg),
          _buildChipField(
            scheme,
            label: 'PREFERRED PAIRS',
            options: _pairs,
            selected: _selectedPairs,
            inputController: _pairInputController,
            hint: 'Add pair, e.g. USOIL',
            onAdd: () =>
                _addCustom(_pairs, _selectedPairs, _pairInputController),
          ),
          const SizedBox(height: AppTokens.spaceLg),
          _buildChipField(
            scheme,
            label: 'TIMEFRAMES',
            options: _timeframeOptions,
            selected: _selectedTimeframes,
          ),
          const SizedBox(height: AppTokens.spaceLg),
          Text(
            'RISK TOLERANCE',
            style: AppFonts.body(
              size: AppTokens.fontSizeTiny,
              weight: FontWeight.w700,
              letterSpacing: 0.8,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _maxRiskController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Max Risk / Trade %',
                    prefixIcon: Icon(Icons.shield_outlined, size: 18),
                  ),
                ),
              ),
              const SizedBox(width: AppTokens.spaceSm),
              Expanded(
                child: TextField(
                  controller: _maxDailyLossController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Max Daily Loss %',
                    prefixIcon: Icon(Icons.warning_amber_rounded, size: 18),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceLg),
          TextField(
            controller: _setupController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'A+ Setup Description',
              hintText: 'Describe what a valid "A+ setup" looks like for you '
                  '— the exact confluence of conditions you wait for.',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: AppTokens.spaceLg),
          Text(
            'REFERENCE CHARTS (OPTIONAL)',
            style: AppFonts.body(
              size: AppTokens.fontSizeTiny,
              weight: FontWeight.w700,
              letterSpacing: 0.8,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          if (_examplePaths.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < _examplePaths.length; i++)
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius:
                            BorderRadius.circular(AppTokens.radiusControl),
                        child: Image.file(
                          File(_examplePaths[i]),
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: -6,
                        right: -6,
                        child: GestureDetector(
                          onTap: () => _removeExample(i),
                          child: Container(
                            decoration: const BoxDecoration(
                              color: AppColors.bear,
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(3),
                            child: const Icon(
                              Icons.close,
                              size: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: AppTokens.spaceSm),
          ],
          OutlinedButton.icon(
            onPressed: _attachScreenshot,
            icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
            label: const Text('Attach Chart Screenshot'),
          ),
          const SizedBox(height: AppTokens.spaceLg),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _canSave && !_saving ? _save : null,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined, size: 18),
              label: Text(_saving ? 'Saving...' : 'Save Strategy'),
            ),
          ),
        ],
      ),
    );
  }
}
