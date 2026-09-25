part of '../prompt_optimizer_view.dart';

/// The composer pinned under the transcript: chips, field, send and stop.
extension _Composer on _PromptOptimizerChatViewState {
  /// Enter sends; Shift+Enter inserts a newline.
  ///
  /// This is a chat box, and every chat box works this way — the old
  /// Ctrl+Enter meant the most common action needed two hands and was
  /// undiscoverable without the tooltip. Shift+Enter keeps multi-line prompts
  /// possible, and the hint under the field says so.
  bool _isSendKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final isEnter =
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    return isEnter && !HardwareKeyboard.instance.isShiftPressed;
  }

  /// A composer chip: 11px, 2×8, r4, a hairline edge, a 14px glyph.
  Widget _composerChip({
    required IconData icon,
    required String label,
    required Color ink,
    Color? iconColor,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: AppSize.iconSm, color: iconColor ?? ink),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: ink),
            ),
          ),
        ],
      ),
    );
  }

  /// The "distill this session" chip (`20d`): deep ink while it can run,
  /// muted with an explanatory tooltip while the session has nothing to
  /// distill yet. A chip rather than a button — it must not outweigh the send
  /// control.
  Widget _buildDistillChip(
    AppLocalizations l10n,
    ColorScheme colorScheme, {
    required bool enabled,
  }) {
    final chip = InkWell(
      borderRadius: BorderRadius.circular(AppRadius.xs),
      onTap: enabled ? widget.onDistill : null,
      child: _composerChip(
        icon: Icons.auto_stories_outlined,
        label: l10n.optDistillAction,
        ink: enabled ? colorScheme.accentText : colorScheme.outline,
        iconColor: enabled ? colorScheme.primary : colorScheme.outline,
      ),
    );
    // The tooltip explains the *disabled* state — the enabled chip's label
    // already says what it does.
    return enabled ? chip : Tooltip(message: l10n.optDistillDisabledTooltip, child: chip);
  }

  /// 32px r10 on the accent (44 r16 on a phone); the track under muted ink
  /// while there is nothing it can do.
  Widget _buildSendButton(
    AppLocalizations l10n,
    ColorScheme colorScheme, {
    required bool enabled,
    required bool phone,
  }) {
    final double side = phone ? AppSize.touch : AppSize.control;
    return SizedBox.square(
      dimension: side,
      child: IconButton(
        icon: const Icon(Icons.arrow_upward_rounded, size: AppSize.iconMd),
        tooltip: l10n.optSend,
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          disabledBackgroundColor: colorScheme.surfaceContainerHighest,
          disabledForegroundColor: colorScheme.outline,
          minimumSize: Size.square(side),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(phone ? AppRadius.lg : AppRadius.control),
          ),
        ),
        onPressed: enabled ? widget.onSend : null,
      ),
    );
  }

  /// Stop, in the send button's slot and at its size: outlined in the error
  /// colour, not filled — stopping is a way out, not the action the screen is
  /// built around. Icon-only; the label is the tooltip and the `Esc` hint
  /// beside it.
  Widget _buildStopButton(AppLocalizations l10n, ColorScheme colorScheme, {required bool phone}) {
    final double side = phone ? AppSize.touch : AppSize.control;
    return SizedBox.square(
      dimension: side,
      child: IconButton(
        icon: const Icon(Icons.stop_rounded, size: AppSize.iconLg),
        tooltip: l10n.optAbort,
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          foregroundColor: colorScheme.error,
          minimumSize: Size.square(side),
          side: BorderSide(color: colorScheme.error.withValues(alpha: AppAlpha.edge)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(phone ? AppRadius.lg : AppRadius.control),
          ),
        ),
        onPressed: widget.onAbort,
      ),
    );
  }

  /// The composer: the text, what goes with it, and how to send or stop it.
  ///
  /// Two rows inside one r16 box: the field, and one toolbar under it. The
  /// toolbar's left is what leaves with the message (reference images,
  /// distill); its right is one slot that holds the send button, or — while a
  /// turn runs — the stop button in exactly its place, with the run's clock
  /// and the Esc hint beside it. One slot rather than two controls, so the
  /// hand goes to the same corner whichever way the turn is going. The
  /// toolbar is a row of its own rather than a suffix, so the control does
  /// not drift down the field as the text grows to six lines.
  Widget _buildInputBar(
    PromptOptimizerSession session,
    AppLocalizations l10n,
    ColorScheme colorScheme,
    int maxLines,
  ) {
    final busy = widget.isBusy;
    final canSend = !busy;
    final canStop = busy && widget.onAbort != null;
    final phone = _phone;
    final textTheme = Theme.of(context).textTheme;
    final attachedCount = context.watch<WorkbenchUIState>().optimizerReferenceImages.length;
    // The distill chip (`20d` a/b) rides the composer in knowledge sessions:
    // it sends a turn, so it belongs with the other send control.
    final showDistill = widget.onDistill != null && session.usesKnowledgeBase;
    final canDistill = !busy && session.promptVersions > 0;
    final feedbackCount = session.transcript
        .where((e) => e.kind == OptimizerEntryKind.resultFeedback)
        .length;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      ),
      padding: phone ? const EdgeInsets.all(12) : const EdgeInsets.fromLTRB(24, 12, 24, 16),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: _PromptOptimizerChatViewState._transcriptMaxWidth,
          ),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Focus(
                    onKeyEvent: (node, event) {
                      if (canSend && _isSendKey(event)) {
                        widget.onSend();
                        return KeyEventResult.handled;
                      }
                      // Esc stops the turn, which is what the hint under the
                      // field promises while one is running. Scoped to the
                      // composer rather than the screen: that is where the hint
                      // is, and a global Escape binding on the workbench would
                      // fight the dialogs and drawers that already use it.
                      if (busy &&
                          widget.onAbort != null &&
                          event is KeyDownEvent &&
                          event.logicalKey == LogicalKeyboardKey.escape) {
                        widget.onAbort!();
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: TextField(
                      controller: widget.inputCtrl,
                      minLines: 1,
                      maxLines: maxLines,
                      // Still focusable while busy — `enabled: false` would drop
                      // focus, and the Esc binding above lives on that focus.
                      // What it must not do is accept text that has nowhere to
                      // go until the turn ends.
                      readOnly: busy,
                      style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface,
                        height: AppType.proseHeight,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: false,
                        hintText: busy
                            ? l10n.optChatBusyHint
                            : _analysisPresetLoaded(session)
                            ? l10n.optChatHintAnalysis
                            : l10n.optChatHint,
                        hintStyle: textTheme.bodyMedium?.copyWith(
                          color: colorScheme.outline,
                          height: AppType.proseHeight,
                        ),
                        // All four, not just `border`. The app's
                        // InputDecorationTheme sets `enabledBorder` and
                        // `focusedBorder`, and those outrank `border` — so
                        // `border: InputBorder.none` alone left the field's own
                        // outline standing inside the composer box.
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 560;
                      // The counter beside the distill chip and the keyboard
                      // hint are the first things to go when the box narrows.
                      final showDistillCounts = showDistill && canDistill && wide;
                      return Row(
                        children: [
                          // A Wrap, so chips that no longer fit take a second
                          // line instead of pushing the send control out of
                          // the box.
                          Expanded(
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                if (attachedCount > 0)
                                  _composerChip(
                                    icon: Icons.image_outlined,
                                    label: l10n.optAttachedImages(attachedCount),
                                    // Muted while a turn runs: nothing is
                                    // about to leave with anything.
                                    ink: busy ? colorScheme.outline : colorScheme.onSurfaceVariant,
                                  ),
                                if (showDistill)
                                  _buildDistillChip(l10n, colorScheme, enabled: canDistill),
                                if (showDistillCounts)
                                  Text(
                                    l10n.optDistillCounts(session.promptVersions, feedbackCount),
                                    style: textTheme.labelSmall?.mono.copyWith(
                                      fontWeight: FontWeight.w400,
                                      color: colorScheme.outline,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // While running the trailing text is the run's clock
                          // and the key that *stops* it; idle it is the key
                          // that sends.
                          if (canStop)
                            _RunStatus(since: session.runStartedAt, hint: l10n.optAbortHint)
                          else if (wide)
                            Text(
                              l10n.optSendHint,
                              maxLines: 1,
                              style: textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w400,
                                color: colorScheme.outline,
                              ),
                            ),
                          const SizedBox(width: 10),
                          // One slot, one control: send, or stop in its place.
                          if (canStop)
                            _buildStopButton(l10n, colorScheme, phone: phone)
                          else
                            _buildSendButton(l10n, colorScheme, enabled: canSend, phone: phone),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What sits beside the stop button while a turn runs: a dot in the accent,
/// the clock, and the key that stops it — `● 37s · Esc 中断`.
class _RunStatus extends StatelessWidget {
  final DateTime? since;
  final String hint;

  const _RunStatus({required this.since, required this.hint});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hintStyle = theme.textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w400,
      color: colorScheme.outline,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: colorScheme.primary, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        _ElapsedLabel(since: since),
        const SizedBox(width: 6),
        Text('·', style: hintStyle),
        const SizedBox(width: 6),
        Text(hint, maxLines: 1, style: hintStyle),
      ],
    );
  }
}
