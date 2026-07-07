import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/pricing_group.dart';
import '../../../services/database_service.dart';
import '../../../state/app_state.dart';
import 'usage_list.dart';
import 'usage_stats.dart';

/// Desktop/wide layout for the token-usage tab: a range sidebar plus large
/// summary stats, per-group cost cards and a paged list.
class UsageViewDesktop extends StatefulWidget {
  const UsageViewDesktop({super.key});

  @override
  State<UsageViewDesktop> createState() => _UsageViewDesktopState();
}

class _UsageViewDesktopState extends State<UsageViewDesktop> {
  final DatabaseService _db = DatabaseService();
  final List<Map<String, dynamic>> _pagedUsageData = [];
  UsageStats _stats = UsageStats.empty();
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentPage = 0;
  static const int _pageSize = 100;

  String _activePreset = 'week';
  DateTimeRange _dateRange = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 7)),
    end: DateTime.now(),
  );

  @override
  void initState() {
    super.initState();
    _loadData(reset: true);
  }

  Future<void> _loadData({bool reset = false}) async {
    if (!mounted) return;

    if (reset) {
      setState(() {
        _isLoading = true;
        _currentPage = 0;
        _pagedUsageData.clear();
        _hasMore = true;
      });
    } else {
      setState(() => _isLoadingMore = true);
    }

    try {
      final appState = Provider.of<AppState>(context, listen: false);

      if (reset) {
        final allInRange = await _db.getTokenUsage(
          start: _dateRange.start,
          end: _dateRange.end,
        );
        if (mounted) {
          _stats = calculateStats(allInRange, appState.allModels);

          if (allInRange.length > 500) {
            _maybeCreateCheckpoint(_stats);
          }
        }
      }

      final pagedData = await _db.getTokenUsage(
        start: _dateRange.start,
        end: _dateRange.end,
        limit: _pageSize,
        offset: _currentPage * _pageSize,
      );

      if (mounted) {
        setState(() {
          _pagedUsageData.addAll(pagedData);
          _hasMore = pagedData.length == _pageSize;
          _currentPage++;
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  Future<void> _maybeCreateCheckpoint(UsageStats currentStats) async {
    final last = await _db.getLatestUsageCheckpoint();
    if (last == null ||
        DateTime.now().difference(DateTime.parse(last['timestamp'])).inDays >=
            1) {
      await _db.saveUsageCheckpoint({
        'timestamp': DateTime.now().toIso8601String(),
        'total_input_tokens': currentStats.totalInput,
        'total_output_tokens': currentStats.totalOutput,
        'total_request_count': currentStats.totalRequestCount,
        'total_cost': currentStats.totalCost,
        'metadata': jsonEncode(currentStats.groupCosts),
      });
    }
  }

  void _updateRange(String preset) {
    final now = DateTime.now();
    DateTime start;
    switch (preset) {
      case 'today':
        start = DateTime(now.year, now.month, now.day);
        break;
      case 'week':
        start = now.subtract(const Duration(days: 7));
        break;
      case 'month':
        start = DateTime(now.year, now.month - 1, now.day);
        break;
      case 'year':
        start = DateTime(now.year - 1, now.month, now.day);
        break;
      default:
        start = now.subtract(const Duration(days: 7));
    }
    setState(() {
      _dateRange = DateTimeRange(start: start, end: now);
      _activePreset = preset;
    });
    _loadData(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final appState = Provider.of<AppState>(context);

    return Row(
      children: [
        // Sidebar. Material (not a colored Container): ListTile paints its
        // selected/ink effects on the nearest Material ancestor, and a plain
        // ColoredBox on top of it hides them (debug-mode assertion).
        SizedBox(
          width: 250,
          child: Material(
            color: colorScheme.surfaceContainerLow,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Text(
                    l10n.rangeLabel,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                _buildPresetTile('today', l10n.today, Icons.today_outlined),
                _buildPresetTile(
                  'week',
                  l10n.lastWeek,
                  Icons.date_range_outlined,
                ),
                _buildPresetTile(
                  'month',
                  l10n.lastMonth,
                  Icons.calendar_month_outlined,
                ),
                _buildPresetTile(
                  'year',
                  l10n.thisYear,
                  Icons.calendar_today_outlined,
                ),
                const Spacer(),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _isLoading
                            ? null
                            : () => _loadData(reset: true),
                        icon: const Icon(Icons.refresh, size: 18),
                        label: Text(l10n.refresh),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _confirmClearAll,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colorScheme.errorContainer,
                          foregroundColor: colorScheme.error,
                        ),
                        icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                        label: Text(l10n.clearAll),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        // Content
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1000),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Large Summary
                          Row(
                            children: [
                              _buildBigStat(
                                l10n.inputTokens,
                                _stats.totalInput.toString(),
                                Colors.blue,
                              ),
                              const SizedBox(width: 24),
                              _buildBigStat(
                                l10n.outputTokens,
                                _stats.totalOutput.toString(),
                                Colors.green,
                              ),
                              const SizedBox(width: 24),
                              _buildBigStat(
                                l10n.estimatedCost,
                                '\$${_stats.totalCost.toStringAsFixed(4)}',
                                Colors.orange,
                                isBold: true,
                              ),
                            ],
                          ),
                          const SizedBox(height: 32),

                          if (_stats.groupCosts.isNotEmpty) ...[
                            Text(
                              l10n.usageByGroup,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: _stats.groupCosts.entries.map((e) {
                                final group = appState.allPricingGroups
                                    .cast<PricingGroup?>()
                                    .firstWhere(
                                      (g) => g?.id == e.key,
                                      orElse: () => null,
                                    );
                                if (group == null) {
                                  return const SizedBox.shrink();
                                }
                                return _buildGroupCard(
                                  group.name,
                                  e.value,
                                  colorScheme,
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 32),
                          ],

                          const Divider(),
                          const SizedBox(height: 16),
                          UsageList(
                            usageData: _pagedUsageData,
                            shrinkWrap: true,
                            onRefresh: () => _loadData(reset: true),
                            hasMore: _hasMore,
                            isLoadingMore: _isLoadingMore,
                            onLoadMore: () => _loadData(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildPresetTile(String id, String label, IconData icon) {
    final isSelected = _activePreset == id;
    return ListTile(
      selected: isSelected,
      leading: Icon(icon, size: 20),
      title: Text(label, style: const TextStyle(fontSize: 14)),
      onTap: () => _updateRange(id),
    );
  }

  Widget _buildBigStat(
    String label,
    String value,
    Color color, {
    bool isBold = false,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: color.withAlpha(15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withAlpha(40)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: color.withAlpha(200),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 28,
                fontWeight: isBold ? FontWeight.bold : FontWeight.w300,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupCard(String name, double cost, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withAlpha(100),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(width: 12),
          Text(
            '\$${cost.toStringAsFixed(4)}',
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }

  void _confirmClearAll() {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.clearAllUsage),
        content: Text(l10n.clearUsageWarning),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await _db.clearTokenUsage();
              if (context.mounted) {
                Navigator.pop(context);
                _loadData(reset: true);
              }
            },
            child: Text(l10n.clearAll),
          ),
        ],
      ),
    );
  }
}
