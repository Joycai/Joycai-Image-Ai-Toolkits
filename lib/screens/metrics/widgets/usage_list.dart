import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../core/responsive.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/spec_rate.dart';
import '../../../models/token_usage.dart';
import '../../../widgets/ui/app_button.dart';
import '../../../widgets/ui/app_dialog.dart';
import 'usage_chrome.dart';
import 'usage_palette.dart';

/// Which of the three row shapes the table draws (`D2` 1a / 1b / 1c).
enum _TableForm { phone, tablet, desktop }

/// Table of token-usage records, grouped by day (`D2` ④). Meant to be hosted
/// in a card inside a scroll view — it lays every row out at once rather than
/// scrolling itself, because the page it belongs to scrolls as a whole, and
/// Load More is always the table's last row.
///
/// A table, not a list of cards: every record holds the same four facts, and
/// four facts in fixed columns can be compared down the page. A row expands in
/// place to its exact counts and the action that clears its model's data.
class UsageList extends StatelessWidget {
  final List<TokenUsage> usageData;

  /// Clears one model's records and reloads: the controller's, so the delete
  /// and the reload land on the same database.
  final Future<void> Function(String modelId) onClearModelUsage;
  final bool hasMore;
  final bool isLoadingMore;
  final VoidCallback onLoadMore;

  /// Model kind (`LLMModel.tag`) by model primary key, for each row's kind
  /// plate. A row whose model is missing here draws a neutral plate.
  final Map<int, String> modelTags;

  /// Records in the whole range, for the status line beside Load More.
  final int? totalCount;

  /// Records per Load More, for the same line. The line shows only when both
  /// this and [totalCount] are known.
  final int? pageSize;

  const UsageList({
    super.key,
    required this.usageData,
    required this.onClearModelUsage,
    required this.hasMore,
    required this.isLoadingMore,
    required this.onLoadMore,
    this.modelTags = const {},
    this.totalCount,
    this.pageSize,
  });

  /// Desktop column widths, as drawn.
  static const double modelWidth = 230;
  static const double specWidth = 170;
  static const double timeWidth = 120;
  static const double costWidth = 90;
  static const double chevronWidth = 28;
  static const double columnGap = 12;
  static const double inset = AppSpace.s16;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (usageData.isEmpty) return _buildEmpty(context, l10n);

