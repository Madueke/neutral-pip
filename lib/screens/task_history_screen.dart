import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/theme.dart';
import '../services/task_history_logger.dart';
import '../widgets/stat_card.dart';

class TaskHistoryScreen extends StatefulWidget {
  const TaskHistoryScreen({super.key});

  @override
  State<TaskHistoryScreen> createState() => _TaskHistoryScreenState();
}

class _TaskHistoryScreenState extends State<TaskHistoryScreen> {
  List<Map<String, dynamic>> _history = [];
  Map<String, dynamic>? _analytics;
  bool _isLoading = true;
  String _statusFilter = 'All';

  static const List<String> _filters = ['All', 'Success', 'Failed'];

  List<Map<String, dynamic>> get _filteredHistory => _statusFilter == 'All'
      ? _history
      : _history
            .where(
              (t) => (t['status'] as String? ?? 'Unknown') == _statusFilter,
            )
            .toList();

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    final history = await TaskHistoryLogger.readHistory();
    final analytics = await TaskHistoryLogger.getAnalytics();
    setState(() {
      _history = history;
      _analytics = analytics;
      _isLoading = false;
    });
  }

  Future<void> _clearHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Task History'),
        content: const Text(
          'Are you sure you want to delete all task history?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Clear',
              style: AppFonts.body(
                weight: FontWeight.w700,
                color: AppColors.bear,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await TaskHistoryLogger.clearHistory();
      _loadHistory();
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Success':
        return AppColors.bull;
      case 'Failed':
        return AppColors.bear;
      case 'Cancelled':
        return AppColors.amber;
      default:
        return AppColors.textSecondaryDark;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'Success':
        return Icons.check_circle;
      case 'Failed':
        return Icons.cancel;
      case 'Cancelled':
        return Icons.stop_circle;
      default:
        return Icons.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filtered = _filteredHistory;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Task History (${_history.length})',
          style: AppFonts.heading(
            size: AppTokens.titleSize,
            weight: FontWeight.w700,
            color: scheme.onSurface,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: 'Clear history',
            onPressed: _history.isEmpty ? null : _clearHistory,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _history.isEmpty
          ? _buildEmptyState(context)
          : Column(
              children: [
                if (_analytics != null && _analytics!['totalTasks'] > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: StatCard(
                            label: 'Total',
                            value: _analytics!['totalTasks'].toString(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: StatCard(
                            label: 'Success',
                            value: _analytics!['successCount'].toString(),
                            valueColor: AppColors.bull,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: StatCard(
                            label: 'Failed',
                            value: _analytics!['failedCount'].toString(),
                            valueColor: AppColors.bear,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: StatCard(
                            label: 'Rate',
                            value:
                                '${(_analytics!['successRate'] * 100).toStringAsFixed(1)}%',
                          ),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    children: [
                      for (final f in _filters)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(
                              f,
                              style: AppFonts.body(
                                size: AppTokens.captionSize,
                                weight: _statusFilter == f
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: _statusFilter == f
                                    ? AppColors.onAmber
                                    : scheme.onSurfaceVariant,
                              ),
                            ),
                            selected: _statusFilter == f,
                            selectedColor: scheme.primary,
                            checkmarkColor: AppColors.onAmber,
                            backgroundColor: scheme.surfaceContainerHighest,
                            side: BorderSide(
                              color: _statusFilter == f
                                  ? scheme.primary
                                  : scheme.outlineVariant,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AppTokens.radiusChip,
                              ),
                            ),
                            onSelected: (_) =>
                                setState(() => _statusFilter = f),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Text(
                            'No ${_statusFilter.toLowerCase()} tasks.',
                            style: AppFonts.body(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: filtered.length,
                          padding: const EdgeInsets.all(16),
                          itemBuilder: (context, index) {
                            final task = filtered[index];
                            final date = DateTime.tryParse(
                              task['timestamp'] ?? '',
                            );
                            final dateStr = date != null
                                ? DateFormat('MMM d, y h:mm a').format(date)
                                : 'Unknown Date';
                            final status =
                                task['status'] as String? ?? 'Unknown';
                            final statusColor = _getStatusColor(status);

                            return Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: scheme.surface,
                                borderRadius: BorderRadius.circular(
                                  AppTokens.radiusCard,
                                ),
                                border: Border.all(
                                  color: scheme.outlineVariant,
                                  width: AppTokens.borderWidth,
                                ),
                                boxShadow: AppShadows.card,
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: ExpansionTile(
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(
                                      alpha: isDark ? 0.14 : 0.1,
                                    ),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    _getStatusIcon(status),
                                    color: statusColor,
                                    size: 24,
                                  ),
                                ),
                                title: Text(
                                  task['goal'] ?? 'Unknown Goal',
                                  style: AppFonts.body(
                                    weight: FontWeight.w700,
                                    color: scheme.onSurface,
                                  ),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Row(
                                    children: [
                                      Text(
                                        dateStr,
                                        style: AppFonts.body(
                                          size: 12,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                      const Spacer(),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: scheme.surfaceContainerHighest,
                                          borderRadius: BorderRadius.circular(
                                            AppTokens.radiusChip,
                                          ),
                                        ),
                                        child: Text(
                                          '${task['total_tokens'] ?? 0} tokens',
                                          style: AppFonts.body(
                                            size: 11,
                                            weight: FontWeight.w600,
                                            color: scheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: statusColor.withValues(
                                                  alpha: isDark ? 0.14 : 0.1,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(
                                                      AppTokens.radiusControl,
                                                    ),
                                                border: Border.all(
                                                  color: statusColor.withValues(
                                                    alpha: 0.3,
                                                  ),
                                                ),
                                              ),
                                              child: Text(
                                                status.toUpperCase(),
                                                style: AppFonts.body(
                                                  color: statusColor,
                                                  weight: FontWeight.w800,
                                                  size: 10,
                                                  letterSpacing: 0.5,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Text(
                                              'Steps taken: ${task['steps_taken'] ?? 0}',
                                              style: AppFonts.body(
                                                weight: FontWeight.w600,
                                                size: 13,
                                                color: scheme.onSurface,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 20),
                                        Text(
                                          'Execution Trace:',
                                          style: AppFonts.body(
                                            weight: FontWeight.w700,
                                            size: 13,
                                            color: scheme.onSurface,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        ...((task['trace'] as List<dynamic>?) ??
                                                [])
                                            .map(
                                              (t) => Container(
                                                margin: const EdgeInsets.only(
                                                  bottom: 6,
                                                ),
                                                padding: const EdgeInsets.all(
                                                  10,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: scheme
                                                      .surfaceContainerHighest,
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        AppTokens.radiusControl,
                                                      ),
                                                ),
                                                child: Text(
                                                  '• $t',
                                                  style: AppFonts.body(
                                                    size: 12,
                                                    color:
                                                        scheme.onSurfaceVariant,
                                                  ),
                                                ),
                                              ),
                                            ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.history_rounded,
              size: 36,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No task history found.',
            style: AppFonts.body(
              size: AppTokens.bodySize,
              weight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Run your first AI task and it will show up here.',
            style: AppFonts.body(
              size: AppTokens.captionSize,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
