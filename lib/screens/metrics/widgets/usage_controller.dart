import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../models/llm_model.dart';
import '../../../services/database_service.dart';
import 'usage_range.dart';
import 'usage_stats.dart';

/// Loads one usage view's range: the totals over it, and the records a page at
/// a time.
///
/// The desktop and phone views used to carry two copies of this. It is one
/// object now so the phone screen's glass header can refresh and clear the
/// same data its body shows. It is not app state: each view owns its own, and
/// switching away re-queries on return, as the views always have.
class UsageController extends ChangeNotifier {
  UsageController({
    required List<LLMModel> Function() models,
    this.pageSize = 100,
    this.createCheckpoints = false,
    DatabaseService? database,
  })  : _models = models,
        _db = database ?? DatabaseService();

  final List<LLMModel> Function() _models;
  final DatabaseService _db;

  /// Records per Load More.
  final int pageSize;

  /// Whether a large range (> 500 records) writes a daily usage checkpoint.
  final bool createCheckpoints;

  List<Map<String, dynamic>> _rows = const [];
  UsageStats _stats = UsageStats.empty();
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentPage = 0;
  int? _totalRecords;
  String _preset = 'week';
  DateTimeRange _range = usageRangeForPreset('week');

  /// Bumped by every reset, so a page that lands after the range changed is
  /// dropped instead of being appended to the new range's records.
  int _generation = 0;
  bool _disposed = false;

  List<Map<String, dynamic>> get rows => _rows;
  UsageStats get stats => _stats;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMore => _hasMore;

  /// Records in the whole range, known once a reset has counted them.
  int? get totalRecords => _totalRecords;

  String get preset => _preset;
  DateTimeRange get range => _range;

  /// Loads the next page, or with [reset] recomputes the totals and starts
  /// again from the first page.
  Future<void> load({bool reset = false}) async {
    if (_disposed) return;

    if (reset) {
      _generation++;
      _isLoading = true;
      _isLoadingMore = false;
      _currentPage = 0;
      _rows = const [];
      _hasMore = true;
    } else {
      _isLoadingMore = true;
    }
    _notify();

    final generation = _generation;
    final range = _range;
    // Read before the first await: the owner's context may be gone after it.
    final models = _models();

    try {
      if (reset) {
        final allInRange = await _db.getTokenUsage(start: range.start, end: range.end);
        if (_isStale(generation)) return;

        _stats = calculateStats(allInRange, models);
        _totalRecords = allInRange.length;

        if (createCheckpoints && allInRange.length > 500) {
          await _maybeCreateCheckpoint(_stats);
        }
      }

      final pagedData = await _db.getTokenUsage(
        start: range.start,
        end: range.end,
        limit: pageSize,
        offset: _currentPage * pageSize,
      );
      if (_isStale(generation)) return;

      _rows = [..._rows, ...pagedData];
      _hasMore = pagedData.length == pageSize;
      _currentPage++;
      _isLoading = false;
      _isLoadingMore = false;
      _notify();
    } catch (_) {
      if (_isStale(generation)) return;
      _isLoading = false;
      _isLoadingMore = false;
      _notify();
    }
  }

  /// Switches to [preset]'s range and reloads it.
  void selectPreset(String preset) {
    _range = usageRangeForPreset(preset);
    _preset = preset;
    load(reset: true);
  }

  /// Deletes every usage record. The caller reloads.
  Future<void> clearTokenUsage() => _db.clearTokenUsage();

  bool _isStale(int generation) => _disposed || generation != _generation;

  Future<void> _maybeCreateCheckpoint(UsageStats currentStats) async {
    try {
      final last = await _db.getLatestUsageCheckpoint();
      if (last == null ||
          DateTime.now().difference(DateTime.parse(last['timestamp'])).inDays >= 1) {
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
          'metadata': jsonEncode(currentStats.groupCosts.map((k, v) => MapEntry(k.toString(), v))),
        });
      }
    } catch (_) {
      // Checkpoint persistence is best-effort; it must never break the view.
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
