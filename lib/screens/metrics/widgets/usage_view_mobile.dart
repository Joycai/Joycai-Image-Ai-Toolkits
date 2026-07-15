import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/database_service.dart';
import '../../../state/app_state.dart';
import 'usage_list.dart';
import 'usage_range.dart';
import 'usage_stats.dart';
import 'usage_summary.dart';

/// Mobile/narrow layout for the token-usage tab: a pinned filter bar over a
/// single scroll of summary cards and records.
class UsageViewMobile extends StatefulWidget {
  const UsageViewMobile({super.key});

  @override
  State<UsageViewMobile> createState() => _UsageViewMobileState();
}

class _UsageViewMobileState extends State<UsageViewMobile> {
  final DatabaseService _db = DatabaseService();
  final List<Map<String, dynamic>> _pagedUsageData = [];
  UsageStats _stats = UsageStats.empty();
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentPage = 0;
  static const int _pageSize = 50;

  String _activePreset = 'week';
  DateTimeRange _dateRange = usageRangeForPreset('week');

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

      // 1. Fetch full stats (using checkpoints if available - background logic)
      if (reset) {
        // For stats calculation, we still need to scan the range once.
        // The checkpoint + offset logic makes this fast.
        final allInRange = await _db.getTokenUsage(
          start: _dateRange.start,
          end: _dateRange.end,
        );
        if (mounted) {
          _stats = calculateStats(allInRange, appState.allModels);
        }
      }

      // 2. Fetch paged data for the list
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

  void _updateRange(String preset) {
    setState(() {
      _dateRange = usageRangeForPreset(preset);
      _activePreset = preset;
    });
    _loadData(reset: true);
  }

  void _confirmClearAll() {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.clearAllUsage),
        content: Text(l10n.clearUsageWarning),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        _buildFilterBar(l10n),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: UsageSummary(
                          stats: _stats,
                          rangeLabel: usagePresetLabel(l10n, _activePreset),
                          compact: true,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Records step up a tone for the same reason the compact
                      // summary cards do: this view is hosted on a card at
                      // tablet width, and surface on surface has no edge.
                      Material(
                        color: colorScheme.surfaceContainerHigh,
                        child: UsageList(
                          usageData: _pagedUsageData,
                          onRefresh: () => _loadData(reset: true),
                          hasMore: _hasMore,
                          isLoadingMore: _isLoadingMore,
                          onLoadMore: () => _loadData(),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildFilterBar(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final preset in usagePresets) ...[
                    _buildPresetChip(preset, usagePresetLabel(l10n, preset)),
                    const SizedBox(width: 4),
                  ],
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _isLoading ? null : () => _loadData(reset: true),
            tooltip: l10n.refresh,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined, size: 20, color: Colors.red),
            onPressed: _confirmClearAll,
            tooltip: l10n.clearAll,
          ),
        ],
      ),
    );
  }

  /// Selectable, not just tappable: the chips are the only thing on this view
  /// that says which range every number below them covers.
  Widget _buildPresetChip(String preset, String label) {
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      selected: _activePreset == preset,
      onSelected: (_) => _updateRange(preset),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }
}
