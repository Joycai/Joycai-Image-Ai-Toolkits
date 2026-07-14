import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/database_service.dart';
import '../../../state/app_state.dart';
import 'usage_list.dart';
import 'usage_stats.dart';
import 'usage_summary.dart';

/// Mobile/narrow layout for the token-usage tab: preset chips, compact summary
/// cards and a paged list.
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

    return Column(
      children: [
        // Filter Bar
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildPresetChip('today', l10n.today),
                      const SizedBox(width: 4),
                      _buildPresetChip('week', l10n.lastWeek),
                      const SizedBox(width: 4),
                      _buildPresetChip('month', l10n.lastMonth),
                      const SizedBox(width: 4),
                      _buildPresetChip('year', l10n.thisYear),
                    ],
                  ),
                ),
              ),
              IconButton(icon: const Icon(Icons.refresh, size: 20), onPressed: () => _loadData(reset: true)),
              IconButton(
                icon: const Icon(Icons.delete_sweep_outlined, size: 20, color: Colors.red),
                onPressed: _confirmClearAll,
                tooltip: l10n.clearAll,
              ),
            ],
          ),
        ),

        // Summary cards — the same component the desktop view uses, stacked.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: UsageSummary(stats: _stats, compact: true),
        ),

        const SizedBox(height: 16),

        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : UsageList(
                  usageData: _pagedUsageData,
                  onRefresh: () => _loadData(reset: true),
                  hasMore: _hasMore,
                  isLoadingMore: _isLoadingMore,
                  onLoadMore: () => _loadData(),
                ),
        ),
      ],
    );
  }

  Widget _buildPresetChip(String id, String label) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      onPressed: () => _updateRange(id),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }

}
