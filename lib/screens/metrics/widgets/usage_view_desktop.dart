import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/pricing_group.dart';
import '../../../services/database_service.dart';
import '../../../state/app_state.dart';
import '../../../widgets/panel_resizer.dart';
import 'usage_list.dart';
import 'usage_stats.dart';
import 'usage_summary.dart';

/// Desktop/wide layout for the token-usage view, following the inset-panel
/// design: a row of compact summary stat cards sits on the canvas above the
/// main card, which hosts the range filters in its header and the per-group
/// costs plus the paged record list in its body.
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
        'total_cache_tokens': currentStats.totalCache,
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

    return Column(
      children: [
        // Summary cards on the canvas, above the main card.
        UsageSummary(stats: _stats),
        const SizedBox(height: 8),
        // Main card: header with range filters + actions, body with per-group
        // costs and the paged usage record list.
        Expanded(
          child: PanelCard(
            child: Column(
              children: [
                _buildHeader(l10n, colorScheme),
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _buildBody(l10n, colorScheme),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Header row inside the top of the main card: everything here acts on the
  /// records below it — the range the filters resolved to, the presets
  /// themselves, and the refresh/clear actions. The view tabs live outside the
  /// card, on the canvas.
  Widget _buildHeader(AppLocalizations l10n, ColorScheme colorScheme) {
    final fmt = DateFormat('yyyy-MM-dd');

    return Container(
      height: kPanelHeaderHeight,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withAlpha(90))),
      ),
      child: Row(
        children: [
          const Spacer(),
          // Reads as the caption of the presets beside it rather than as a
          // subtitle of the screen — it is what the active preset resolved to.
          Flexible(
            child: Text(
              '${fmt.format(_dateRange.start)} – ${fmt.format(_dateRange.end)}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurfaceVariant,
                fontFamily: 'monospace',
              ),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
            ),
          ),
          const SizedBox(width: 12),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'today', label: Text(l10n.today)),
              ButtonSegment(value: 'week', label: Text(l10n.lastWeek)),
              ButtonSegment(value: 'month', label: Text(l10n.lastMonth)),
              ButtonSegment(value: 'year', label: Text(l10n.thisYear)),
            ],
            selected: {_activePreset},
            onSelectionChanged: _isLoading
                ? null
                : (selection) => _updateRange(selection.first),
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _isLoading ? null : () => _loadData(reset: true),
            tooltip: l10n.refresh,
          ),
          IconButton(
            icon: Icon(Icons.delete_sweep_outlined, size: 20, color: colorScheme.error),
            onPressed: _confirmClearAll,
            tooltip: l10n.clearAll,
          ),
        ],
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n, ColorScheme colorScheme) {
    final appState = Provider.of<AppState>(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_stats.groupCosts.isNotEmpty) ...[
                Text(
                  l10n.usageByGroup,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 12),
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
                    return _buildGroupCard(group.name, e.value, colorScheme);
                  }).toList(),
                ),
                const SizedBox(height: 24),
                Divider(height: 1, color: colorScheme.outlineVariant.withAlpha(90)),
                const SizedBox(height: 16),
              ],
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
