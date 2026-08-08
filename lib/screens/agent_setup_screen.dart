import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../config/theme.dart';
import '../services/trading_api_service.dart';
import '../widgets/logo_loader.dart';
import 'strategy_training_screen.dart';

/// Agent Setup (Trading Mode).
///
/// Three ways to configure the co-pilot, all server-side:
///  1. Train from uploads — PDF strategy docs and/or chart images are sent to
///     POST /train, which returns a PROPOSED strategy-profile update. The
///     backend never saves it: the user Confirms (saves via /strategy),
///     Edits, or Discards.
///  2. Config chat — talk to the agent ("list my config", "set max risk to
///     1%", "add a skill named ..."). The agent applies changes only after
///     confirming them in its reply.
///  3. Current configuration — strategy profile, risk rules, alarms, and
///     skills (user-taught vs auto-extracted) with on/off toggles, plus a
///     link to the manual strategy editor.
///
/// TRADING MODE: never add tap-based execution here. All config data and
/// execution decisions live server-side.
class AgentSetupScreen extends StatefulWidget {
  final TradingApiService tradingApiService;

  const AgentSetupScreen({super.key, required this.tradingApiService});

  @override
  State<AgentSetupScreen> createState() => _AgentSetupScreenState();
}

class _AgentSetupScreenState extends State<AgentSetupScreen> {
  final ImagePicker _picker = ImagePicker();

  // --- Load state ---------------------------------------------------------
  bool _loading = true;
  String? _loadError;
  Map<String, dynamic>? _config;
  String _sessionId = 'default';

  // --- Upload / train state ----------------------------------------------
  final List<({String path, String name, String kind})> _selectedFiles = [];
  bool _training = false;
  Map<String, dynamic>? _proposal;

  // --- Config chat state --------------------------------------------------
  final List<Map<String, String>> _chatMessages = [];
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScroll = ScrollController();
  bool _chatSending = false;

