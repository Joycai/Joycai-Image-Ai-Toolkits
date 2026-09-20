import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../l10n/app_localizations.dart';
import 'app_button.dart';
import 'app_dialog.dart';
import 'app_icon_button.dart';
import 'app_segmented_control.dart';
import 'app_switch.dart';
import '../../core/design_tokens.dart';
import '../glass/app_glass_menu.dart';

part 'markdown_editor_large.dart';

/// A specialized controller that provides basic syntax highlighting for Markdown.
class MarkdownTextEditingController extends TextEditingController {
  MarkdownTextEditingController({super.text});

  /// Whether Markdown syntax is coloured. The editor showing this controller
  /// turns it off while its Markdown switch is off — plain text that happens
  /// to hold a `#` or a `_` is not a heading or an emphasis.
  ///
  /// Setting it notifies, so a field showing this controller repaints
  /// whoever set it.
  bool get highlight => _highlight;
  bool _highlight = true;
  set highlight(bool value) {
    if (_setHighlight(value)) notifyListeners();
  }

  /// The editor's own way in, from `initState` and `didUpdateWidget`: both run
  /// mid-build, where a notification would have listeners calling `setState`
  /// during a build — and where none is needed, since the field showing this
  /// controller is being rebuilt by the same pass.
  bool _setHighlight(bool value) {
    if (_highlight == value) return false;
    _highlight = value;
    _cachedSpan = null;
    return true;
  }

  /// Compiled once for the class, not once per call.
  ///
  /// [buildTextSpan] runs on every repaint of the field — caret blinks and
  /// selection changes included, not just edits — and building a `RegExp`
  /// compiles the pattern each time.
  static final RegExp _syntax = RegExp(
    r'(?<header>^#+ .*$)|(?<bold>\*\*.*?\*\*)|(?<italic>_.*?_)|(?<link>\[.*?\]\(.*?\))|(?<list>^[*-] .*$|^[0-9]+\. .*$)',
    multiLine: true,
  );

  // Last span handed out, with the inputs that produced it. A long prompt is
  // scanned end to end to build one, so repaints that change none of these —
  // the caret blink again — reuse it instead of re-scanning the document.
  String? _cachedText;
  TextStyle? _cachedStyle;
  ColorScheme? _cachedScheme;
  TextSpan? _cachedSpan;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    // The base class, not a bare span: it underlines the IME's composing run.
    if (!_highlight) {
      return super.buildTextSpan(context: context, style: style, withComposing: withComposing);
    }

    final colorScheme = Theme.of(context).colorScheme;

    if (_cachedSpan != null &&
        _cachedText == text &&
        _cachedStyle == style &&
        _cachedScheme == colorScheme) {
      return _withComposing(_cachedSpan!, withComposing);
    }

    final List<TextSpan> children = [];
    final RegExp regExp = _syntax;

    int lastMatchEnd = 0;
    for (final Match match in regExp.allMatches(text)) {
      // Add text before the match
      if (match.start > lastMatchEnd) {
        children.add(TextSpan(text: text.substring(lastMatchEnd, match.start)));
      }

      final String matchText = match.group(0)!;
      TextStyle? matchStyle;

      if (match.group(1) != null) { // header
        matchStyle = TextStyle(
          color: colorScheme.accentText,
          fontWeight: FontWeight.bold,
          fontSize: (style?.fontSize ?? 13) + 2,
        );
      } else if (match.group(2) != null) { // bold
        matchStyle = const TextStyle(fontWeight: FontWeight.bold);
      } else if (match.group(3) != null) { // italic
        matchStyle = const TextStyle(fontStyle: FontStyle.italic);
      } else if (match.group(4) != null) { // link
        matchStyle = TextStyle(color: colorScheme.tertiary, decoration: TextDecoration.underline);
      } else if (match.group(5) != null) { // list
        matchStyle = TextStyle(color: colorScheme.secondary, fontWeight: FontWeight.w500);
      }

      children.add(TextSpan(text: matchText, style: matchStyle));
      lastMatchEnd = match.end;
    }

    // Add remaining text
    if (lastMatchEnd < text.length) {
      children.add(TextSpan(text: text.substring(lastMatchEnd)));
    }

