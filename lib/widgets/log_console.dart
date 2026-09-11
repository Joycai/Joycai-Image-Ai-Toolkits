import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/app_semantic_colors.dart';
import '../core/app_theme.dart';
import '../core/design_tokens.dart';
import '../l10n/app_localizations.dart';
import '../models/log_entry.dart';
import '../state/log_state.dart';
import 'app_search_field.dart';
import 'app_snackbar.dart';
import 'scroll_edge_fade.dart';

/// `HH:MM:SS` for a log line — the clock both the log panel and the run
/// console's tail line print, so the two always agree.
String logClockOf(DateTime timestamp) =>
    timestamp.toIso8601String().split('T').last.substring(0, 8);

/// The execution log panel: a toolbar (search, level filter, copy, clear)
/// over the scrolling log, on the opaque column ground.
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

    // `展开面板 = 不透明 col`: toolbar and log share the one opaque ground.
    return ColoredBox(
      color: colorScheme.surfaceContainerLow,
      child: Column(
        children: [
          if (widget.showHeader) _buildToolbar(context, logState, colorScheme),
          Expanded(
            // No rule under the toolbar: the soft edge says "continues" and
            // only appears while there is content beyond it, where a hard
            // line would slice whatever log line sat at the boundary.
            child: ScrollEdgeFade(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: AppSpace.s6),
                itemCount: filteredLogs.length,
                itemBuilder: (context, index) {
                  return _LogLine(log: filteredLogs[index]);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(BuildContext context, LogState logState, ColorScheme colorScheme) {
    final l10n = AppLocalizations.of(context)!;
    final materialL10n = MaterialLocalizations.of(context);
    final semantic = context.semantic;

    return SizedBox(
      height: AppSize.large,
      child: Padding(
        // 12 to line up with the status strip above; the controls are 28, so
        // the 40 row leaves them 6 either side.
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            // Search
            if (_isSearchExpanded)
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: AppSize.control,
                        child: AppSearchField(
                          controller: _searchController,
                          hint: l10n.logSearchHint,
                          compact: true,
                          autofocus: true,
                          onChanged: (v) => setState(() => _searchQuery = v),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpace.s6),
                    // A sibling, not the field's suffix. This ✕ closes the
                    // search rather than clearing it, and it has to stay
                    // reachable while the field is empty — which is exactly
                    // when AppSearchField hides its own clear button. Folding
                    // the two together is what made one glyph mean two things.
                    _ToolbarIconButton(
                      icon: Icons.close,
                      tooltip: materialL10n.closeButtonTooltip,
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
              )
            else
              _ToolbarIconButton(
                icon: Icons.search,
                tooltip: materialL10n.searchFieldLabel,
                onPressed: () => setState(() => _isSearchExpanded = true),
              ),

            if (!_isSearchExpanded) ...[
              const Spacer(),

              // Level filter
              _buildLevelChip(
                context,
                label: l10n.logLevelError,
                level: 'ERROR',
                mark: colorScheme.error,
                ink: colorScheme.error,
              ),
              _buildLevelChip(
                context,
                label: l10n.logLevelRunning,
                level: 'RUNNING',
                mark: semantic.info,
                ink: semantic.onInfoContainer,
              ),
              _buildLevelChip(
                context,
                label: l10n.logLevelSuccess,
                level: 'SUCCESS',
                mark: semantic.success,
                ink: semantic.onSuccessContainer,
              ),

              const SizedBox(width: AppSpace.s10),
              SizedBox(
                height: AppSpace.s16,
                child: VerticalDivider(width: 1, color: colorScheme.outlineVariant),
              ),
              const SizedBox(width: AppSpace.s6),

              _ToolbarIconButton(
                icon: Icons.copy_all,
                tooltip: l10n.copyLogs,
                onPressed: () {
                  final text = logState.logs.map((l) => '[${l.level}] ${l.message}').join('\n');
                  Clipboard.setData(ClipboardData(text: text));
                  AppSnackBar.info(context, l10n.taskLogCopied);
                },
              ),
              const SizedBox(width: 2),
              _ToolbarIconButton(
                icon: Icons.delete_sweep_outlined,
                tooltip: l10n.clear,
                onPressed: () => logState.clear(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// A level filter toggle: a hairline box with the level's dot at rest, the
  /// level's own 12% wash and ring when chosen. The level's colour, not the
  /// accent — a status means the same thing whichever theme is picked.
  Widget _buildLevelChip(
    BuildContext context, {
    required String label,
    required String level,
    required Color mark,
    required Color ink,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSelected = _filterLevel == level;

    return Padding(
      padding: const EdgeInsets.only(left: AppSpace.s4),
      child: TextButton(
        onPressed: () {
          setState(() {
            _filterLevel = isSelected ? null : level;
          });
        },
        style: TextButton.styleFrom(
          foregroundColor: isSelected ? ink : colorScheme.onSurfaceVariant,
          backgroundColor: isSelected ? mark.withValues(alpha: AppAlpha.tint) : Colors.transparent,
          overlayColor: colorScheme.onSurface,
          side: BorderSide(
            color: isSelected ? mark.withValues(alpha: AppAlpha.ring) : colorScheme.outlineVariant,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
          minimumSize: const Size(0, AppSize.compact),
          maximumSize: const Size(double.infinity, AppSize.compact),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.standard,
          // `inherit: false`, as the theme's own button label is: a button
          // lerps between label styles and TextStyle.lerp asserts across a
          // change of `inherit`.
          textStyle: Theme.of(context).textTheme.labelSmall?.copyWith(inherit: false),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(color: mark, shape: BoxShape.circle),
              child: const SizedBox.square(dimension: 6),
            ),
            const SizedBox(width: AppSpace.s6),
            Text(label),
          ],
        ),
      ),
    );
  }
}

/// A bare 28px glyph action for the log toolbar: no box at rest, r10 ink.
class _ToolbarIconButton extends StatelessWidget {
  const _ToolbarIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return IconButton(
      icon: Icon(icon),
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        foregroundColor: colorScheme.onSurfaceVariant,
        iconSize: AppSize.iconMd,
        minimumSize: const Size.square(AppSize.compact),
        fixedSize: const Size.square(AppSize.compact),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
        visualDensity: VisualDensity.standard,
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
          // Mono 12/400 — `bodySmall`, not a label slot: a log line is read,
          // and the 500 weight of the label slots thickens a wall of it.
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.mono
              .copyWith(height: AppType.proseHeight),
          children: [
            TextSpan(
              text: '[${logClockOf(log.timestamp)}] ',
              style: TextStyle(color: colorScheme.outline),
            ),
            if (log.taskId != null)
              TextSpan(
                text: '[${log.taskId!.length > 8 ? log.taskId!.substring(0, 8) : log.taskId}] ',
                style: TextStyle(color: colorScheme.accentText),
              ),
            TextSpan(
              text: '[${log.level}] ',
              style: TextStyle(
                color: _getLevelColor(log.level, colorScheme, semantic),
                fontWeight: FontWeight.w600,
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
  /// Error is the scheme's red; the rest come from [AppSemanticColors] so no
  /// level follows the theme colour. These are the `onXContainer` tones rather
  /// than the base ones because a log line is *text*: the base hues are tuned
  /// to be seen as a fill, and at 12px on the column ground they read thin.
  /// `DEBUG` — the chattiest level by far — takes the muted ink, so the
  /// levels that mean something are the ones that stand out.
  Color _getLevelColor(String level, ColorScheme colorScheme, AppSemanticColors semantic) {
    switch (level) {
      case 'ERROR':
        return colorScheme.error;
      case 'WARN':
      case 'WARNING':
        return semantic.onWarningContainer;
      case 'SUCCESS':
        return semantic.onSuccessContainer;
      case 'RUNNING':
      case 'INFO':
        return semantic.onInfoContainer;
      default:
        return colorScheme.outline;
    }
  }
}