  bool get _backendConfigured => widget.tradingApiService.isConfigured;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _chatController.dispose();
    _chatScroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final sessionId = await widget.tradingApiService.getOrCreateSessionId();
    final data = await widget.tradingApiService.getConfig(
      sessionId: sessionId,
    );
    if (!mounted) return;
    setState(() {
      _sessionId = sessionId;
      if (data['status'] == 'error') {
        _loadError = data['message'] as String?;
      } else {
        _config = data;
      }
      _loading = false;
    });
  }

  // --- Uploads ------------------------------------------------------------

  Future<void> _pickFiles() async {
    final kind = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surfaceElevatedDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AppTokens.spaceMd),
            Text(
              'Add training material',
              style: AppFonts.heading(
                size: AppTokens.titleSize,
                color: AppColors.textPrimaryDark,
              ),
            ),
            const SizedBox(height: AppTokens.spaceSm),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: AppColors.textSecondaryDark),
              title: Text('Chart images',
                  style: AppFonts.body(color: AppColors.textPrimaryDark)),
              subtitle: Text('Screenshots of your setups',
                  style: AppFonts.body(
                      size: AppTokens.captionSize,
                      color: AppColors.textSecondaryDark)),
              onTap: () => Navigator.pop(context, 'images'),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined,
                  color: AppColors.textSecondaryDark),
              title: Text('Strategy PDFs',
                  style: AppFonts.body(color: AppColors.textPrimaryDark)),
              subtitle: Text('Rules write-ups, playbooks',
                  style: AppFonts.body(
                      size: AppTokens.captionSize,
                      color: AppColors.textSecondaryDark)),
              onTap: () => Navigator.pop(context, 'pdfs'),
            ),
            const SizedBox(height: AppTokens.spaceMd),
          ],
        ),
      ),
    );
    if (kind == null || !mounted) return;

    if (kind == 'images') {
      final picked = await _picker.pickMultiImage();
      if (picked.isEmpty) return;
      setState(() {
        for (final x in picked) {
          _selectedFiles.add((path: x.path, name: x.name, kind: 'image'));
        }
      });
    } else {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: true,
      );
      if (result == null) return;
      setState(() {
        for (final f in result.files) {
          if (f.path == null) continue;
          _selectedFiles.add((path: f.path!, name: f.name, kind: 'pdf'));
        }
      });
    }
  }

  Future<void> _train() async {
    if (_selectedFiles.isEmpty || _training) return;
    setState(() {
      _training = true;
      _proposal = null;
    });
    final data = await widget.tradingApiService.trainFromUploads(
      _selectedFiles.map((f) => f.path).toList(),
    );
    if (!mounted) return;
    setState(() {
      _training = false;
      if (data['status'] == 'error') {
        _showSnack('Training failed: ${data['message'] ?? 'unknown error'}',
            isError: true);
      } else if (data['proposed'] is Map<String, dynamic>) {
        _proposal = data['proposed'] as Map<String, dynamic>;
      } else {
        _showSnack('The backend returned no proposal.', isError: true);
      }
    });
  }

  /// Merge the current profile with the (possibly partial) proposal, then
  /// save through the existing strategy endpoint. Nothing is saved unless
  /// the user explicitly confirms here.
  Map<String, dynamic> _mergedProfile() {
    final current = _config?['strategy_profile'];
    final p = _proposal ?? <String, dynamic>{};

    String text(dynamic v, String fallback) =>
        v is String && v.trim().isNotEmpty ? v.trim() : fallback;
    List<String> list(dynamic v) =>
        v is List ? v.whereType<String>().toList() : <String>[];

    final merged = <String, dynamic>{
      'rules': '',
      'indicators': <String>[],
      'preferred_pairs': <String>[],
      'timeframes': <String>[],
      'setup_description': '',
    };
    if (current is Map<String, dynamic>) {
      merged['rules'] = text(current['rules'], '');
      merged['indicators'] = list(current['indicators']);
      merged['preferred_pairs'] = list(current['preferred_pairs']);
      merged['timeframes'] = list(current['timeframes']);
      merged['setup_description'] = text(current['setup_description'], '');
    }

    // Overlay the proposal's non-empty fields.
    if (text(p['rules'], '').isNotEmpty) merged['rules'] = text(p['rules'], '');
    if (list(p['indicators']).isNotEmpty) merged['indicators'] = list(p['indicators']);
    if (list(p['preferred_pairs']).isNotEmpty) {
      merged['preferred_pairs'] = list(p['preferred_pairs']);
    }
    if (list(p['timeframes']).isNotEmpty) merged['timeframes'] = list(p['timeframes']);
    if (text(p['setup_description'], '').isNotEmpty) {
      merged['setup_description'] = text(p['setup_description'], '');
    }

    // Risk rules: current risk_rules (from config) merged with proposal.
    final risk = <String, dynamic>{};
    final currentRisk = _config?['risk_rules'];
    if (currentRisk is Map<String, dynamic>) {
      risk.addAll(currentRisk);
    }
    final propRisk = p['risk_tolerance'];
    if (propRisk is Map<String, dynamic>) {
      for (final key in ['max_risk_percent', 'max_daily_loss_percent', 'max_correlated_positions']) {
        final v = propRisk[key];
        if (v is num) risk[key] = v;
      }
    }
    merged['risk_tolerance'] = risk;
    return merged;
  }

  Future<void> _confirmProposal() async {
    final merged = _mergedProfile();
    final hasContent = (merged['rules'] as String).trim().isNotEmpty ||
        (merged['setup_description'] as String).trim().isNotEmpty;
    if (!hasContent) {
      _showSnack(
        'The proposal has no rules or setup description. Edit it first.',
        isError: true,
      );
      return;
    }
    final response = await widget.tradingApiService.saveStrategy(merged);
    if (!mounted) return;
    if (response['status'] == 'ok') {
      _showSnack('Proposal confirmed and saved. Backtest re-running...');
      setState(() => _proposal = null);
      await _load();
    } else {
      _showSnack(
        'Save failed: ${response['message'] ?? 'unknown error'}',
        isError: true,
      );
    }
  }

  Future<void> _editProposal() async {
    final p = _proposal ?? <String, dynamic>{};
    final rules = TextEditingController(
      text: p['rules'] is String ? p['rules'] as String : '',
    );
    final setup = TextEditingController(
      text: p['setup_description'] is String
          ? p['setup_description'] as String
          : '',
    );
    final indicators = TextEditingController(
      text: _commaList(p['indicators']),
    );
    final pairs = TextEditingController(text: _commaList(p['preferred_pairs']));
    final timeframes = TextEditingController(
      text: _commaList(p['timeframes']),
    );
    final risk = TextEditingController(
      text: p['risk_tolerance'] is Map<String, dynamic>
          ? ((p['risk_tolerance'] as Map<String, dynamic>)['max_risk_percent']
                      ?.toString() ??
                  '')
          : '',
    );
    final dailyLoss = TextEditingController(
      text: p['risk_tolerance'] is Map<String, dynamic>
          ? ((p['risk_tolerance'] as Map<String, dynamic>)[
                      'max_daily_loss_percent']
                  ?.toString() ??
              '')
          : '',
    );

    final edited = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceElevatedDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: AppTokens.spaceLg,
          right: AppTokens.spaceLg,
          top: AppTokens.spaceLg,
          bottom: MediaQuery.of(context).viewInsets.bottom + AppTokens.spaceLg,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Edit proposal',
                  style: AppFonts.heading(
                      size: AppTokens.titleSize,
                      color: AppColors.textPrimaryDark)),
              const SizedBox(height: AppTokens.spaceMd),
              _editField(rules, 'Rules', maxLines: 5),
              const SizedBox(height: AppTokens.spaceSm),
              _editField(setup, 'Setup description', maxLines: 3),
              const SizedBox(height: AppTokens.spaceSm),
              _editField(indicators, 'Indicators (comma separated)'),
              const SizedBox(height: AppTokens.spaceSm),
              _editField(pairs, 'Preferred pairs (comma separated)'),
              const SizedBox(height: AppTokens.spaceSm),
              _editField(timeframes, 'Timeframes (comma separated)'),
              const SizedBox(height: AppTokens.spaceSm),
              _editField(risk, 'Max risk % per trade'),
              const SizedBox(height: AppTokens.spaceSm),
              _editField(dailyLoss, 'Max daily loss %'),
              const SizedBox(height: AppTokens.spaceLg),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.amber,
                    foregroundColor: AppColors.onAmber,
                  ),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Save edits'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (edited == true && mounted) {
      setState(() {
        _proposal = {
          'rules': rules.text.trim(),
          'setup_description': setup.text.trim(),
          'indicators': _splitList(indicators.text),
          'preferred_pairs': _splitList(pairs.text),
          'timeframes': _splitList(timeframes.text),
          'risk_tolerance': {
            if (double.tryParse(risk.text.trim()) != null)
              'max_risk_percent': double.parse(risk.text.trim()),
            if (double.tryParse(dailyLoss.text.trim()) != null)
              'max_daily_loss_percent': double.parse(dailyLoss.text.trim()),
          },
        };
      });
      _showSnack('Proposal updated. Confirm to save it.');
    }
  }

  Widget _editField(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: AppFonts.body(color: AppColors.textPrimaryDark),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: AppFonts.body(
            size: AppTokens.captionSize, color: AppColors.textSecondaryDark),
        filled: true,
        fillColor: AppColors.surfaceDark,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusControl),
          borderSide: const BorderSide(color: AppColors.borderDark),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusControl),
          borderSide: const BorderSide(color: AppColors.amber),
        ),
      ),
    );
  }

  String _commaList(dynamic v) {
    if (v is! List) return '';
    return v.whereType<String>().join(', ');
  }

  List<String> _splitList(String text) => text
      .split(',')
      .map((e) => e.trim().toUpperCase())
      .where((e) => e.isNotEmpty)
      .toList();

  // --- Config chat --------------------------------------------------------

  Future<void> _sendChat() async {
    final text = _chatController.text.trim();
    if (text.isEmpty || _chatSending) return;
    setState(() {
      _chatMessages.add({'role': 'user', 'content': text});
      _chatSending = true;
      _chatController.clear();
    });
    _scrollChat();

    final history = _chatMessages
        .sublist(0, _chatMessages.length - 1)
        .map((m) => Map<String, String>.from(m))
        .toList();
    final reply = await widget.tradingApiService.chat(text, history);
    if (!mounted) return;
    setState(() {
      _chatMessages.add({'role': 'assistant', 'content': reply});
      _chatSending = false;
    });
    _scrollChat();
    // Config changes may have been applied via the agent's tools.
    await _load();
  }

  void _scrollChat() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScroll.hasClients) {
        _chatScroll.animateTo(
          _chatScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // --- Toggles ------------------------------------------------------------

  Future<void> _toggleSkill(String name, bool active) async {
    final response = await widget.tradingApiService.setSkillActive(
      sessionId: _sessionId,
      name: name,
      active: active,
    );
    if (!mounted) return;
    if (response['status'] != 'ok') {
      _showSnack('Could not update skill: ${response['message']}',
          isError: true);
    }
    await _load();
  }

  Future<void> _toggleAlarm(String id, bool active) async {
    final response = await widget.tradingApiService.setAlarmActive(
      id: id,
      active: active,
    );
    if (!mounted) return;
    if (response['status'] != 'ok') {
      _showSnack('Could not update alarm: ${response['message']}',
          isError: true);
    }
    await _load();
  }

  // --- UI -----------------------------------------------------------------

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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Agent Setup'),
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
                          'the agent, chat about configuration, and manage '
                          'skills and alarms.',
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
                  _buildTrainCard(scheme),
                  const SizedBox(height: AppTokens.spaceXl),
                  _buildChatCard(scheme),
                  const SizedBox(height: AppTokens.spaceXl),
                  _buildConfigCard(scheme),
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

  Widget _card(ColorScheme scheme, {required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(AppTokens.spaceLg),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        boxShadow: AppShadows.card,
      ),
      child: child,
    );
  }

  // --- Train card ---------------------------------------------------------

  Widget _buildTrainCard(ColorScheme scheme) {
    return _card(
      scheme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.upload_file_outlined,
                  color: scheme.onSurfaceVariant, size: 20),
              const SizedBox(width: AppTokens.spaceSm),
              Text('Train from uploads',
                  style: AppFonts.heading(
                      size: AppTokens.titleSize,
                      color: AppColors.textPrimaryDark)),
            ],
          ),
          const SizedBox(height: AppTokens.spaceXs),
          Text(
            'Upload strategy PDFs or chart images. The backend proposes a '
            'strategy profile — you confirm, edit, or discard it. Nothing is '
            'saved until you confirm.',
            style: AppFonts.body(
                size: AppTokens.captionSize,
                color: AppColors.textSecondaryDark),
          ),
          const SizedBox(height: AppTokens.spaceMd),
          Wrap(
            spacing: AppTokens.spaceSm,
            runSpacing: AppTokens.spaceSm,
            children: [
              for (final f in _selectedFiles)
                InputChip(
                  label: Text(f.name,
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.body(
                          size: AppTokens.captionSize,
                          color: AppColors.textPrimaryDark)),
                  avatar: Icon(
                    f.kind == 'pdf'
                        ? Icons.picture_as_pdf_outlined
                        : Icons.image_outlined,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                  backgroundColor: AppColors.surfaceDark,
                  side: const BorderSide(color: AppColors.borderDark),
                  onDeleted: () {
                    setState(() {
                      _selectedFiles.remove(f);
                      if (_proposal != null) _proposal = null;
                    });
                  },
                ),
              ActionChip(
                avatar: Icon(Icons.add_rounded,
                    size: 16, color: scheme.onSurfaceVariant),
                label: Text('Add files',
                    style: AppFonts.body(
                        size: AppTokens.captionSize,
                        color: scheme.onSurfaceVariant)),
                backgroundColor: AppColors.surfaceDark,
                side: const BorderSide(color: AppColors.borderDark),
                onPressed: _pickFiles,
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceMd),
          if (_training)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppTokens.spaceMd),
              child: Center(child: LogoLoader(size: 36)),
            )
          else if (_proposal != null)
            _buildProposalCard(scheme)
          else
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.amber,
                  foregroundColor: AppColors.onAmber,
                  disabledBackgroundColor: AppColors.amberDim,
                ),
                onPressed: _selectedFiles.isEmpty ? null : _train,
                icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                label: const Text('Generate proposal'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProposalCard(ColorScheme scheme) {
    final p = _proposal!;
    final parseError = p['parse_error'];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTokens.spaceMd),
      decoration: BoxDecoration(
        color: AppColors.amber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTokens.radiusControl),
      ),
      child: parseError is String
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Proposal could not be parsed',
                    style: AppFonts.body(
                        weight: FontWeight.w600,
                        color: AppColors.bear)),
                const SizedBox(height: AppTokens.spaceXs),
                Text(
                  p['raw'] is String ? p['raw'] as String : parseError,
                  style: AppFonts.body(
                      size: AppTokens.captionSize,
                      color: AppColors.textSecondaryDark),
                ),
                const SizedBox(height: AppTokens.spaceMd),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => setState(() => _proposal = null),
                      child: const Text('Discard'),
                    ),
                  ],
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Proposed changes',
                    style: AppFonts.heading(
                        size: AppTokens.titleSize,
                        color: AppColors.amberStrong)),
                if (p['summary'] is String &&
                    (p['summary'] as String).trim().isNotEmpty) ...[
                  const SizedBox(height: AppTokens.spaceXs),
                  Text(p['summary'] as String,
                      style: AppFonts.body(
                          size: AppTokens.captionSize,
                          color: AppColors.textPrimaryDark)),
                ],
                const SizedBox(height: AppTokens.spaceMd),
                _proposalLine('Rules', p['rules']),
                _proposalLine('Setup', p['setup_description']),
                _proposalLine('Indicators', _commaList(p['indicators'])),
                _proposalLine('Pairs', _commaList(p['preferred_pairs'])),
                _proposalLine('Timeframes', _commaList(p['timeframes'])),
                if (p['risk_tolerance'] is Map<String, dynamic>) ...[
                  _proposalLine(
                      'Max risk/trade',
                      (p['risk_tolerance'] as Map<String, dynamic>)[
                              'max_risk_percent']
                          ?.toString()),
                  _proposalLine(
                      'Max daily loss',
                      (p['risk_tolerance'] as Map<String, dynamic>)[
                              'max_daily_loss_percent']
                          ?.toString()),
                ],
                const SizedBox(height: AppTokens.spaceMd),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => setState(() => _proposal = null),
                      child: const Text('Discard'),
                    ),
                    TextButton(
                      onPressed: _editProposal,
                      child: const Text('Edit'),
                    ),
                    const SizedBox(width: AppTokens.spaceXs),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.amber,
                        foregroundColor: AppColors.onAmber,
                      ),
                      onPressed: _confirmProposal,
                      child: const Text('Confirm & save'),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _proposalLine(String label, dynamic value) {
    final text = value is String && value.trim().isNotEmpty
        ? value.trim()
        : null;
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.spaceXs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label: ',
              style: AppFonts.body(
                  size: AppTokens.captionSize,
                  weight: FontWeight.w600,
                  color: AppColors.amber)),
          Expanded(
            child: Text(text,
                style: AppFonts.body(
                    size: AppTokens.captionSize,
                    color: AppColors.textSecondaryDark)),
          ),
        ],
      ),
    );
  }

  // --- Chat card ----------------------------------------------------------

  Widget _buildChatCard(ColorScheme scheme) {
    return _card(
      scheme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.forum_outlined,
                  color: scheme.onSurfaceVariant, size: 20),
              const SizedBox(width: AppTokens.spaceSm),
              Text('Configure by conversation',
                  style: AppFonts.heading(
                      size: AppTokens.titleSize,
                      color: AppColors.textPrimaryDark)),
            ],
          ),
          const SizedBox(height: AppTokens.spaceXs),
          Text(
            'Ask the agent to change your setup: "list my config", "set max '
            'risk to 1%", "add a skill named ...", "set a gold alarm". '
            'Changes are only applied after the agent confirms them.',
            style: AppFonts.body(
                size: AppTokens.captionSize,
                color: AppColors.textSecondaryDark),
          ),
          const SizedBox(height: AppTokens.spaceMd),
          Container(
            height: 260,
            decoration: BoxDecoration(
              color: AppColors.surfaceDark,
              borderRadius: BorderRadius.circular(AppTokens.radiusControl),
            ),
            child: _chatMessages.isEmpty
                ? Center(
                    child: Text(
                      'No messages yet.',
                      style: AppFonts.body(
                          size: AppTokens.captionSize,
                          color: AppColors.textMutedDark),
                    ),
                  )
                : ListView.builder(
                    controller: _chatScroll,
                    padding: const EdgeInsets.all(AppTokens.spaceMd),
                    itemCount: _chatMessages.length,
                    itemBuilder: (context, index) {
                      final m = _chatMessages[index];
                      final isUser = m['role'] == 'user';
                      return Align(
                        alignment: isUser
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppTokens.spaceMd,
                            vertical: AppTokens.spaceSm,
                          ),
                          constraints: BoxConstraints(
                            maxWidth:
                                MediaQuery.of(context).size.width * 0.72,
                          ),
                          decoration: BoxDecoration(
                            color: isUser
                                ? AppColors.amber.withValues(alpha: 0.18)
                                : AppColors.surfaceElevatedDark,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isUser
                                  ? AppColors.amber.withValues(alpha: 0.3)
                                  : AppColors.borderDark,
                            ),
                          ),
                          child: Text(
                            m['content'] ?? '',
                            style: AppFonts.body(
                                size: AppTokens.captionSize,
                                color: AppColors.textPrimaryDark),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _chatController,
                  style: AppFonts.body(color: AppColors.textPrimaryDark),
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendChat(),
                  decoration: InputDecoration(
                    hintText: 'Tell the agent what to change...',
                    hintStyle: AppFonts.body(
                        size: AppTokens.captionSize,
                        color: AppColors.textMutedDark),
                    filled: true,
                    fillColor: AppColors.surfaceDark,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppTokens.spaceMd,
                      vertical: AppTokens.spaceMd,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AppTokens.radiusControl),
                      borderSide: const BorderSide(color: AppColors.borderDark),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AppTokens.radiusControl),
                      borderSide: const BorderSide(color: AppColors.amber),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppTokens.spaceSm),
              IconButton.filled(
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.amber,
                  foregroundColor: AppColors.onAmber,
                ),
                icon: _chatSending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.onAmber),
                      )
                    : const Icon(Icons.send_rounded, size: 18),
                onPressed: _chatSending ? null : _sendChat,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- Config card --------------------------------------------------------

  Widget _buildConfigCard(ColorScheme scheme) {
    final cfg = _config;
    final profile = cfg?['strategy_profile'];
    final risk = cfg?['risk_rules'];
    final alarms = cfg?['alarms'];
    final skills = cfg?['skills'];

    return _card(
      scheme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune_rounded,
                  color: scheme.onSurfaceVariant, size: 20),
              const SizedBox(width: AppTokens.spaceSm),
              Text('Current configuration',
                  style: AppFonts.heading(
                      size: AppTokens.titleSize,
                      color: AppColors.textPrimaryDark)),
            ],
          ),
          const SizedBox(height: AppTokens.spaceMd),

          // Strategy profile
          _sectionLabel('Strategy profile'),
          if (profile is Map<String, dynamic>) ...[
            _kvRow('Rules',
                profile['rules'] is String ? profile['rules'] as String : ''),
            _kvRow(
                'Setup',
                profile['setup_description'] is String
                    ? profile['setup_description'] as String
                    : ''),
            _kvRow('Indicators', _commaList(profile['indicators'])),
            _kvRow('Pairs', _commaList(profile['preferred_pairs'])),
            _kvRow('Timeframes', _commaList(profile['timeframes'])),
          ] else
            Text(
              'No strategy profile yet. Train one from uploads above or edit '
              'manually below.',
              style: AppFonts.body(
                  size: AppTokens.captionSize,
                  color: AppColors.textSecondaryDark),
            ),
          const SizedBox(height: AppTokens.spaceMd),

          // Risk rules
          _sectionLabel('Risk rules'),
          if (risk is Map<String, dynamic>) ...[
            _kvRow('Max risk per trade',
                risk['max_risk_percent']?.toString() ?? '--'),
            _kvRow('Max daily loss',
                risk['max_daily_loss_percent']?.toString() ?? '--'),
          ] else
            Text(
              'Defaults: 2% per trade, 5% daily loss.',
              style: AppFonts.body(
                  size: AppTokens.captionSize,
                  color: AppColors.textSecondaryDark),
            ),
          const SizedBox(height: AppTokens.spaceMd),

          // Alarms
          _sectionLabel('Alarms'),
          if (alarms is List && alarms.isNotEmpty)
            for (final alarm in alarms)
              if (alarm is Map<String, dynamic>)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  activeThumbColor: AppColors.amber,
                  title: Text(
                    '${alarm['symbol']} ${alarm['timeframe']}',
                    style: AppFonts.body(
                        weight: FontWeight.w600,
                        color: AppColors.textPrimaryDark),
                  ),
                  subtitle: Text(
                    alarm['condition_description'] is String
                        ? alarm['condition_description'] as String
                        : '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppFonts.body(
                        size: AppTokens.fontSizeTiny,
                        color: AppColors.textSecondaryDark),
                  ),
                  value: alarm['active'] == true,
                  onChanged: (v) => _toggleAlarm(
                    alarm['id'] as String? ?? '',
                    v,
                  ),
                )
          else
            Text(
              'No alarms set. Ask the agent in the chat above, e.g. "set an '
              'alarm for XAUUSD H4 when it breaks the range".',
              style: AppFonts.body(
                  size: AppTokens.captionSize,
                  color: AppColors.textSecondaryDark),
            ),
          const SizedBox(height: AppTokens.spaceMd),

          // Skills
          _sectionLabel('Skills'),
          if (skills is Map<String, dynamic> &&
              _skillCount(skills) > 0) ...[
            _skillsGroup(scheme, 'User-taught', skills['user_taught']),
            const SizedBox(height: AppTokens.spaceSm),
            _skillsGroup(scheme, 'Auto-extracted', skills['auto_extracted']),
          ] else
            Text(
              'No skills yet. Winning trades are captured automatically, and '
              'you can teach skills in the chat above.',
              style: AppFonts.body(
                  size: AppTokens.captionSize,
                  color: AppColors.textSecondaryDark),
            ),
          const SizedBox(height: AppTokens.spaceLg),

          // Manual edit
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: scheme.onSurfaceVariant,
                side: const BorderSide(color: AppColors.borderDark),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StrategyTrainingScreen(
                      tradingApiService: widget.tradingApiService,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Edit strategy manually'),
            ),
          ),
        ],
      ),
    );
  }

  int _skillCount(Map<String, dynamic> skills) {
    var count = 0;
    for (final key in ['user_taught', 'auto_extracted']) {
      final list = skills[key];
      if (list is List) count += list.length;
    }
    return count;
  }

  Widget _skillsGroup(
    ColorScheme scheme,
    String label,
    dynamic list,
  ) {
    if (list is! List || list.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: AppFonts.body(
            size: AppTokens.fontSizeTiny,
            weight: FontWeight.w700,
            letterSpacing: 0.8,
            color: AppColors.textMutedDark,
          ),
        ),
        for (final skill in list)
          if (skill is Map<String, dynamic>)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              activeThumbColor: AppColors.amber,
              title: Text(
                skill['name'] is String ? skill['name'] as String : 'skill',
                style: AppFonts.body(
                    weight: FontWeight.w600,
                    color: AppColors.textPrimaryDark),
              ),
              subtitle: Text(
                skill['description'] is String
                    ? skill['description'] as String
                    : '',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppFonts.body(
                    size: AppTokens.fontSizeTiny,
                    color: AppColors.textSecondaryDark),
              ),
              value: skill['active'] == true,
              onChanged: (v) => _toggleSkill(
                skill['name'] is String ? skill['name'] as String : '',
                v,
              ),
            ),
      ],
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.spaceXs),
      child: Text(
        text.toUpperCase(),
        style: AppFonts.body(
          size: AppTokens.fontSizeTiny,
          weight: FontWeight.w700,
          letterSpacing: 0.8,
          color: AppColors.textSecondaryDark,
        ),
      ),
    );
  }

  Widget _kvRow(String label, String value) {
    final trimmed = value.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.spaceXs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: AppFonts.body(
                    size: AppTokens.captionSize,
                    weight: FontWeight.w600,
                    color: AppColors.textSecondaryDark)),
          ),
          Expanded(
            child: Text(
              trimmed.isEmpty ? '—' : trimmed,
              style: AppFonts.body(
                  size: AppTokens.captionSize,
                  color: AppColors.textPrimaryDark),
            ),
          ),
        ],
      ),
    );
  }
}
