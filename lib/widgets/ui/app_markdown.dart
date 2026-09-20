import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../../core/app_theme.dart';
import '../../core/design_tokens.dart';
import '../../l10n/app_localizations.dart';
import 'dashed_border.dart';

/// How much room rendered markdown is given. See [AppMarkdownMetrics].
enum AppMarkdownDensity {
  /// Editor previews and the assistant's replies.
  prose,

  /// Prompt cards: headings a step smaller, no heading marks.
  compact;

  AppMarkdownMetrics get metrics => switch (this) {
        prose => AppMarkdownMetrics.prose,
        compact => AppMarkdownMetrics.compact,
      };
}

/// Markdown, rendered — the one place the app does it (`A1e`).
///
/// `flutter_markdown_plus` spaces every block, *and every list item*, by one
/// `blockSpacing`, so a stylesheet alone cannot set a heading close to its own
/// text and far from the text before it. This widget therefore parses the
/// source itself and lays the blocks out — gaps, lists, quotes, code, tables,
/// rules — and hands the library only what it is good at: one run of inline
/// text (a paragraph, a heading, a table cell).
///
/// What a prompt needs that a document does not:
///  * a single newline is kept — prompts are written one clause per line;
///  * an image is a placeholder — previewing someone's prompt makes no request;
///  * a link is coloured, not tappable — in a prompt it is material, not
///    navigation.
class AppMarkdown extends StatefulWidget {
  const AppMarkdown({
    super.key,
    required this.data,
    this.density = AppMarkdownDensity.prose,
    this.style,
    this.selectable = false,
  });

  final String data;
  final AppMarkdownDensity density;

  /// The body text. Headings are sized from it; defaults to `bodyMedium`.
  final TextStyle? style;

  /// Wraps the whole in a [SelectionArea]. Leave off when an ancestor already
  /// is one.
  final bool selectable;

  @override
  State<AppMarkdown> createState() => _AppMarkdownState();
}

class _AppMarkdownState extends State<AppMarkdown> implements MarkdownBuilderDelegate {
  static const _headings = {'h1': 0, 'h2': 1, 'h3': 2, 'h4': 3, 'h5': 3, 'h6': 3};

