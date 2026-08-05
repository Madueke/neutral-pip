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
          .where((t) => (t['status'] as String? ?? 'Unknown') == _statusFilter)
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
        content: const Text('Are you sure you want to delete all task history?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear', style: TextStyle(color: AppColors.bear)),
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
    final filtered = _filteredHistory;

    return Scaffold(
      appBar: AppBar(
        title: Text('Task History (${_history.length})'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
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
                                label: Text(f),
                                selected: _statusFilter == f,
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
                                style: TextStyle(color: scheme.onSurfaceVariant),
                              ),
                            )
                          : ListView.builder(
                              itemCount: filtered.length,
                              padding: const EdgeInsets.all(16),
                              itemBuilder: (context, index) {
                                final task = filtered[index];
                                final date =
                                    DateTime.tryParse(task['timestamp'] ?? '');
                                final dateStr = date != null
                                    ? DateFormat('MMM d, y h:mm a').format(date)
                                    : 'Unknown Date';
                                final status =
                                    task['status'] as String? ?? 'Unknown';

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 16),
                                  child: ExpansionTile(
                                    leading: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color:
                                            _getStatusColor(status).withOpacity(0.12),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        _getStatusIcon(status),
                                        color: _getStatusColor(status),
                                        size: 24,
                                      ),
                                    ),
                                    title: Text(
                                      task['goal'] ?? 'Unknown Goal',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold),
                                    ),
                                    subtitle: Padding(
                                      padding:
                                          const EdgeInsets.only(top: 8.0),
                                      child: Row(
                                        children: [
                                          Text(dateStr,
                                              style: const TextStyle(
                                                  fontSize: 12)),
                                          const Spacer(),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: scheme
                                                  .surfaceContainerHighest,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              '${task['total_tokens'] ?? 0} tokens',
                                              style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.all(16.0),
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
                                                          vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: _getStatusColor(
                                                            status)
                                                        .withOpacity(0.12),
                                                    borderRadius:
                                                        BorderRadius.circular(8),
                                                    border: Border.all(
                                                        color: _getStatusColor(
                                                                status)
                                                            .withOpacity(0.3)),
                                                  ),
                                                  child: Text(
                                                    status.toUpperCase(),
                                                    style: TextStyle(
                                                      color: _getStatusColor(
                                                          status),
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      fontSize: 10,
                                                      letterSpacing: 0.5,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Text(
                                                  'Steps taken: ${task['steps_taken'] ?? 0}',
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize: 13),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 20),
                                            const Text(
                                              'Execution Trace:',
                                              style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13),
                                            ),
                                            const SizedBox(height: 8),
                                            ...((task['trace']
                                                        as List<dynamic>?) ??
                                                    [])
                                                .map((t) => Container(
                                                      margin: const EdgeInsets
                                                          .only(bottom: 6),
                                                      padding:
                                                          const EdgeInsets.all(
                                                              10),
                                                      decoration:
                                                          BoxDecoration(
                                                        color: scheme
                                                            .surfaceContainerHighest,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(8),
                                                      ),
                                                      child: Text(
                                                        '• $t',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: scheme
                                                              .onSurfaceVariant,
                                                        ),
                                                      ),
                                                    )),
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
          Icon(Icons.history_rounded,
              size: 42, color: scheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            'No task history found.',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
