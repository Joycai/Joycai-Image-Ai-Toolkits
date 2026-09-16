part of '../prompt_optimizer_view.dart';

/// A staged prompt version, folded when long.
extension _PromptCard on _PromptOptimizerChatViewState {
  Widget _buildPromptCard(OptimizerChatEntry entry, AppLocalizations l10n, ColorScheme colorScheme) {
    final textTheme = Theme.of(context).textTheme;
    // Keyed by version rather than transcript index: a prompt card is the one
    // row a user scrolls back to, and the version is what identifies it.
    final key = entry.version ?? 1;
    final expanded = _expandedPrompts.contains(key);
    final isLong = entry.text.length > _PromptOptimizerChatViewState._promptFoldChars;
    final hasFooter = entry.note != null || isLong;

    return _underAvatar(
      _card(
        children: [
          _cardHeader(
            icon: Icons.text_snippet_outlined,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        l10n.optPromptTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _cardTitleStyle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _versionBadge('v${entry.version ?? 1}'),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Ghost: a bare glyph inside a card header, no box of its own.
              SizedBox.square(
                dimension: AppSize.compact,
                child: IconButton(
                  icon: const Icon(Icons.content_copy_outlined, size: AppSize.iconMd),
                  tooltip: l10n.optCopy,
                  padding: EdgeInsets.zero,
                  color: colorScheme.onSurfaceVariant,
                  style: IconButton.styleFrom(
                    minimumSize: const Size.square(AppSize.compact),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.control),
                    ),
                  ),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: entry.text));
                    AppSnackBar.success(context, l10n.optPromptCopied);
                  },
                ),
              ),
              const SizedBox(width: 6),
              // Tonal: this puts the model's output to work, so it is the
              // accent's — but outranked by the screen's one solid fill.
              AppButton(
                label: l10n.apply,
                variant: AppButtonVariant.tonal,
                size: AppButtonSize.compact,
                onPressed: () => widget.onApplyPrompt(entry.text),
              ),
              const SizedBox(width: 4),
            ],
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(12, 10, 12, hasFooter ? 4 : 12),
            // Folded to a readable opening rather than scrolled inside its own
            // box: a long prompt otherwise pushes the reply that explains it,
            // and the composer, off the bottom of the conversation.
            child: _fold(
              MarkdownBody(
                data: entry.text,
                selectable: true,
                styleSheet: MarkdownStyleSheet(
                  p: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface,
                    height: AppType.looseHeight,
                  ),
                ),
              ),
              folded: isLong && !expanded,
              fadeColor: colorScheme.surfaceContainerLow,
            ),
          ),
          // One footer row: the note and the expand link, in reading order.
          if (hasFooter)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Row(
                children: [
                  if (entry.note != null)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Text(
                          entry.note!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w400,
                            color: colorScheme.onSurfaceVariant,
                            height: AppType.proseHeight,
                          ),
                        ),
                      ),
                    ),
                  if (isLong)
                    _textAction(
                      expanded ? l10n.optPromptCollapse : l10n.optPromptExpand,
                      () => _rebuild(() {
                        if (!_expandedPrompts.remove(key)) _expandedPrompts.add(key);
                      }),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Shows the first [_promptFoldHeight] of [child] and hides the rest.
  ///
  /// The obvious `ConstrainedBox(maxHeight:) + ClipRect` does not work here and
  /// was the bug: `ClipRect` only clips the painting, so the markdown's inner
  /// `Column` was still being *laid out* inside the cap and reported a huge
  /// RenderFlex overflow for every long prompt. The child has to be given the
  /// unbounded height it wants — which is what [OverflowBox] is for — and the
  /// fixed-height box around it does the hiding. Width constraints are left
  /// null so they pass through untouched and the text wraps as it otherwise
  /// would.
  ///
  /// The fade over the last [_promptFadeHeight] is what tells the reader the
  /// text was cut rather than finished. It is drawn in the card's own fill,
  /// faded from the same colour at zero alpha rather than from
  /// [Colors.transparent], which is transparent *black* and lerps through grey.
  Widget _fold(Widget child, {required bool folded, required Color fadeColor}) {
    if (!folded) return child;
    return Stack(
      children: [
        ClipRect(
          child: SizedBox(
            height: _PromptOptimizerChatViewState._promptFoldHeight,
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minHeight: 0,
              maxHeight: double.infinity,
              child: child,
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: _PromptOptimizerChatViewState._promptFadeHeight,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [fadeColor.withValues(alpha: 0), fadeColor],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Feedback loop (`20b` / `20d`)
  // ---------------------------------------------------------------------------
}