    final form = Responsive.isMobile(context)
        ? _TableForm.phone
        : Responsive.isDesktop(context)
        ? _TableForm.desktop
        : _TableForm.tablet;
    final days = _groupByDay(usageData);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (form == _TableForm.desktop) _buildColumnHeader(context, l10n),
        for (var i = 0; i < days.length; i++) ...[
          _buildDayRow(
            context,
            l10n,
            form,
            day: days[i].day,
            rows: days[i].rows,
            // The oldest day on screen is only as complete as the pages
            // loaded so far, so it does not get to claim a daily total —
            // that number would be wrong until the user pressed Load More,
            // and wrong quietly.
            partial: hasMore && i == days.length - 1,
            first: i == 0 && form != _TableForm.desktop,
          ),
          for (final row in days[i].rows)
            _UsageRow(
              // The record itself: a page appended by Load More keeps every
              // expanded row expanded, and a reset starts them all closed.
              key: ObjectKey(row),
              row: row,
              form: form,
              kind: modelTags[row.modelDbId],
              onDelete: () => _confirmDeleteModelData(context, row.modelId),
            ),
        ],
        if (hasMore) _buildLoadMore(context, l10n),
      ],
    );
  }

  // --- Empty --------------------------------------------------------------

  Widget _buildEmpty(BuildContext context, AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: inset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.query_stats, size: 28, color: colorScheme.outline),
          const SizedBox(height: AppSpace.s10),
          Text(
            l10n.noUsageInRange,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpace.s4),
          Text(
            l10n.noUsageInRangeHint,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // --- Header rows --------------------------------------------------------

  Widget _buildColumnHeader(BuildContext context, AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;

    Widget caption(String label, {TextAlign align = TextAlign.start}) => Text(
      label.toUpperCase(),
      textAlign: align,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        letterSpacing: AppType.trackedLabelSpacing,
        color: colorScheme.onSurfaceVariant,
      ),
    );

    return Container(
      height: 40,
      color: colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: inset),
      child: Row(
        children: [
          SizedBox(width: modelWidth, child: caption(l10n.model)),
          const SizedBox(width: columnGap),
          Expanded(child: caption(l10n.usageColumnDetail)),
          const SizedBox(width: columnGap),
          SizedBox(width: specWidth, child: caption(l10n.usageSpecColumn)),
          const SizedBox(width: columnGap),
          SizedBox(width: timeWidth, child: caption(l10n.usageColumnTime)),
          const SizedBox(width: columnGap),
          SizedBox(
            width: costWidth,
            child: caption(l10n.usageColumnCost, align: TextAlign.end),
          ),
          const SizedBox(width: columnGap + chevronWidth),
        ],
      ),
    );
  }

  /// The day's name, how many records it holds, and what they cost — the
  /// total set on the cost column's right edge.
  Widget _buildDayRow(
    BuildContext context,
    AppLocalizations l10n,
    _TableForm form, {
    required DateTime day,
    required List<TokenUsage> rows,
    required bool partial,
    required bool first,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final total = rows.fold<double>(0, (sum, row) => sum + row.cost);
    final name = _dayName(l10n, day);
    final readout = textTheme.labelSmall?.mono.copyWith(color: colorScheme.onSurfaceVariant);

    return Container(
      constraints: const BoxConstraints(minHeight: 32),
      alignment: AlignmentDirectional.centerStart,
      padding: const EdgeInsets.symmetric(horizontal: inset, vertical: AppSpace.s6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: first ? null : Border(top: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          // The day and its count give way before the total does: which day it
          // is, is already half-answered by position on the page; what it cost
          // is the reason the row is here.
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    name ?? DateFormat('yyyy-MM-dd').format(day),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: (name == null ? textTheme.labelSmall?.mono : textTheme.labelSmall)
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (!partial) ...[
                  const SizedBox(width: AppSpace.s6),
                  Flexible(
                    child: Text(
                      '· ${l10n.usageRecordCount(rows.length)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: readout,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!partial) ...[
            const SizedBox(width: 8),
            Text('\$${total.toStringAsFixed(4)}', style: readout),
          ],
          SizedBox(width: _UsageRow.trailingWidth(form)),
        ],
      ),
    );
  }

  Widget _buildLoadMore(BuildContext context, AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    final total = totalCount;
    final perPage = pageSize;

    return Container(
      constraints: const BoxConstraints(minHeight: AppSize.touch),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppButton(
            label: l10n.loadMore,
            icon: Icons.expand_more,
            variant: AppButtonVariant.text,
            size: AppButtonSize.compact,
            loading: isLoadingMore,
            onPressed: onLoadMore,
          ),
          if (total != null && perPage != null) ...[
            const SizedBox(width: AppSpace.s10),
            Flexible(
              child: Text(
                l10n.usageLoadMoreStatus(perPage, usageData.length, total),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.mono.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // --- Grouping -----------------------------------------------------------

  /// Records bucketed by calendar day, newest first — the order the query
  /// already returns them in, so a day never appears twice.
  List<({DateTime day, List<TokenUsage> rows})> _groupByDay(List<TokenUsage> rows) {
    final days = <({DateTime day, List<TokenUsage> rows})>[];

    for (final row in rows) {
      final time = row.timestamp;
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
    // Taken now: the list rebuilds into another form when the width crosses
    // a breakpoint, and the context this was opened from goes with it.
    final navigator = Navigator.of(context);
    AppDialog.show<void>(
      context,
      icon: Icons.delete_outline,
      iconColor: Theme.of(context).colorScheme.error,
      title: l10n.clearDataForModel(modelId),
      content: Text(l10n.clearModelDataWarning(modelId)),
      maxWidth: 460,
      actions: [
        AppButton(label: l10n.cancel, variant: AppButtonVariant.text, onPressed: navigator.pop),
        AppButton(
          label: l10n.clearModelData,
          variant: AppButtonVariant.destructive,
          onPressed: () {
            // Close first: the reload behind this is a whole-range query,
            // and the dialog has nothing to show while it runs.
            navigator.pop();
            onClearModelUsage(modelId);
          },
        ),
      ],
    );
  }
}

/// One record: a collapsed row, and in place under it once expanded, the exact
/// counts and the action that clears the model's data.
class _UsageRow extends StatefulWidget {
  final TokenUsage row;
  final _TableForm form;
  final String? kind;
  final VoidCallback onDelete;

  const _UsageRow({
    super.key,
    required this.row,
    required this.form,
    required this.kind,
    required this.onDelete,
  });

  /// What follows the cost column, so a day's total can sit on the same edge.
  static double trailingWidth(_TableForm form) => form == _TableForm.desktop
      ? UsageList.columnGap + UsageList.chevronWidth
      : AppSpace.s4 + UsageList.chevronWidth;

  @override
  State<_UsageRow> createState() => _UsageRowState();
}

class _UsageRowState extends State<_UsageRow> {
  bool _expanded = false;

  TokenUsage get _row => widget.row;
  bool get _isTokenRow => _row.billing == UsageBilling.token;
  bool get _isSpecRow => _row.billing == UsageBilling.spec;

  /// The 「规格」 cell's text: null for a row of another mode.
  String? get _specLabel => _row.specLabel;

  /// Reference images this row sent, when its fee group charged for them
  /// (`D2c · 22f`) — by the price snapshotted on the row, so a group that
  /// never charged inputs shows nothing even though the count is kept. A
  /// request-billed row carries the input three alone (`D2e · 24e`), so the
  /// snapshot, not the mode, decides.
  int? get _chargedInputImages {
    final spec = _row.spec;
    if (spec == null) return null;
    return spec.inputUnitPrice > 0 && spec.inputImages > 0 ? spec.inputImages : null;
  }

  bool get _hasSpecCell => (_specLabel?.isNotEmpty ?? false) || _chargedInputImages != null;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final (minHeight, summary) = switch (widget.form) {
      _TableForm.desktop => (48.0, _buildDesktop(context)),
      _TableForm.tablet => (52.0, _buildTablet(context)),
      _TableForm.phone => (56.0, _buildPhone(context)),
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Material(
        // The faint accent wash marks which row is open.
        color: _expanded ? colorScheme.accentTint : Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: minHeight),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: UsageList.inset,
                    vertical: AppSpace.s6,
                  ),
                  child: summary,
                ),
              ),
            ),
            AnimatedSize(
              duration: AppMotion.durationOf(context, AppMotion.reveal),
              curve: AppMotion.enter,
              alignment: AlignmentDirectional.topStart,
              child: _expanded ? _buildDetails(context) : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }

  // --- Collapsed forms ----------------------------------------------------

  Widget _buildDesktop(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        SizedBox(
          width: UsageList.modelWidth,
          child: Row(
            children: [
              _kindPlate(context, 24),
              const SizedBox(width: 8),
              Expanded(child: _modelName(context)),
            ],
          ),
        ),
        const SizedBox(width: UsageList.columnGap),
        Expanded(
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: _detail(context, textTheme.bodySmall),
          ),
        ),
        const SizedBox(width: UsageList.columnGap),
        SizedBox(width: UsageList.specWidth, child: _spec(context)),
        const SizedBox(width: UsageList.columnGap),
        SizedBox(width: UsageList.timeWidth, child: _time(context)),
        const SizedBox(width: UsageList.columnGap),
        SizedBox(width: UsageList.costWidth, child: _cost(context, textTheme.bodySmall)),
        const SizedBox(width: UsageList.columnGap),
        _chevron(context),
      ],
    );
  }

  Widget _buildTablet(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        _kindPlate(context, 24),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _modelName(context),
              const SizedBox(height: 3),
              Row(
                children: [
                  Flexible(child: _detail(context, textTheme.labelSmall)),
                  if (_hasSpecCell) ...[
                    Text(
                      ' · ',
                      style: textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                    Flexible(child: _spec(context)),
                  ],
                  Text(
                    ' · ',
                    style: textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                  _time(context),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        _cost(context, textTheme.bodySmall),
        const SizedBox(width: AppSpace.s4),
        _chevron(context),
      ],
    );
  }

  Widget _buildPhone(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        _kindPlate(context, 28),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _modelName(context),
              const SizedBox(height: 3),
              // `21i`: the phone's second line is 「规格 · 时间」.
              Row(
                children: [
                  if (_hasSpecCell) ...[
                    Flexible(child: _spec(context)),
                    Text(
                      ' · ',
                      style: textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  _time(context),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        _cost(context, textTheme.bodyMedium, tooltip: false),
        const SizedBox(width: AppSpace.s4),
        _chevron(context),
      ],
    );
  }

  // --- Cells --------------------------------------------------------------

  /// The model's kind, as a glyph on a wash of its identity colour.
  Widget _kindPlate(BuildContext context, double size) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = usageModelKindColor(widget.kind) ?? colorScheme.onSurfaceVariant;
    final label = usageModelKindLabel(AppLocalizations.of(context)!, widget.kind);

    final plate = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: AppAlpha.tint),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Icon(
        usageModelKindGlyph(widget.kind),
        size: size > 24 ? AppSize.iconMd : AppSize.iconSm,
        color: color,
      ),
    );

    return label == null ? plate : Tooltip(message: label, child: plate);
  }

  /// The model, with any `[channel]` prefix lifted out of the id into a badge.
  ///
  /// The prefix is how the user tags which channel a model came through, so it
  /// is the same handful of strings over and over down the column. Left inline
  /// it pushed every real model name to a different x and made the column
  /// unscannable; as a badge it stays readable and the names line up.
  Widget _modelName(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final modelId = _row.modelId;
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
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
              child: Text(
                match.group(1)!,
                style: textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpace.s6),
          ],
          Flexible(
            child: Text(
              name,
              style: textTheme.bodySmall?.mono,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// What was billed: token counts keyed by their identity dots, or a count of
  /// requests.
  Widget _detail(BuildContext context, TextStyle? base) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final style = base?.copyWith(color: colorScheme.onSurfaceVariant);

    if (_isSpecRow) {
      // What the row counted, in its unit: 「2 张」 / 「8 秒」 / 「1 条」.
      final units = NumberFormat.decimalPattern().format((_row.spec?.units ?? 0).round());
      final text = switch (_row.spec?.unit) {
        OutputUnit.second => l10n.usageUnitsSecond(units),
        OutputUnit.clip => l10n.usageUnitsClip(units),
        OutputUnit.image || null => l10n.usageUnitsImage(units),
      };
      return Text(text, style: style, maxLines: 1, overflow: TextOverflow.ellipsis);
    }

    if (!_isTokenRow) {
      return Text(
        l10n.usageItemCount(_row.requestCount),
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    final cacheTokens = _row.cacheTokens;

    return Tooltip(
      message: [
        '${l10n.inputTokens}: ${_exact(_row.inputTokens)}',
        if (cacheTokens > 0) '${l10n.cachedInputTokens}: ${_exact(cacheTokens)}',
        '${l10n.outputTokens}: ${_exact(_row.outputTokens)}',
      ].join('\n'),
      // The column holds a user-chosen font at whatever width the window
      // leaves; scaling the chips down beats letting them overflow.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _tokenChip(context, UsageToken.input, _row.inputTokens, style),
            // Only rows that actually hit the cache carry the extra chip,
            // keeping the common no-cache row as compact as before.
            if (cacheTokens > 0) ...[
              const SizedBox(width: AppSpace.s10),
              _tokenChip(context, UsageToken.cache, cacheTokens, style),
            ],
            const SizedBox(width: AppSpace.s10),
            _tokenChip(context, UsageToken.output, _row.outputTokens, style),
          ],
        ),
      ),
    );
  }

  Widget _tokenChip(BuildContext context, UsageToken token, int tokens, TextStyle? style) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        UsageDot(token.colorOf(context), size: 6),
        const SizedBox(width: AppSpace.s4),
        Text(_abbreviate(tokens), style: style?.mono),
      ],
    );
  }

  /// The 「规格」 column (`D2b · 21g`): the spec the row was billed at, the
  /// absent dimensions left out; 「—」 in the outline colour for a row of
  /// another mode. An unmatched row's spec is stated in full — it is exactly
  /// what the user needs to copy into the rate table.
  Widget _spec(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final mono = Theme.of(context).textTheme.labelSmall?.mono;
    final spec = _specLabel ?? '';
    final inputs = _chargedInputImages;
    if (spec.isEmpty && inputs == null) {
      return Text('—', maxLines: 1, style: mono?.copyWith(color: colorScheme.outline));
    }
    // `D2c · 22f`: 「2K · 输入 3 张」 — the count sent, in the secondary ink.
    final input = inputs == null ? '' : l10n.usageSpecInputImages(inputs);
    final joiner = spec.isNotEmpty && input.isNotEmpty ? ' · ' : '';
    return Tooltip(
      message: '$spec$joiner$input',
      waitDuration: const Duration(milliseconds: 600),
      child: Text.rich(
        TextSpan(
          text: spec,
          children: [
            if (input.isNotEmpty)
              TextSpan(
                text: '$joiner$input',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: mono?.copyWith(color: colorScheme.onSurface),
      ),
    );
  }

  Widget _time(BuildContext context) {
    return Text(
      DateFormat('HH:mm').format(_row.timestamp),
      maxLines: 1,
      style: Theme.of(
        context,
      ).textTheme.labelSmall?.mono.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }

  /// Zero costs are stated but not shouted: a free row is still a row, and at
  /// full contrast a column of `$0.0000` drowns out the ones that cost money.
  ///
  /// A row the provider priced itself (`D2d · 23a`) is set exactly like the
  /// others — no glyph, no sub-label: the most trustworthy figure on the page
  /// must not look like the suspect one, and a marker on some rows breaks
  /// the right-aligned scan. Where there is a pointer, the cell's [tooltip]
  /// states the report against the table's estimate; the phone has none.
  Widget _cost(BuildContext context, TextStyle? base, {bool tooltip = true}) {
    final colorScheme = Theme.of(context).colorScheme;
    final cost = _row.cost;
    final reported = _row.reportedCost;

    final text = Text(
      '\$${cost.toStringAsFixed(4)}',
      textAlign: TextAlign.end,
      maxLines: 1,
      style: base?.mono.copyWith(
        fontWeight: FontWeight.w600,
        color: cost > 0 ? colorScheme.onSurface : colorScheme.outline,
      ),
    );
    if (reported == null || !tooltip) return text;
    final l10n = AppLocalizations.of(context)!;
    return Tooltip(
      message:
          '${l10n.usageReportedCost}: \$${reported.toStringAsFixed(4)}\n'
          '${l10n.usageTableEstimate}: \$${_row.snapshotCost.toStringAsFixed(4)}',
      child: text,
    );
  }

  Widget _chevron(BuildContext context) {
    return SizedBox(
      width: UsageList.chevronWidth,
      child: Icon(
        _expanded ? Icons.expand_less : Icons.expand_more,
        size: AppSize.iconMd,
        color: Theme.of(context).colorScheme.outline,
      ),
    );
  }

  /// The detail pairs two to a row, except a `wide` one, which has a row to
  /// itself: the input side's sum (「2 × $0.0200 = $0.0400」) does not fit
  /// half of a tablet's grid.
  static List<List<(String, String, {bool muted, bool wide})>> _gridRows(
    List<(String, String, {bool muted, bool wide})> pairs,
  ) {
    final rows = <List<(String, String, {bool muted, bool wide})>>[];
    for (final entry in pairs) {
      if (entry.wide || rows.isEmpty || rows.last.length == 2 || rows.last.single.wide) {
        rows.add([entry]);
      } else {
        rows.last.add(entry);
      }
    }
    return rows;
  }

  /// 「3 张 · 1 张免费」: the images sent, and how many of them the group's
  /// free count covered — sent less billed, the row keeping no free count of
  /// its own. A row without the count sent (none reached the column) states
  /// the billed ones alone; so does one that delivered nothing — its images
  /// went unbilled because the request failed, not because they were free.
  String _inputImagesText(AppLocalizations l10n, UsageSpecBilling spec) {
    final billed = spec.inputUnits.round();
    final sent = spec.inputImages > 0 ? spec.inputImages : billed;
    // A request-billed row is always delivered (its request was charged);
    // a spec row that delivered nothing was not charged, and its unbilled
    // images are not "free".
    final delivered = _isSpecRow ? spec.units > 0 : true;
    final free = delivered ? sent - billed : 0;
    // Its own plural-aware string: one reference, the first free, is the
    // common Seedream row, and 「1 images」 would be its headline.
    final count = l10n.usageInputSentCount(sent);
    return free > 0 ? '$count · ${l10n.usageInputFreeCount(free)}' : count;
  }

  // --- Expanded -----------------------------------------------------------

  /// The exact counts in a mono grid, set under the model name, and the action
  /// that clears this model's records.
  Widget _buildDetails(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final labelStyle = textTheme.labelSmall?.mono.copyWith(color: colorScheme.onSurfaceVariant);
    final valueStyle = textTheme.labelSmall?.mono.copyWith(color: colorScheme.onSurface);

    final spec = _row.spec;
    final chargesInput = spec != null && spec.inputUnitPrice > 0;
    final reported = _row.reportedCost;
    // `D2d · 23b`: on a row the provider priced itself, every value the rate
    // table *computed* (the estimate, the unit price, the two amounts) is
    // demoted to the outline ink; the request's facts stay as they are. The
    // demoted pair is the whole signal — disagreement is the norm on this
    // line (an `auto` quality the model settled), not a warning.
    final demoted = reported != null;
    String money(double v) => '\$${v.toStringAsFixed(4)}';

    final pairs = <(String, String, {bool muted, bool wide})>[
      // The comparison leads: the report, the only full-ink amount in the
      // grid, beside what the table would have charged. The estimate never
      // hides — a $0.0000 under a default token-mode group is the point.
      if (reported != null) ...[
        (l10n.usageReportedCost, money(reported), muted: false, wide: false),
        (l10n.usageTableEstimate, money(_row.snapshotCost), muted: true, wide: false),
      ],
      (l10n.requests, _exact(_row.requestCount), muted: false, wide: false),
      if (_isTokenRow) ...[
        (l10n.inputTokens, _exact(_row.inputTokens), muted: false, wide: false),
        (l10n.cachedInputTokens, _exact(_row.cacheTokens), muted: false, wide: false),
        (l10n.outputTokens, _exact(_row.outputTokens), muted: false, wide: false),
      ],
      if (_isSpecRow) ...[
        (
          l10n.usageSpecColumn,
          _specLabel?.isNotEmpty == true ? _specLabel! : '—',
          muted: false,
          wide: false,
        ),
        (l10n.usageUnitPrice, money(spec?.unitPrice ?? 0), muted: demoted, wide: false),
      ]
      // `D2e · 24e`: a request-billed row that charged inputs is the spec
      // row less its 「规格」 cell — the request price is its unit price.
      else if (chargesInput)
        (l10n.usageUnitPrice, money(_row.requestPrice), muted: demoted, wide: false),
      // `D2c · 22g`: a row whose group charges for reference images splits
      // its amount in two and writes the input side out — what was sent, how
      // many of those were free, and the sum. Other rows are as they were.
      if (chargesInput) ...[
        (
          l10n.usageOutputAmount,
          money(_isSpecRow ? spec.cost : _row.requestCount * _row.requestPrice),
          muted: demoted,
          wide: false,
        ),
        (l10n.specInputTitle, _inputImagesText(l10n, spec), muted: false, wide: true),
        (
          l10n.usageInputAmount,
          '${_exact(spec.inputUnits.round())} × ${money(spec.inputUnitPrice)} = ${money(spec.inputCost)}',
          // Fully free (one image sent, the first free): stated, not shouted.
          muted: demoted || spec.inputCost == 0,
          wide: true,
        ),
      ],
    ];

    Widget pair((String, String, {bool muted, bool wide}) entry) => Row(
      children: [
        Expanded(
          child: Text(entry.$1, style: labelStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 8),
        Text(
          entry.$2,
          style: entry.muted ? valueStyle?.copyWith(color: colorScheme.outline) : valueStyle,
        ),
      ],
    );

    final phone = widget.form == _TableForm.phone;

    final grid = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (phone)
            for (final (index, entry) in pairs.indexed) ...[
              if (index > 0) const SizedBox(height: AppSpace.s4),
              pair(entry),
            ]
          else
            for (final (index, row) in _gridRows(pairs).indexed) ...[
              if (index > 0) const SizedBox(height: AppSpace.s4),
              if (row.length == 1 && row.single.wide)
                pair(row.single)
              else
                Row(
                  children: [
                    Expanded(child: pair(row[0])),
                    const SizedBox(width: 24),
                    Expanded(child: row.length > 1 ? pair(row[1]) : const SizedBox.shrink()),
                  ],
                ),
            ],
        ],
      ),
    );

    final clear = AppButton(
      label: l10n.clearModelData,
      icon: Icons.delete_outline,
      variant: AppButtonVariant.destructiveText,
      size: AppButtonSize.compact,
      onPressed: widget.onDelete,
    );

    // Indented to the model name: the plate, and the gap after it.
    final indent = switch (widget.form) {
      _TableForm.desktop => UsageList.inset + 24 + 8,
      _TableForm.tablet => UsageList.inset + 24 + 12,
      _TableForm.phone => UsageList.inset + 28 + 12,
    };

    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(indent, 0, UsageList.inset, 12),
      child: phone
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                grid,
                const SizedBox(height: AppSpace.s6),
                clear,
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: Align(alignment: AlignmentDirectional.centerStart, child: grid),
                ),
                const SizedBox(width: AppSpace.s16),
                clear,
              ],
            ),
    );
  }

  /// `1.2K` where the exact figure is a tooltip away: the column is here to be
  /// compared down the page, and six digits per row defeats that.
  String _abbreviate(int value) {
    if (value < 1000) return '$value';
    if (value < 1000000) return '${(value / 1000).toStringAsFixed(1)}K';
    return '${(value / 1000000).toStringAsFixed(2)}M';
  }

  String _exact(int value) => NumberFormat.decimalPattern().format(value);
}
