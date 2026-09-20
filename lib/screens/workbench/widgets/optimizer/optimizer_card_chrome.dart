part of '../prompt_optimizer_view.dart';

/// The transcript's card vocabulary: the avatar column, the card frame and
/// header, the text actions and badges every card below is built from.
extension _CardChrome on _PromptOptimizerChatViewState {
  /// The 26px r6 square that says whose line this is. No avatar on the
  /// user's own turns — the right-aligned bubble already says it.
  Widget _avatar(IconData icon, {required Color ground, required Color ink}) {
    return Container(
      width: _PromptOptimizerChatViewState._avatarSize,
      height: _PromptOptimizerChatViewState._avatarSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: ground,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Icon(icon, size: AppSize.iconMd, color: ink),
    );
  }

  /// An avatar with its content beside it, capped at the body width.
  /// `A3e 5e`: the one action an analysis result has. Copies the Markdown as
  /// written — what gets pasted elsewhere is the source, not its rendering.
  Widget _buildResultActions(
    String text,
    AppLocalizations l10n,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.s6),
      child: Transform.translate(
        // The button's own inset, given back, so its label starts on the
        // reply's left edge rather than a button-padding in from it.
        offset: const Offset(-AppSpace.s10, 0),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpace.s4,
          children: [
            AppButton(
              label: l10n.copy,
              icon: Icons.content_copy,
              variant: AppButtonVariant.text,
              size: AppButtonSize.compact,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: text));
                AppSnackBar.success(context, l10n.optResultCopied);
              },
            ),
            Text(
              l10n.optResultMeta(text.characters.length),
              style: textTheme.labelSmall?.mono.copyWith(color: colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }

  Widget _besideAvatar(Widget avatar, Widget content) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        avatar,
        const SizedBox(width: _PromptOptimizerChatViewState._avatarGap),
        Expanded(
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _PromptOptimizerChatViewState._bodyMaxWidth),
              child: content,
            ),
          ),
        ),
      ],
    );
  }

  /// A card that belongs to the assistant's turn, indented under its avatar
  /// so it lines up with the reply text (`A3b · 1a`).
  Widget _underAvatar(Widget card) {
    return Padding(
      padding: const EdgeInsets.only(left: _PromptOptimizerChatViewState._turnIndent),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _PromptOptimizerChatViewState._bodyMaxWidth),
          child: card,
        ),
      ),
    );
  }

  /// The transcript card: 1px hairline, r16, the column ground, clipped.
  ///
  /// The [Material] inside is what makes ink visible: a splash paints on the
  /// nearest Material, and without one here it would land on the scaffold
  /// underneath this card's own fill.
  Widget _card({required List<Widget> children, Color? ground, Color? edge}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: ground ?? colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: edge ?? colorScheme.outlineVariant),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: children,
        ),
      ),
    );
  }

  /// A card's 40px title bar: accent glyph, then [children], over a hairline.
  ///
  /// A minimum rather than a fixed height, so a header that has to wrap at a
  /// large text scale grows instead of overflowing. The right inset is 8, not
  /// 12, because the trailing element is nearly always a text action or a
  /// button with its own padding.
  Widget _cardHeader({
    required IconData icon,
    Color? iconColor,
    required List<Widget> children,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: _PromptOptimizerChatViewState._cardHeaderHeight),
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Icon(icon, size: AppSize.iconMd, color: iconColor ?? colorScheme.primary),
          const SizedBox(width: 8),
          ...children,
        ],
      ),
    );
  }

  TextStyle? get _cardTitleStyle => Theme.of(context).textTheme.bodySmall?.copyWith(
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurface,
      );

  TextStyle? get _cardMetaStyle => Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );

  /// A deep-ink text action — "Show all 8 steps", "Show full text". Smaller
  /// than a compact [AppButton] on purpose: it sits inside a 40px header or
  /// under 12px body text, where a 28px button reads as a second control row.
  Widget _textAction(String label, VoidCallback? onTap) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w500,
            color: onTap == null ? theme.colorScheme.outline : theme.colorScheme.accentText,
          ),
        ),
      ),
    );
  }

  /// `v3`: r4, the accent wash, mono 11/600 in the deep ink.
  Widget _versionBadge(String text) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: theme.colorScheme.accentTint,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.mono.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onAccentTint,
        ),
      ),
    );
  }

  /// A status badge on an opaque semantic container — r4, 11/500.
  Widget _statusBadge(String label, {required Color ground, required Color ink}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: ground,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: ink),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Agent process
  // ---------------------------------------------------------------------------
}
