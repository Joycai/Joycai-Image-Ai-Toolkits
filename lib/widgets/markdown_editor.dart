import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../l10n/app_localizations.dart';

/// A specialized controller that provides basic syntax highlighting for Markdown.
class MarkdownTextEditingController extends TextEditingController {
  MarkdownTextEditingController({super.text});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final List<TextSpan> children = [];
    final colorScheme = Theme.of(context).colorScheme;

    // Basic Markdown Regex Patterns
    final RegExp regExp = RegExp(
      r'(?<header>^#+ .*$)|(?<bold>\*\*.*?\*\*)|(?<italic>_.*?_)|(?<link>\[.*?\]\(.*?\))|(?<list>^[*-] .*$|^[0-9]+\. .*$)',
      multiLine: true,
    );

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
          color: colorScheme.primary,
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

    return TextSpan(style: style, children: children);
  }
}

/// Normalizes all line endings to \n (LF) and provides smart list continuation.
class SmartMarkdownFormatter extends TextInputFormatter {
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
    if (newValue.text.length == oldValue.text.length + 1 && 
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
  final bool selectable;

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
    this.selectable = true,
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
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    final header = Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!widget.isRefined) ...[
              Checkbox(
                value: widget.isMarkdown,
                onChanged: (v) {
                  widget.onMarkdownChanged(v ?? false);
                  if (!(v ?? false)) {
                    setState(() => _isPreview = false);
                  }
                },
              ),
              const Text(
                "Markdown",
                style: TextStyle(fontSize: 12),
              ),
            ] else
              Text(
                widget.label,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
          ],
        ),
        if (widget.isMarkdown || widget.isRefined)
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(
                value: false,
                label: Text(l10n.edit),
                icon: const Icon(Icons.edit, size: 16),
              ),
              ButtonSegment(
                value: true,
                label: Text(l10n.preview),
                icon: const Icon(Icons.visibility, size: 16),
              ),
            ],
            selected: {_isPreview},
            onSelectionChanged: (v) => setState(() => _isPreview = v.first),
            style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(fontSize: 11),
            ),
          ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // If height is extremely limited (e.g. log console expanded on small screen),
        // fallback to a scrollable Column instead of using Expanded/Flexible
        // to prevent RenderFlex overflow errors.
        final bool isSpaceTooTight = widget.expand && constraints.maxHeight < 120;

        if (isSpaceTooTight) {
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                header,
                const SizedBox(height: 8),
                _buildEditorContent(colorScheme, forceDisableExpand: true),
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
          children: [
            header,
            const SizedBox(height: 8),
            if (widget.expand)
              Expanded(child: _buildEditorContent(colorScheme))
            else
              Flexible(child: _buildEditorContent(colorScheme)),
          ],
        );
      },
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
          const SingleActivator(LogicalKeyboardKey.tab): () {
            final String text = widget.controller.text;
            final TextSelection selection = widget.controller.selection;
            final String newText = text.replaceRange(selection.start, selection.end, '  ');
            widget.controller.value = TextEditingValue(
              text: newText,
              selection: TextSelection.collapsed(offset: selection.start + 2),
            );
          },
        },
        child: TextField(
          controller: widget.controller,
          minLines: shouldExpand ? null : (widget.maxLines > 5 ? 5 : widget.maxLines),
          maxLines: shouldExpand ? null : widget.maxLines,
          expands: shouldExpand,
          onChanged: widget.onChanged,
          readOnly: widget.isRefined,
          textAlignVertical: TextAlignVertical.top,
          inputFormatters: [SmartMarkdownFormatter()],
          decoration: InputDecoration(
            hintText: widget.hint,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.all(12),
            fillColor: widget.isRefined ? Colors.grey.withValues(alpha: 0.05) : null,
            filled: widget.isRefined,
          ),
          style: const TextStyle(fontSize: 13),
          strutStyle: const StrutStyle(
            fontSize: 13,
            height: 1.5,
            forceStrutHeight: true,
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      constraints: shouldExpand ? null : BoxConstraints(
        minHeight: math.min(120.0, widget.maxLines * 24.0),
        maxHeight: widget.maxLines * 24.0,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
        color: (_isPreview || widget.isRefined) ? colorScheme.surfaceContainerLowest : null,
      ),
      child: inner,
    );
  }
}