  List<Widget> _children = const [];
  late AppMarkdownMetrics _m;
  late ColorScheme _scheme;
  late TextStyle _body;
  late MarkdownStyleSheet _fallback;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _parse();
  }

  @override
  void didUpdateWidget(AppMarkdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.data != oldWidget.data || widget.density != oldWidget.density || widget.style != oldWidget.style) {
      _parse();
    }
  }

  void _parse() {
    final theme = Theme.of(context);
    _m = widget.density.metrics;
    _scheme = theme.colorScheme;
    final base = widget.style ?? theme.textTheme.bodyMedium ?? const TextStyle(fontSize: 14);
    _body = base.copyWith(color: base.color ?? _scheme.onSurface);
    _fallback = MarkdownStyleSheet.fromTheme(theme);

    final document = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored, encodeHtml: false);
    _children = _blocks(document.parse(widget.data), _body);
  }

  // ---------------------------------------------------------------- blocks

  List<Widget> _blocks(List<md.Node> nodes, TextStyle body, {int depth = 0, double? gap}) {
    final out = <Widget>[];
    String? previous;
    for (final node in nodes) {
      if (node is! md.Element) continue;
      if (previous != null) out.add(SizedBox(height: gap ?? _gapBetween(previous, node.tag)));
      out.add(_block(node, body, depth));
      previous = node.tag;
    }
    return out;
  }

  double _gapBetween(String above, String below) {
    final next = _headings[below];
    if (next != null) return math.max(_m.headingAbove[next], above == 'hr' ? _m.ruleGap : 0);
    if (above == 'hr' || below == 'hr') return _m.ruleGap;
    final prev = _headings[above];
    return prev != null ? _m.headingBelow[prev] : _m.blockGap;
  }

  Widget _block(md.Element el, TextStyle body, int depth) {
    final level = _headings[el.tag];
    if (level != null) return _heading(el, level, body);
    return switch (el.tag) {
      'ul' || 'ol' => _list(el, body, depth),
      'blockquote' => _quote(el, body, depth),
      'pre' => _CodeBlock(
          code: el.textContent.replaceFirst(RegExp(r'\n$'), ''),
          language: _languageOf(el),
          style: body,
          metrics: _m,
        ),
      'hr' => Container(height: 1, color: _scheme.outlineVariant),
      'table' => _table(el, body),
      _ => _inline(el, body),
    };
  }

  Widget _heading(md.Element el, int level, TextStyle body) {
    final size = (body.fontSize ?? 14) + _m.headingDelta[level];
    final style = body.copyWith(
      fontSize: size,
      fontWeight: FontWeight.w600,
      height: AppMarkdownMetrics.headingHeight,
      letterSpacing: level == 3 ? 0.3 : AppType.trackingFor(size),
      color: level == 3 ? _scheme.onSurfaceVariant : body.color,
    );
    Widget child = _inline(el, style);

    if (_m.headingMarks && level == 0) {
      child = Container(
        padding: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _scheme.outlineVariant))),
        child: child,
      );
    } else if (_m.headingMarks && level == 1) {
      // The same sign as the accent-coloured `##` in the source pane: H2 is
      // the skeleton of a prompt, and the one thing the eye scans for.
      final bar = size - 2;
      child = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            key: const ValueKey('app-markdown-h2-bar'),
            width: AppMarkdownMetrics.headingBarWidth,
            height: bar,
            margin: EdgeInsets.only(
              top: (size * AppMarkdownMetrics.headingHeight - bar) / 2,
              right: AppMarkdownMetrics.headingBarGap,
            ),
            decoration: BoxDecoration(color: _scheme.primary, borderRadius: BorderRadius.circular(2)),
          ),
          Expanded(child: child),
        ],
      );
    }
    return Semantics(header: true, child: child);
  }

  Widget _quote(md.Element el, TextStyle body, int depth) {
    return Container(
      padding: _m.quotePadding,
      decoration: BoxDecoration(
        // Neutral on purpose: the accent already marks H2, and two kinds of
        // coloured bar on one page fight.
        color: _scheme.surfaceContainerLow,
        border: Border(left: BorderSide(color: _scheme.outline, width: 2)),
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(AppRadius.sm)),
      ),
      child: _column(_blocks(el.children ?? const [], body.copyWith(color: _scheme.onSurfaceVariant), depth: depth)),
    );
  }

  // ----------------------------------------------------------------- lists

  Widget _list(md.Element el, TextStyle body, int depth) {
    final items = (el.children ?? const <md.Node>[]).whereType<md.Element>().where((e) => e.tag == 'li').toList();
    final ordered = el.tag == 'ol';
    final start = int.tryParse(el.attributes['start'] ?? '') ?? 1;
    final loose = items.any((li) => (li.children ?? const []).any((c) => c is md.Element && c.tag == 'p'));

    final marker = body.copyWith(
      color: _scheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    // One slot for the whole list, sized by its longest number.
    final digits = '${start + items.length - 1}'.length;
    final slot = ordered
        ? math.max(AppMarkdownMetrics.numberSlot, (digits + 1) * (body.fontSize ?? 14) * 0.62 + 6)
        : AppMarkdownMetrics.listIndent;

    final rows = <Widget>[];
    for (int i = 0; i < items.length; i++) {
      if (i > 0) rows.add(SizedBox(height: loose ? _m.blockGap : _m.itemGap));
      rows.add(_item(items[i], body, depth, loose,
          slot: slot,
          marker: ordered
              ? Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text('${start + i}.', style: marker, textAlign: TextAlign.right),
                )
              : Text(const ['•', '◦', '▪'][math.min(depth, 2)], style: marker)));
    }
    return _column(rows);
  }

  Widget _item(md.Element li, TextStyle body, int depth, bool loose, {required double slot, required Widget marker}) {
    final children = List<md.Node>.of(li.children ?? const []);

    // A task item: the parser leaves an `<input type=checkbox>` first, either
    // on the item or inside its paragraph.
    bool? checked;
    md.Element? takeBox(List<md.Node> from) =>
        from.isNotEmpty && from.first is md.Element && (from.first as md.Element).tag == 'input'
            ? from.removeAt(0) as md.Element
            : null;
    md.Element? box = takeBox(children);
    if (box == null && children.isNotEmpty && children.first is md.Element) {
      final first = children.first as md.Element;
      if (first.tag == 'p') {
        final inner = List<md.Node>.of(first.children ?? const []);
        box = takeBox(inner);
        if (box != null) children[0] = md.Element('p', inner);
      }
    }
    if (box != null) checked = box.attributes.containsKey('checked');

    // A tight item's text arrives as bare inline nodes; gather each run into
    // one paragraph so everything below deals in blocks.
    final blocks = <md.Node>[];
    List<md.Node>? run;
    for (final child in children) {
      if (child is md.Element && _isBlock(child.tag)) {
        run = null;
        blocks.add(child);
      } else {
        if (run == null) blocks.add(md.Element('p', run = <md.Node>[]));
        run.add(child);
      }
    }

    final text = checked == true ? body.copyWith(color: _scheme.onSurfaceVariant) : body;
    final lineHeight = (body.fontSize ?? 14) * (body.height ?? 1.4);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (checked != null)
          Padding(
            padding: EdgeInsets.only(
              top: math.max(0, (lineHeight - AppMarkdownMetrics.taskBox) / 2),
              left: 1,
              right: 8,
            ),
            child: _TaskBox(checked: checked, scheme: _scheme),
          )
        else
          SizedBox(width: slot, child: marker),
        Expanded(child: _column(_blocks(blocks, text, depth: depth + 1, gap: loose ? null : _m.itemGap))),
      ],
    );
  }

  static bool _isBlock(String tag) =>
      _headings.containsKey(tag) || const {'p', 'ul', 'ol', 'blockquote', 'pre', 'hr', 'table'}.contains(tag);

  // ---------------------------------------------------------------- tables

  Widget _table(md.Element el, TextStyle body) {
    final rows = <md.Element>[
      for (final section in (el.children ?? const <md.Node>[]).whereType<md.Element>())
        ...(section.children ?? const <md.Node>[]).whereType<md.Element>().where((e) => e.tag == 'tr'),
    ];
    final columns = rows.fold<int>(0, (n, r) => math.max(n, r.children?.length ?? 0));
    if (columns == 0) return const SizedBox.shrink();

    final head = body.copyWith(
      fontSize: (body.fontSize ?? 14) - 1,
      fontWeight: FontWeight.w600,
      color: _scheme.onSurfaceVariant,
    );
    final line = BorderSide(color: _scheme.outlineVariant);

    final table = Table(
      defaultColumnWidth: const IntrinsicColumnWidth(flex: 1),
      border: TableBorder(horizontalInside: line),
      children: [
        for (final row in rows)
          TableRow(
            decoration: _isHeader(row) ? BoxDecoration(color: _scheme.surfaceContainerLow) : null,
            children: [
              for (final cell in (row.children ?? const <md.Node>[]).whereType<md.Element>())
                Padding(
                  padding: _m.cellPadding,
                  child: _inline(
                    md.Element('p', cell.children ?? const []),
                    cell.tag == 'th' ? head : body,
                    align: switch (cell.attributes['align']) {
                      'center' => WrapAlignment.center,
                      'right' => WrapAlignment.end,
                      _ => WrapAlignment.start,
                    },
                  ),
                ),
              for (int i = row.children?.length ?? 0; i < columns; i++) const SizedBox.shrink(),
            ],
          ),
      ],
    );

    // Too wide for the measure, the table scrolls by itself rather than
    // pushing the text column out; narrower, it fills the measure.
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(border: Border.fromBorderSide(line), borderRadius: BorderRadius.circular(AppRadius.sm)),
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.hasBoundedWidth ? constraints.maxWidth : 0),
            child: table,
          ),
        ),
      ),
    );
  }

  static bool _isHeader(md.Element row) =>
      (row.children ?? const <md.Node>[]).whereType<md.Element>().any((c) => c.tag == 'th');

  // ---------------------------------------------------------------- inline

  /// One run of inline text, set by the library in [style].
  Widget _inline(md.Element el, TextStyle style, {WrapAlignment align = WrapAlignment.start}) {
    final size = style.fontSize ?? 14;
    final sheet = _fallback.merge(MarkdownStyleSheet(
      p: style,
      h1: style,
      h2: style,
      h3: style,
      h4: style,
      h5: style,
      h6: style,
      pPadding: EdgeInsets.zero,
      h1Padding: EdgeInsets.zero,
      h2Padding: EdgeInsets.zero,
      h3Padding: EdgeInsets.zero,
      h4Padding: EdgeInsets.zero,
      h5Padding: EdgeInsets.zero,
      h6Padding: EdgeInsets.zero,
      textAlign: align,
      h1Align: align,
      h2Align: align,
      h3Align: align,
      h4Align: align,
      h5Align: align,
      h6Align: align,
      strong: const TextStyle(fontWeight: FontWeight.w700),
      em: const TextStyle(fontStyle: FontStyle.italic),
      del: const TextStyle(decoration: TextDecoration.lineThrough),
      code: style.mono.copyWith(fontSize: size * 0.86, backgroundColor: _scheme.surfaceContainerHighest),
      a: TextStyle(
        color: _scheme.onAccentTint,
        decoration: TextDecoration.underline,
        decorationColor: _scheme.accentRing,
      ),
      blockSpacing: _m.itemGap,
    ));

    final built = MarkdownBuilder(
      delegate: this,
      selectable: false,
      styleSheet: sheet,
      imageDirectory: null,
      imageBuilder: (uri, title, alt) => _ImagePlaceholder(label: alt ?? title ?? uri.pathSegments.lastOrNull ?? '', style: style),
      checkboxBuilder: null,
      bulletBuilder: null,
      builders: {'a': _InertLinkBuilder()},
      paddingBuilders: const {},
      listItemCrossAxisAlignment: MarkdownListItemCrossAxisAlignment.start,
      softLineBreak: true,
    ).build([el]);
    return built.length == 1 ? built.single : _column(built);
  }

  static Widget _column(List<Widget> children) => children.length == 1
      ? children.single
      : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: children);

  static String? _languageOf(md.Element pre) {
    final code = (pre.children ?? const <md.Node>[]).whereType<md.Element>().firstOrNull;
    final cls = code?.attributes['class'];
    return cls != null && cls.startsWith('language-') ? cls.substring('language-'.length) : null;
  }

  // -------------------------------------------------- MarkdownBuilderDelegate

  // Never reached: `a` has a builder, so the library asks for no recognizer.
  @override
  GestureRecognizer createLink(String text, String? href, String title) => TapGestureRecognizer();

  // Never reached: `pre` is drawn by [_CodeBlock].
  @override
  TextSpan formatText(MarkdownStyleSheet styleSheet, String code) => TextSpan(text: code, style: styleSheet.code);

  @override
  Widget build(BuildContext context) {
    final body = _column(_children.isEmpty ? const [SizedBox.shrink()] : _children);
    return widget.selectable ? SelectionArea(child: body) : body;
  }
}

