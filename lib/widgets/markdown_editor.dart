import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../l10n/app_localizations.dart';

class MarkdownEditor extends StatefulWidget {
  final TextEditingController controller;
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
                _buildEditorContent(colorScheme),
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

  Widget _buildEditorContent(ColorScheme colorScheme) {
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
      inner = TextField(
        controller: widget.controller,
        maxLines: widget.expand ? null : widget.maxLines,
        expands: widget.expand,
        onChanged: widget.onChanged,
        readOnly: widget.isRefined,
        textAlignVertical: TextAlignVertical.top,
        decoration: InputDecoration(
          hintText: widget.hint,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(12),
          fillColor: widget.isRefined ? Colors.grey.withValues(alpha: 0.05) : null,
          filled: widget.isRefined,
        ),
        style: const TextStyle(fontSize: 13, height: 1.5),
      );
    }

    return Container(
      width: double.infinity,
      constraints: widget.expand ? null : BoxConstraints(
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