    final span = TextSpan(style: style, children: children);
    _cachedText = text;
    _cachedStyle = style;
    _cachedScheme = colorScheme;
    _cachedSpan = span;
    return _withComposing(span, withComposing);
  }

  /// [span] with the IME's composing run underlined, as the base class does
  /// for plain text. Laid over the cached span rather than built into it: the
  /// run moves with every keystroke of a composition and the syntax does not.
  TextSpan _withComposing(TextSpan span, bool withComposing) {
    final TextRange composing = value.composing;
    if (!withComposing || !value.isComposingRangeValid || composing.isCollapsed) return span;

    const underline = TextStyle(decoration: TextDecoration.underline);
    final List<InlineSpan> children = [];
    int offset = 0;
    for (final InlineSpan child in span.children ?? const <InlineSpan>[]) {
      final TextSpan piece = child as TextSpan;
      final String pieceText = piece.text ?? '';
      final int start = offset;
      final int end = offset + pieceText.length;
      offset = end;

      final int from = composing.start.clamp(start, end);
      final int to = composing.end.clamp(start, end);
      if (from == to) {
        children.add(piece);
        continue;
      }
      if (from > start) children.add(TextSpan(text: pieceText.substring(0, from - start), style: piece.style));
      children.add(TextSpan(
        text: pieceText.substring(from - start, to - start),
        style: piece.style?.merge(underline) ?? underline,
      ));
      if (to < end) children.add(TextSpan(text: pieceText.substring(to - start), style: piece.style));
    }
    return TextSpan(style: span.style, children: children);
  }
}

/// Normalizes all line endings to \n (LF) and provides smart list continuation.
class SmartMarkdownFormatter extends TextInputFormatter {
  const SmartMarkdownFormatter({this.continueLists = true});

  /// Off for plain text: a line that happens to start with "- " is not a list
  /// there. Line endings are normalized either way.
  final bool continueLists;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // 1. Normalize line endings
    String newText = newValue.text;
    if (newText.contains('\r')) {
      newText = newText.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    }

    // 2. Detect if a newline was just added to handle list continuation
    if (continueLists &&
        newValue.text.length == oldValue.text.length + 1 && 
        newValue.selection.isCollapsed && 
        newValue.selection.start > 0 &&
        newValue.text[newValue.selection.start - 1] == '\n') {
      
      final String textBeforeNewLine = oldValue.text.substring(0, oldValue.selection.start);
      final List<String> lines = textBeforeNewLine.split('\n');
      if (lines.isNotEmpty) {
        final String lastLine = lines.last;
        
        // Match "- " or "* " or "1. " etc.
        final RegExp listRegex = RegExp(r'^(\s*)([-*] |[0-9]+\. )(.*)$');
        final Match? match = listRegex.firstMatch(lastLine);
        
        if (match != null) {
          final String indent = match.group(1)!;
          final String prefix = match.group(2)!;
          final String content = match.group(3)!;
          
          if (content.trim().isEmpty) {
            // User pressed Enter on an empty list item: remove the prefix (end of list)
            final String textWithoutPrefix = oldValue.text.substring(0, oldValue.selection.start - (indent.length + prefix.length)) + oldValue.text.substring(oldValue.selection.start);
            return newValue.copyWith(
              text: textWithoutPrefix,
              selection: TextSelection.collapsed(offset: oldValue.selection.start - (indent.length + prefix.length)),
            );
          } else {
            // User pressed Enter on a populated list item: continue the list
            String newPrefix = prefix;
            if (RegExp(r'^[0-9]+\. $').hasMatch(prefix)) {
              // Increment numbered list
              final int currentNumber = int.parse(prefix.substring(0, prefix.length - 2));
              newPrefix = '${currentNumber + 1}. ';
            }
            
            final String autoInsert = indent + newPrefix;
            final String finalSub = newValue.text.substring(0, newValue.selection.start) + autoInsert + newValue.text.substring(newValue.selection.start);
            return newValue.copyWith(
              text: finalSub,
              selection: TextSelection.collapsed(offset: newValue.selection.start + autoInsert.length),
            );
          }
        }
      }
    }

    if (newText != newValue.text) {
      return newValue.copyWith(
        text: newText,
        selection: TextSelection.collapsed(offset: math.min(newValue.selection.start, newText.length)),
      );
    }

    return newValue;
  }
}