/// A link as text in the link colour, with no recognizer: not tappable, and no
/// pointer cursor promising that it is.
class _InertLinkBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    return Text.rich(TextSpan(
      text: element.textContent,
      style: (parentStyle ?? const TextStyle()).merge(preferredStyle),
    ));
  }
}

/// `![alt](src)` without the request.
class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder({required this.label, required this.style});

  final String label;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = (style.fontSize ?? 14) - 2;
    return DashedBorder(
      color: scheme.outline,
      radius: AppRadius.sm,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_outlined, size: size + 2, color: scheme.onSurfaceVariant),
            if (label.isNotEmpty) ...[
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: style.copyWith(fontSize: size, color: scheme.onSurfaceVariant, height: 1.3),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Read-only: a preview does not write to its source.
class _TaskBox extends StatelessWidget {
  const _TaskBox({required this.checked, required this.scheme});

  final bool checked;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    const size = AppMarkdownMetrics.taskBox;
    return Semantics(
      checked: checked,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: checked ? scheme.primary : null,
          border: checked ? null : Border.all(color: scheme.outline, width: 1.5),
          borderRadius: BorderRadius.circular(AppRadius.xs),
        ),
        child: checked ? Icon(Icons.check, size: size - 2, color: scheme.onPrimary) : null,
      ),
    );
  }
}

