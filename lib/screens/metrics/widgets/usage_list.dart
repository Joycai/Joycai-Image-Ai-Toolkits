import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/database_service.dart';
import 'usage_stats.dart';
import 'usage_summary.dart';

/// Table of token-usage records, grouped by day. Meant to be hosted in a card
/// inside a scroll view — it lays every row out at once rather than scrolling
/// itself, because the page it belongs to scrolls as a whole.
///
/// A table, not a list of cards: every record holds the same four facts, and
/// four facts in fixed columns can be compared down the page. Cards made each
/// row restate its own labels and put the costs at a different x each time.
class UsageList extends StatelessWidget {
  final List<Map<String, dynamic>> usageData;
  final VoidCallback onRefresh;
  final bool hasMore;
  final bool isLoadingMore;
  final VoidCallback onLoadMore;

  const UsageList({
    super.key,
    required this.usageData,
    required this.onRefresh,
    required this.hasMore,
    required this.isLoadingMore,
    required this.onLoadMore,
  });

  /// Below this the four columns stop fitting and the row folds its detail and
  /// time under the model name.
  static const double _compactWidth = 560;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    if (usageData.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(48),
        child: Center(
          child: Text(
            l10n.noUsageInRange,
            style: TextStyle(color: colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final days = _groupByDay(usageData);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < _compactWidth;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!compact) _buildColumnHeader(l10n, colorScheme),
            for (var i = 0; i < days.length; i++) ...[
              _buildDayHeader(
                context,
                l10n,
                colorScheme,
                day: days[i].day,
                rows: days[i].rows,
                // The oldest day on screen is only as complete as the pages
                // loaded so far, so it does not get to claim a daily total —
                // that number would be wrong until the user pressed Load More,
                // and wrong quietly.
                partial: hasMore && i == days.length - 1,
              ),
              for (final row in days[i].rows)
                _UsageRow(
                  row: row,
                  compact: compact,
                  onDelete: () => _confirmDeleteModelData(context, row['model_id'] as String),
                ),
            ],
            if (hasMore) _buildLoadMore(l10n),
          ],
        );
      },
    );
  }

  // --- Header -------------------------------------------------------------

  Widget _buildColumnHeader(AppLocalizations l10n, ColorScheme colorScheme) {
    final style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: colorScheme.onSurfaceVariant,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withAlpha(90))),
      ),
      child: Row(
        children: [
          Expanded(child: Text(l10n.model, style: style)),
          SizedBox(
            width: _UsageRow.detailWidth,
            child: Text(l10n.usageColumnDetail, style: style, textAlign: TextAlign.end),
          ),
          const SizedBox(width: _UsageRow.columnGap),
          SizedBox(
            width: _UsageRow.timeWidth,
            child: Text(l10n.usageColumnTime, style: style, textAlign: TextAlign.end),
          ),
          const SizedBox(width: _UsageRow.columnGap),
          SizedBox(
            width: _UsageRow.costWidth,
            child: Text(l10n.usageColumnCost, style: style, textAlign: TextAlign.end),
          ),
          const SizedBox(width: _UsageRow.actionWidth),
        ],
      ),
    );
  }

  /// The day's name, how many records it holds, and what they cost.
  Widget _buildDayHeader(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme colorScheme, {
    required DateTime day,
    required List<Map<String, dynamic>> rows,
    required bool partial,
  }) {
    final total = rows.fold<double>(0, (sum, row) => sum + calculateRowCost(row));
    final name = _dayName(l10n, day);
    final date = DateFormat('MM-dd').format(day);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      color: colorScheme.onSurface.withAlpha(10),
      child: Row(
        children: [
          // The day and its count give way before the total does: which day it
          // is, is already half-answered by position on the page; what it cost
          // is the reason the header is here.
          Expanded(
            child: Row(
              children: [
                if (name != null) ...[
                  Flexible(
                    child: Text(
                      name,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  date,
                  style: TextStyle(
                    fontSize: name == null ? 12.5 : 11,
                    fontWeight: name == null ? FontWeight.w700 : FontWeight.w400,
                    fontFamily: 'monospace',
                    color: name == null ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
                  ),
                ),
                if (!partial) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '· ${l10n.usageRecordCount(rows.length)}',
                      style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (!partial)
            Text(
              '\$${total.toStringAsFixed(4)}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
                color: usageCostAccent,
              ),
            ),
          const SizedBox(width: _UsageRow.actionWidth),
        ],
      ),
    );
  }

  Widget _buildLoadMore(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: isLoadingMore
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
            : OutlinedButton(onPressed: onLoadMore, child: Text(l10n.loadMore)),
      ),
    );
  }

  // --- Grouping -----------------------------------------------------------

  /// Records bucketed by calendar day, newest first — the order the query
  /// already returns them in, so a day never appears twice.
  List<({DateTime day, List<Map<String, dynamic>> rows})> _groupByDay(
    List<Map<String, dynamic>> rows,
  ) {
    final days = <({DateTime day, List<Map<String, dynamic>> rows})>[];

    for (final row in rows) {
      final time = DateTime.parse(row['timestamp'] as String);
      final day = DateTime(time.year, time.month, time.day);

      if (days.isEmpty || days.last.day != day) {
        days.add((day: day, rows: [row]));
      } else {
        days.last.rows.add(row);
      }
    }
    return days;
  }

  /// "Today" / "Yesterday", or null for any day far enough back that its date
  /// is the only name it has.
  String? _dayName(AppLocalizations l10n, DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;

    if (diff == 0) return l10n.today;
    if (diff == 1) return l10n.yesterday;
    return null;
  }

  void _confirmDeleteModelData(BuildContext context, String modelId) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.clearDataForModel(modelId)),
        content: Text(l10n.clearModelDataWarning(modelId)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await DatabaseService().clearTokenUsage(modelId: modelId);
              if (context.mounted) {
                Navigator.pop(context);
                onRefresh();
              }
            },
            child: Text(l10n.clearModelData),
          ),
        ],
      ),
    );
  }
}