/// Tab in a prompt is two spaces over the selection, not a focus move.
///
/// A write to the controller is not an edit as far as the field is concerned,
/// so [onChanged] is called by hand — callers save from it.
/// Colours Markdown syntax in [controller] only while Markdown is on. A plain
/// [TextEditingController] never coloured anything and is left alone.
///
/// [duringBuild] is for `initState` / `didUpdateWidget`; see
/// [MarkdownTextEditingController._setHighlight].
void _syncMarkdownHighlight(TextEditingController controller, bool isMarkdown, {bool duringBuild = false}) {
  if (controller is! MarkdownTextEditingController) return;
  if (duringBuild) {
    controller._setHighlight(isMarkdown);
  } else {
    controller.highlight = isMarkdown;
  }
}

void _insertMarkdownTab(TextEditingController controller, ValueChanged<String>? onChanged) {
  final TextSelection selection = controller.selection;
  if (!selection.isValid) return;
  controller.value = TextEditingValue(
    text: controller.text.replaceRange(selection.start, selection.end, '  '),
    selection: TextSelection.collapsed(offset: selection.start + 2),
  );
  onChanged?.call(controller.text);
}

class MarkdownEditor extends StatefulWidget {
  final TextEditingController controller;
// ... (rest of the file remains similar)

// ... (rest of the class remains similar but using the new features)

  final String label;
  final String hint;
  final int maxLines;
  final bool isMarkdown;
  final ValueChanged<bool> onMarkdownChanged;
  final bool initiallyPreview;
  final ValueChanged<String>? onChanged;
  final bool isRefined;
  final bool expand;

  /// Whether to measure the height on offer before laying out.
  ///
  /// The measurement is a [LayoutBuilder], and a [LayoutBuilder] makes the
  /// whole subtree unmeasurable to an ancestor [IntrinsicHeight]. Pass false
  /// from a parent that guarantees this editor a workable minimum height and
  /// wants to ask it, in return, how tall it would like to be.
  final bool probeAvailableHeight;
  final bool selectable;

  /// Whether the body draws an outline of its own.
  ///
  /// True where the editor stands on a bare panel. Pass false when the caller
  /// already puts it inside an outlined card: `A1 16a` draws the workbench
  /// prompt as *one* box — header, body and footer under a single border, the
  /// header set off by a hairline instead — and a second outline around the
  /// body inside that box reads as a field nested in a field.
  ///
  /// Unframed, the header also takes the padding the card gave up, so the
  /// hairline can run the full width of the card rather than stopping short of
  /// it on both sides.
  final bool bordered;

  /// Shows an "expand editor" action that opens the same controller in a
  /// large dialog (fullscreen on mobile) — for editing long prompts
  /// comfortably. Disabled inside the pop-out itself.
  final bool allowExpand;

  const MarkdownEditor({
    super.key,
    required this.controller,
    required this.label,
    this.hint = '',
    this.maxLines = 10,
    required this.isMarkdown,
    required this.onMarkdownChanged,
    this.initiallyPreview = false,
    this.onChanged,
    this.isRefined = false,
    this.expand = false,
    this.probeAvailableHeight = true,
    this.selectable = true,
    this.allowExpand = true,
    this.bordered = true,
  });

  @override
  State<MarkdownEditor> createState() => _MarkdownEditorState();
}

class _MarkdownEditorState extends State<MarkdownEditor> {
  late bool _isPreview;

  @override
  void initState() {
    super.initState();
    _isPreview = (widget.initiallyPreview && widget.isMarkdown) || widget.isRefined;
    _syncMarkdownHighlight(widget.controller, widget.isMarkdown || widget.isRefined, duringBuild: true);
  }

  /// While the pop-out is open it is the editor on screen, and the one that
  /// says how the shared controller is coloured. This one, behind it, may be a
  /// rebuild late in hearing about the switch and must not write the old
  /// answer back over it.
  bool _popOutOpen = false;