/// A fenced block: mono, never wrapped, scrolled sideways, copied whole.
class _CodeBlock extends StatefulWidget {
  const _CodeBlock({required this.code, required this.language, required this.style, required this.metrics});

  final String code;
  final String? language;
  final TextStyle style;
  final AppMarkdownMetrics metrics;

  @override
  State<_CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<_CodeBlock> {
  bool _hovered = false;
  bool _copied = false;
  Timer? _copiedTimer;

  // No pointer to hover with: the button is simply there.
  bool get _touch =>
      defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    setState(() => _copied = true);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final size = (widget.style.fontSize ?? 14) - 2;
    final copies = widget.metrics.copiesCode && l10n != null;
    final showCopy = copies && (_hovered || _touch || _copied);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Stack(
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: widget.metrics.codePadding,
              child: Text(
                widget.code,
                softWrap: false,
                style: widget.style.mono.copyWith(fontSize: size, height: 1.6, color: scheme.onSurface),
              ),
            ),
            Positioned(
              top: 6,
              right: 6,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.language != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        widget.language!,
                        style: widget.style.mono.copyWith(fontSize: 10.5, height: 1.3, color: scheme.onSurfaceVariant),
                      ),
                    ),
                  if (showCopy)
                    Tooltip(
                      message: _copied ? l10n.editorCopied : l10n.copy,
                      child: Material(
                        color: _copied ? scheme.accentTint : scheme.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          side: BorderSide(
                            color: _copied ? scheme.accentRing : scheme.outlineVariant,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: _copy,
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: Icon(
                              _copied ? Icons.check : Icons.content_copy,
                              size: 13,
                              color: _copied ? scheme.primary : scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