/// One record. Stateful only to hold hover: the delete action stays out of the
/// way until the pointer is on the row it would act on.
class _UsageRow extends StatefulWidget {
  final Map<String, dynamic> row;
  final bool compact;
  final VoidCallback onDelete;

  const _UsageRow({required this.row, required this.compact, required this.onDelete});

  static const double detailWidth = 170;
  static const double timeWidth = 64;
  static const double costWidth = 104;
  static const double columnGap = 16;

  /// Reserved on every row, empty until hover. The button cannot appear from
  /// nowhere and push the costs sideways as the pointer moves down the table.
  static const double actionWidth = 32;

  @override
  State<_UsageRow> createState() => _UsageRowState();
}

class _UsageRowState extends State<_UsageRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final row = widget.row;
    final time = DateTime.parse(row['timestamp'] as String);
    final cost = calculateRowCost(row);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Container(
        decoration: BoxDecoration(
          color: _hovering ? colorScheme.onSurface.withAlpha(8) : null,
          border: Border(top: BorderSide(color: colorScheme.outlineVariant.withAlpha(50))),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: widget.compact
            ? _buildCompact(colorScheme, time, cost)
            : _buildWide(colorScheme, time, cost),
      ),
    );
  }

  Widget _buildWide(ColorScheme colorScheme, DateTime time, double cost) {
    return Row(
      children: [
        Expanded(child: _buildModel(colorScheme)),
        SizedBox(
          width: _UsageRow.detailWidth,
          child: Align(alignment: Alignment.centerRight, child: _buildDetail(colorScheme)),
        ),
        const SizedBox(width: _UsageRow.columnGap),
        SizedBox(
          width: _UsageRow.timeWidth,
          child: Text(
            DateFormat('HH:mm').format(time),
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 11.5,
              fontFamily: 'monospace',
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: _UsageRow.columnGap),
        SizedBox(width: _UsageRow.costWidth, child: _buildCost(colorScheme, cost)),
        _buildDeleteAction(),
      ],
    );
  }

  Widget _buildCompact(ColorScheme colorScheme, DateTime time, double cost) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildModel(colorScheme),
              const SizedBox(height: 5),
              Row(
                children: [
                  Text(
                    DateFormat('HH:mm').format(time),
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(child: _buildDetail(colorScheme)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        _buildCost(colorScheme, cost),
        _buildDeleteAction(),
      ],
    );
  }

  /// The model, with any `[channel]` prefix lifted out of the id into a badge.
  ///
  /// The prefix is how the user tags which channel a model came through, so it
  /// is the same handful of strings over and over down the column. Left inline
  /// it pushed every real model name to a different x and made the column
  /// unscannable; as a badge it stays readable and the names line up.
  Widget _buildModel(ColorScheme colorScheme) {
    final modelId = widget.row['model_id'] as String;
    final match = RegExp(r'^\[([^\]]+)\]\s*').firstMatch(modelId);
    final name = match == null ? modelId : modelId.substring(match.end);

    return Tooltip(
      message: modelId,
      waitDuration: const Duration(milliseconds: 600),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (match != null) ...[
            Container(
              constraints: const BoxConstraints(maxWidth: 88),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: colorScheme.primary.withAlpha(28),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                match.group(1)!,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.primary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              name,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                fontFamily: 'monospace',
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// What was billed: token counts, or a count of requests.
  Widget _buildDetail(ColorScheme colorScheme) {
    final row = widget.row;
    final billingMode = row['billing_mode'] as String? ?? 'token';
    final l10n = AppLocalizations.of(context)!;

    if (billingMode != 'token') {
      return Text(
        l10n.usageItemCount(row['request_count'] as int? ?? 1),
        style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    final cacheTokens = row['cache_tokens'] as int? ?? 0;

    return Tooltip(
      message: [
        '${l10n.inputTokens}: ${_exact(row['input_tokens'])}',
        if (cacheTokens > 0) '${l10n.cachedInputTokens}: ${_exact(cacheTokens)}',
        '${l10n.outputTokens}: ${_exact(row['output_tokens'])}',
      ].join('\n'),
      // The column is a fixed width so the counts line up down the page; three
      // chips in a user-chosen font are not. Scaling down beats both letting
      // them overflow and widening the column for the worst case.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _tokenChip(Icons.input, usageInputAccent, row['input_tokens']),
            // Only rows that actually hit the cache carry the extra chip,
            // keeping the common no-cache row as compact as before.
            if (cacheTokens > 0) ...[
              const SizedBox(width: 8),
              _tokenChip(Icons.bolt, usageCacheAccent, cacheTokens),
            ],
            const SizedBox(width: 8),
            _tokenChip(Icons.output, usageOutputAccent, row['output_tokens']),
          ],
        ),
      ),
    );
  }

  Widget _tokenChip(IconData icon, Color color, Object? tokens) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 3),
        Text(
          _abbreviate((tokens as int?) ?? 0),
          style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
        ),
      ],
    );
  }

  /// Zero costs are stated but not shouted: a free row is still a row, and at
  /// full contrast a column of `$0.0000` drowns out the ones that cost money.
  Widget _buildCost(ColorScheme colorScheme, double cost) {
    return Text(
      '\$${cost.toStringAsFixed(4)}',
      textAlign: TextAlign.end,
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        fontFamily: 'monospace',
        color: cost > 0 ? colorScheme.onSurface : colorScheme.outline,
      ),
    );
  }

  /// Hidden until the pointer is on the row it would act on — except where
  /// there is no pointer to hover with, and a control that only appears on
  /// hover is a control that does not exist.
  Widget _buildDeleteAction() {
    final l10n = AppLocalizations.of(context)!;

    return SizedBox(
      width: _UsageRow.actionWidth,
      child: _hovering || widget.compact
          ? IconButton(
              icon: const Icon(Icons.delete_outline, size: 16),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              visualDensity: VisualDensity.compact,
              tooltip: l10n.clearModelData,
              onPressed: widget.onDelete,
            )
          : null,
    );
  }

  /// `1.2K` where the exact figure is a tooltip away: the column is here to be
  /// compared down the page, and six digits per row defeats that.
  String _abbreviate(int value) {
    if (value < 1000) return '$value';
    if (value < 1000000) return '${(value / 1000).toStringAsFixed(1)}K';
    return '${(value / 1000000).toStringAsFixed(2)}M';
  }

  String _exact(Object? value) =>
      NumberFormat.decimalPattern().format((value as int?) ?? 0);
}