  @override
  void didUpdateWidget(MarkdownEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A controller swapped in behind the pop-out is nobody else's to colour.
    if (_popOutOpen && oldWidget.controller == widget.controller) return;
    _syncMarkdownHighlight(widget.controller, widget.isMarkdown || widget.isRefined, duringBuild: true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    void setMarkdown(bool v) {
      widget.onMarkdownChanged(v);
      if (!v) setState(() => _isPreview = false);
    }

    final viewControls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.isMarkdown || widget.isRefined)
          // Raised and wordless, the way `A1 16a` draws it. Two reasons,
          // and neither is taste. This picks *which view of the same text*
          // you are looking at, which is the case `AppSegmentStyle.raised`
          // exists for — the lift says which one is chosen and the accent
          // stays free to mean "selected" inside the prompt itself. And
          // the icons had to go for the control to fit on the header's
          // one line at the config panel's 340px, where the design has
          // it side by side with the Markdown checkbox.
          AppSegmentedControl<bool>(
            segments: [
              AppSegment(value: false, label: l10n.edit),
              AppSegment(value: true, label: l10n.preview),
            ],
            value: _isPreview,
            onChanged: (v) => setState(() => _isPreview = v),
            compact: true,
            style: AppSegmentStyle.raised,
          ),
        if (widget.allowExpand) ...[
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.open_in_full, size: 16),
            onPressed: _openLargeEditor,
            tooltip: l10n.expandEditor,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ],
    );

    // A [Row], and one that needs the full width from its parent: the view
    // toggle and the expand button sit against the right edge, the expand
    // button where `A1 1a` draws it. The row's order — Markdown switch on the
    // left, toggle and expand on the right — is the ruling recorded at the end
    // of `A1d`'s spec, which replaces the order `1a` drew.
    //
    // This was a [Wrap] with `spaceBetween`, which failed twice. Under a
    // start-aligned [Column] it shrank to its children and had no slack to
    // hand out, so everything sat on the left. And a run holding one child is
    // laid out from the start, so when the controls did wrap they landed on
    // the left again. When the width runs short here, the right-hand group
    // scales down in place instead — nothing moves and nothing overflows.
    final header = Row(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!widget.isRefined) ...[
              // A switch, as `A1 1a` and the pop-out (`A1d`) both draw it: this
              // turns a mode on, it does not tick an item off. The word is part
              // of the control — the switch alone is 36×22, and the checkbox it
              // replaced brought a 48px target with it.
              // One node for a screen reader — 「Markdown, switch, on」 — not a
              // button and a switch that do the same thing.
              MergeSemantics(
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  onTap: () => setMarkdown(!widget.isMarkdown),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppSwitch(value: widget.isMarkdown, onChanged: setMarkdown),
                        const SizedBox(width: 6),
                        Text('Markdown', style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ),
              ),
            ] else
              Text(
                widget.label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              ),
          ],
        ),
        const SizedBox(width: 8),
        Expanded(
          // The [Align] is load-bearing. [Expanded] hands down a tight width,
          // and a [FittedBox] given one grows its child to fill it, taking the
          // height up in proportion; loosened first, it only ever scales down.
          child: Align(
            alignment: Alignment.centerRight,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: viewControls,
            ),
          ),
        ),
      ],
    );

    // Laid out against a caller's promise rather than a measurement, when the
    // caller is willing to make one. A [LayoutBuilder] cannot report intrinsic
    // dimensions — it would have to run its callback speculatively — so an
    // ancestor [IntrinsicHeight] over a subtree containing one throws. The
    // workbench's config panel is exactly that ancestor: it asks the column how
    // tall it wants to be so it can decide between filling and scrolling.
    //
    // So a caller that guarantees the floor itself opts out of the measurement.
    // Nothing is lost — the fallback below exists for callers that cannot.
    if (!widget.probeAvailableHeight) {
      return _buildBodyColumn(colorScheme, header: header);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // If height is extremely limited (e.g. log console expanded on small screen),
        // fallback to a scrollable Column instead of using Expanded/Flexible
        // to prevent RenderFlex overflow errors.
        final bool isSpaceTooTight = widget.expand && constraints.maxHeight < 120;

        if (isSpaceTooTight) {
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                header,
                const SizedBox(height: 8),
                _buildEditorContent(colorScheme, forceDisableExpand: true),
              ],
            ),
          );
        }

        return _buildBodyColumn(colorScheme, header: header);
      },
    );
  }

  /// Opens the same controller in the pop-out editor (`A1d`): a fullscreen
  /// dialog on narrow screens, a large centered dialog elsewhere. Text stays
  /// in sync automatically because the controller is shared.
  void _openLargeEditor() {
    // Outlives the switch between the two dialog forms below, so resizing the
    // window across the breakpoint keeps the editor's state.
    final editorKey = GlobalKey();

    _popOutOpen = true;
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        // Read here, not once at open: the window can be resized under it.
        final isCompact = MediaQuery.sizeOf(dialogContext).width < 600;
        final body = _LargeEditor(
          key: editorKey,
          controller: widget.controller,
          label: widget.label,
          hint: widget.hint,
          isMarkdown: widget.isMarkdown,
          onMarkdownChanged: widget.onMarkdownChanged,
          onChanged: widget.onChanged,
          readOnly: widget.isRefined,
          selectable: widget.selectable,
          initiallyPreview: _isPreview,
          onPreviewChanged: (v) {
            if (mounted && !widget.isRefined) setState(() => _isPreview = v);
          },
          compact: isCompact,
        );

        // Left as Dialog.fullscreen: on a phone the pop-out *is* the screen,
        // and a rounded card inset from the edges would waste the width the
        // user opened it to get.
        if (isCompact) {
          return Dialog.fullscreen(child: SafeArea(child: body));
        }

        final screen = MediaQuery.of(dialogContext).size;
        return AppDialog(
          clipBehavior: Clip.antiAlias,
          maxWidth: (screen.width * 0.8).clamp(0.0, 1000.0),
          // A deliberate height, not a ceiling: the editor should not resize
          // as the text grows under the cursor.
          maxHeight: screen.height * 0.85,
          // The body carries its own header and footer, and fills the card.
          contentPadding: EdgeInsets.zero,
          content: SizedBox(height: screen.height * 0.85, child: body),
        );
      },
    ).whenComplete(() {
      _popOutOpen = false;
      if (mounted) _syncMarkdownHighlight(widget.controller, widget.isMarkdown || widget.isRefined);
    });
  }

  /// Header over body, with the body taking the rest of the height when
  /// [expand] is on.
  ///
  /// Split out so both paths through [build] — the measured one and the
  /// caller-guaranteed one — lay the editor out identically. They differ only
  /// in whether a [LayoutBuilder] sits above this.
  Widget _buildBodyColumn(ColorScheme colorScheme, {required Widget header}) {
    return Column(
      // Stretch: the header is a [Row] that pins its controls to the right
      // edge, and the body fills the width. Both need a bounded width — the
      // text field always did.
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      children: [
        if (widget.bordered) ...[
          header,
          const SizedBox(height: 8),
        ] else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: AppAlpha.edge),
                ),
              ),
            ),
            child: header,
          ),
        if (widget.expand)
          Expanded(child: _buildEditorContent(colorScheme))
        else
          Flexible(child: _buildEditorContent(colorScheme)),
      ],
    );
  }

  Widget _buildEditorContent(ColorScheme colorScheme, {bool forceDisableExpand = false}) {
    final bool shouldExpand = widget.expand && !forceDisableExpand;
    Widget inner;
    if (_isPreview) {
      inner = MarkdownBody(
        data: widget.controller.text,
        selectable: false, // Handled by SelectionArea
      );
      
      if (widget.selectable) {
        inner = SelectionArea(child: inner);
      }
      
      inner = SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: inner,
      );
    } else {
      inner = CallbackShortcuts(
        bindings: {
          if (!widget.isRefined)
            const SingleActivator(LogicalKeyboardKey.tab): () => _insertMarkdownTab(widget.controller, widget.onChanged),
        },
        child: TextField(
          controller: widget.controller,
          minLines: shouldExpand ? null : (widget.maxLines > 5 ? 5 : widget.maxLines),
          maxLines: shouldExpand ? null : widget.maxLines,
          expands: shouldExpand,
          onChanged: widget.onChanged,
          readOnly: widget.isRefined,
          textAlignVertical: TextAlignVertical.top,
          inputFormatters: [SmartMarkdownFormatter(continueLists: widget.isMarkdown)],
          decoration: InputDecoration(
            hintText: widget.hint,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.all(12),
            fillColor: widget.isRefined ? Colors.grey.withValues(alpha: 0.05) : null,
            filled: widget.isRefined,
          ),
          style: Theme.of(context).textTheme.bodyMedium,
          strutStyle: const StrutStyle(
            fontSize: 13,
            height: AppType.looseHeight,
            forceStrutHeight: true,
          ),
        ),
      );
    }

    return Container(
      constraints: shouldExpand ? null : BoxConstraints(
        minHeight: math.min(120.0, widget.maxLines * 24.0),
        maxHeight: widget.maxLines * 24.0,
      ),
      decoration: BoxDecoration(
        border: widget.bordered ? Border.all(color: colorScheme.outlineVariant) : null,
        borderRadius: BorderRadius.circular(8),
        color: (_isPreview || widget.isRefined) ? colorScheme.surfaceContainerLowest : null,
      ),
      child: inner,
    );
  }
}