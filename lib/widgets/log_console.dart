import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/app_semantic_colors.dart';
import '../models/log_entry.dart';
import '../state/log_state.dart';
import 'app_search_field.dart';
import 'app_snackbar.dart';

class LogConsoleWidget extends StatefulWidget {
  final bool showHeader;
  const LogConsoleWidget({super.key, this.showHeader = true});

  @override
  State<LogConsoleWidget> createState() => _LogConsoleWidgetState();
}

class _LogConsoleWidgetState extends State<LogConsoleWidget> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  bool _autoScroll = true;
  String? _filterLevel;
  String _searchQuery = "";
  bool _isSearchExpanded = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final isAtBottom = _scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 10;
    if (_autoScroll != isAtBottom) {
      setState(() => _autoScroll = isAtBottom);
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients && _autoScroll) {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    }
  }

  @override
  Widget build(BuildContext context) {
    final logState = Provider.of<LogState>(context);
    final colorScheme = Theme.of(context).colorScheme;

    // Apply filters. The unfiltered case — which is how the console spends
    // nearly all of its time — reads the list straight through rather than
    // copying a thousand entries on every rebuild.
    final List<LogEntry> filteredLogs;
    if (_filterLevel == null && _searchQuery.isEmpty) {
      filteredLogs = logState.logs;
    } else {
      final query = _searchQuery.toLowerCase();
      filteredLogs = logState.logs.where((log) {
        final matchesLevel = _filterLevel == null || log.level == _filterLevel;
        final matchesSearch = query.isEmpty ||
            log.message.toLowerCase().contains(query) ||
            (log.taskId?.toLowerCase().contains(query) ?? false);
        return matchesLevel && matchesSearch;
      }).toList();
    }

    // Trigger scroll after build if auto-scroll is enabled
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    return Column(
      children: [
        if (widget.showHeader) _buildToolbar(context, logState, colorScheme),
        Expanded(
          child: Container(
            color: colorScheme.surfaceContainerLowest,
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: filteredLogs.length,
              itemBuilder: (context, index) {
                return _LogLine(log: filteredLogs[index]);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildToolbar(BuildContext context, LogState logState, ColorScheme colorScheme) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withAlpha(90))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // Search
          if (_isSearchExpanded)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: AppSearchField(
                        controller: _searchController,
                        hint: 'Filter logs...',
                        compact: true,
                        autofocus: true,
                        onChanged: (v) => setState(() => _searchQuery = v),
                      ),
                    ),
                    // A sibling, not the field's suffix. This ✕ closes the
                    // search rather than clearing it, and it has to stay
                    // reachable while the field is empty — which is exactly
                    // when AppSearchField hides its own clear button. Folding
                    // the two together is what made one glyph mean two things.
                    IconButton(
                      icon: Icon(Icons.close, size: 14, color: colorScheme.onSurfaceVariant),
                      visualDensity: VisualDensity.compact,
                      tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                      onPressed: () {
                        setState(() {
                          _searchQuery = "";
                          _searchController.clear();
                          _isSearchExpanded = false;
                        });
                      },
                    ),
                  ],
                ),
              ),
            )
          else
            IconButton(
              icon: Icon(Icons.search, size: 18, color: colorScheme.onSurfaceVariant),
              onPressed: () => setState(() => _isSearchExpanded = true),
              tooltip: 'Search logs',
            ),

          if (!_isSearchExpanded) ...[
            const Spacer(),

            // Level Filter
            _buildLevelChip('ERR', 'ERROR', colorScheme.error),
            _buildLevelChip('RUN', 'RUNNING', colorScheme.primary),
            _buildLevelChip('SUC', 'SUCCESS', context.semantic.success),

            VerticalDivider(width: 16, indent: 8, endIndent: 8, color: colorScheme.outlineVariant),

            IconButton(
              icon: Icon(Icons.copy_all, size: 18, color: colorScheme.onSurfaceVariant),
              onPressed: () {
                final text = logState.logs.map((l) => '[${l.level}] ${l.message}').join('\n');
                Clipboard.setData(ClipboardData(text: text));
                AppSnackBar.info(context, 'Logs copied to clipboard');
              },
              tooltip: 'Copy all',
            ),
            IconButton(
              icon: Icon(Icons.delete_sweep_outlined, size: 18, color: colorScheme.onSurfaceVariant),
              onPressed: () => logState.clear(),
              tooltip: 'Clear',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLevelChip(String label, String level, Color color) {
    final isSelected = _filterLevel == level;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: ActionChip(
        label: Text(label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(fontWeight: FontWeight.bold, color: color)),
        backgroundColor: isSelected ? color.withAlpha(100) : Colors.transparent,
        side: BorderSide(color: color.withAlpha(isSelected ? 255 : 100)),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        onPressed: () {
          setState(() {
            _filterLevel = isSelected ? null : level;
          });
        },
      ),
    );
  }
}

class _LogLine extends StatelessWidget {
  final LogEntry log;
  const _LogLine({required this.log});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final semantic = context.semantic;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: RichText(
        text: TextSpan(
          style: Theme.of(context)
              .textTheme
              .labelMedium
              ?.copyWith(fontFamily: 'monospace', height: 1.4),
          children: [
            TextSpan(
              text: '[${log.timestamp.toIso8601String().split('T').last.substring(0, 8)}] ',
              style: TextStyle(color: colorScheme.onSurfaceVariant.withAlpha(160)),
            ),
            if (log.taskId != null)
              TextSpan(
                text: '[${log.taskId!.length > 8 ? log.taskId!.substring(0, 8) : log.taskId}] ',
                style: TextStyle(color: colorScheme.primary),
              ),
            TextSpan(
              text: '[${log.level}] ',
              style: TextStyle(
                color: _getLevelColor(log.level, colorScheme, semantic),
                fontWeight: FontWeight.bold,
              ),
            ),
            TextSpan(
              text: log.message,
              style: TextStyle(color: log.level == 'ERROR' ? colorScheme.error : colorScheme.onSurface),
            ),
          ],
        ),
      ),
    );
  }

  /// The colour a level is spoken in.
  ///
  /// Was four pairs of literals behind a hand-written `isDark` branch — and
  /// the same amber pair appeared again in `task_log_dialog.dart` and a third
  /// time in `app_snackbar.dart`, at three slightly different values. These
  /// are the `onXContainer` tones rather than the base ones because a log line
  /// is *text*: the base hues are tuned to be seen as a fill, and at 11.5px on
  /// the console's surface they read thin.
  Color _getLevelColor(String level, ColorScheme colorScheme, AppSemanticColors semantic) {
    switch (level) {
      case 'ERROR':
        return colorScheme.error;
      case 'RUNNING':
        return semantic.onInfoContainer;
      case 'SUCCESS':
        return semantic.onSuccessContainer;
      default:
        return semantic.onWarningContainer;
    }
  }
}