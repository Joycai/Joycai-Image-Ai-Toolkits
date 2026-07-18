import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/database_service.dart';
import '../../../state/app_state.dart';
import '../../../widgets/app_icon_button.dart';
import '../../../widgets/app_segmented_control.dart';
import '../../../widgets/panel_resizer.dart';
import 'usage_group_costs.dart';
import 'usage_list.dart';
import 'usage_range.dart';
import 'usage_stats.dart';
import 'usage_summary.dart';

/// Desktop/wide layout for the token-usage view: a scrolling canvas of cards —
/// the summary hero, the range toolbar, per-group costs, and the record table.
///
/// The toolbar sits on the canvas between the hero and the groups rather than
/// in a card header, because the range it sets governs every card on the page,
/// hero included. Inside one card's header it would have looked like that
/// card's filter.
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
            await _maybeCreateCheckpoint(_stats);
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
    try {
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
          // groupCosts is keyed by int group id; jsonEncode throws
          // JsonUnsupportedObjectError on any non-String map key, so the keys
          // must be stringified first.
          'metadata': jsonEncode(currentStats.groupCosts
              .map((k, v) => MapEntry(k.toString(), v))),
        });
      }
    } catch (_) {
      // Checkpoint persistence is best-effort; it must never break the view.
    }
  }

  void _updateRange(String preset) {
    setState(() {
      _dateRange = usageRangeForPreset(preset);
      _activePreset = preset;
    });
    _loadData(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final appState = Provider.of<AppState>(context);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          UsageSummary(
            stats: _stats,
            rangeLabel: usagePresetLabel(l10n, _activePreset),
          ),
          const SizedBox(height: 16),
          _buildToolbar(l10n, colorScheme),
          const SizedBox(height: 16),
          if (_isLoading)
            const PanelCard(
              child: Padding(
                padding: EdgeInsets.all(64),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else ...[
            UsageGroupCosts(stats: _stats, groups: appState.allPricingGroups),
            if (_stats.groupCosts.isNotEmpty) const SizedBox(height: 16),
            PanelCard(
              child: Padding(
                padding: const EdgeInsets.only(top: 14),
                child: UsageList(
                  usageData: _pagedUsageData,
                  onRefresh: () => _loadData(reset: true),
                  hasMore: _hasMore,
                  isLoadingMore: _isLoadingMore,
                  onLoadMore: () => _loadData(),
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  /// Range presets and the destructive actions, on the canvas. The dates the
  /// active preset resolved to caption it from the left — the presets say
  /// "last week", only the dates say which week that was.
  Widget _buildToolbar(AppLocalizations l10n, ColorScheme colorScheme) {
    final fmt = DateFormat('yyyy-MM-dd');

    return Row(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2),
          child: Text(
            '${fmt.format(_dateRange.start)} ~ ${fmt.format(_dateRange.end)}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurfaceVariant,
              fontFamily: 'monospace',
            ),
          ),
        ),
        const Spacer(),
        AppSegmentedControl<String>(
          segments: [
            for (final preset in usagePresets)
              AppSegment(
                value: preset,
                label: usagePresetLabel(l10n, preset),
                enabled: !_isLoading,
              ),
          ],
          value: _activePreset,
          onChanged: _updateRange,
          compact: true,
        ),
        const SizedBox(width: 12),
        AppIconButton(
          icon: Icons.refresh,
          tooltip: l10n.refresh,
          onPressed: _isLoading ? null : () => _loadData(reset: true),
        ),
        const SizedBox(width: 6),
        AppIconButton(
          icon: Icons.delete_sweep_outlined,
          tooltip: l10n.clearAll,
          color: colorScheme.error,
          onPressed: _confirmClearAll,
        ),
      ],
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
