import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:provider/provider.dart';

import '../../../core/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/prompt_optimizer_agent.dart';
import '../../../state/workbench_ui_state.dart';

/// Multi-turn chat view for the prompt-optimizer agent.
///
/// Renders the session transcript (user turns, assistant replies, tool-call
/// chips, staged prompt versions) with an input bar at the bottom. The
/// heavy lifting happens in [PromptOptimizerAgent]; this widget only observes
/// the session.
class PromptOptimizerChatView extends StatefulWidget {
  final TextEditingController inputCtrl;
  final VoidCallback onSend;
  final VoidCallback onRetry;
  final void Function(String prompt) onApplyPrompt;

  /// Writes a staged knowledge-base edit to disk after the user approves it.
  final void Function(String editId) onApplyKbEdit;

  /// Discards a staged knowledge-base edit.
  final void Function(String editId) onRejectKbEdit;
  final bool isBusy;

  const PromptOptimizerChatView({
    super.key,
    required this.inputCtrl,
    required this.onSend,
    required this.onRetry,
    required this.onApplyPrompt,
    required this.onApplyKbEdit,
    required this.onRejectKbEdit,
    required this.isBusy,
  });

  @override
  State<PromptOptimizerChatView> createState() => _PromptOptimizerChatViewState();
}

class _PromptOptimizerChatViewState extends State<PromptOptimizerChatView> {
  final ScrollController _scrollCtrl = ScrollController();
  PromptOptimizerSession? _session;
  int _lastTranscriptLength = 0;

  /// Edit ids whose full proposed content is expanded. Purely presentational.
  final Set<String> _expandedKbEdits = {};

  @override
  void dispose() {
    _session?.removeListener(_onSessionChanged);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _attachSession(PromptOptimizerSession session) {
    if (identical(_session, session)) return;
    _session?.removeListener(_onSessionChanged);
    _session = session;
    _lastTranscriptLength = session.transcript.length;
    session.addListener(_onSessionChanged);
  }

  void _onSessionChanged() {
    if (!mounted) return;
    final length = _session?.transcript.length ?? 0;
    if (length != _lastTranscriptLength) {
      _lastTranscriptLength = length;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
    setState(() {});
  }

  void _scrollToBottom() {
    if (!_scrollCtrl.hasClients) return;
    _scrollCtrl.animateTo(
      _scrollCtrl.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  bool _isCtrlEnter(KeyEvent event) {
    return event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter) &&
        (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<WorkbenchUIState>().optimizerSession;
    _attachSession(session);
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Expanded(
          child: session.transcript.isEmpty
              ? _buildEmptyState(l10n, colorScheme)
              : _buildTranscript(session, l10n, colorScheme),
        ),
        if (session.isRunning || widget.isBusy) _buildWorkingIndicator(l10n, colorScheme),
        _buildInputBar(l10n, colorScheme),
      ],
    );
  }

  Widget _buildEmptyState(AppLocalizations l10n, ColorScheme colorScheme) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_fix_high, size: 44, color: colorScheme.outlineVariant),
            const SizedBox(height: 16),
            Text(
              l10n.optEmptyChat,
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTranscript(
    PromptOptimizerSession session,
    AppLocalizations l10n,
    ColorScheme colorScheme,
  ) {
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      itemCount: session.transcript.length,
      itemBuilder: (context, index) {
        final entry = session.transcript[index];
        final isLast = index == session.transcript.length - 1;
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 780),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildEntry(entry, isLast, l10n, colorScheme),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEntry(OptimizerChatEntry entry, bool isLast, AppLocalizations l10n, ColorScheme colorScheme) {
    switch (entry.kind) {
      case OptimizerEntryKind.user:
        return Align(
          alignment: Alignment.centerRight,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 560),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: SelectableText(
              entry.text,
              style: TextStyle(color: colorScheme.onPrimaryContainer, fontSize: 13, height: 1.4),
            ),
          ),
        );

      case OptimizerEntryKind.assistant:
        return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 640),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(14),
            ),
            child: MarkdownBody(
              data: entry.text,
              selectable: true,
              styleSheet: MarkdownStyleSheet(
                p: TextStyle(color: colorScheme.onSurface, fontSize: 13, height: 1.4),
              ),
            ),
          ),
        );

      case OptimizerEntryKind.tool:
        final String label;
        final IconData icon;
        switch (entry.toolName) {
          case 'view_image':
            label = l10n.optToolViewImage(entry.text);
            icon = Icons.visibility_outlined;
          case 'read_knowledge_file':
            label = l10n.optToolReadKnowledge(entry.text);
            icon = Icons.menu_book_outlined;
          case 'list_knowledge_files':
            label = l10n.optToolListKnowledge;
            icon = Icons.folder_outlined;
          case 'write_knowledge_file':
            // Only reached for restored sessions — a live staged edit renders
            // as an actionable kbEdit card instead.
            label = l10n.optToolWriteKnowledge(entry.text);
            icon = Icons.edit_note_outlined;
          default:
            label = l10n.optToolListImages;
            icon = Icons.checklist_rtl;
        }
        return Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: colorScheme.outline),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: colorScheme.outline),
                  ),
                ),
              ],
            ),
          ),
        );

      case OptimizerEntryKind.prompt:
        return _buildPromptCard(entry, l10n, colorScheme);

      case OptimizerEntryKind.kbEdit:
        return _buildKbEditCard(entry, l10n, colorScheme);

      case OptimizerEntryKind.notice:
        final noticeText = switch (entry.text) {
          PromptOptimizerAgent.compactedNoticeToken => l10n.optCompactedNotice,
          PromptOptimizerAgent.imageMissingNoticeToken => l10n.optImageMissing,
          _ => entry.text,
        };
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.info_outline, size: 13, color: colorScheme.outline),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    noticeText,
                    style: TextStyle(fontSize: 11, color: colorScheme.outline, fontStyle: FontStyle.italic),
                  ),
                ),
              ],
            ),
          ),
        );

      case OptimizerEntryKind.error:
        return Align(
          alignment: Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                constraints: const BoxConstraints(maxWidth: 640),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: SelectableText(
                  entry.text,
                  style: TextStyle(color: colorScheme.onErrorContainer, fontSize: 12, height: 1.4),
                ),
              ),
              // The failed turn's context (user message, tool results) is
              // still in the session history — retrying just re-runs the
              // agent turn without re-reading knowledge or images.
              if (isLast && !widget.isBusy)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: OutlinedButton.icon(
                    onPressed: widget.onRetry,
                    icon: const Icon(Icons.refresh, size: 15),
                    label: Text(l10n.optRetry, style: const TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                  ),
                ),
            ],
          ),
        );
    }
  }

  /// Preview card for a knowledge-base edit the agent proposed. Nothing has
  /// been written yet — this card is the approval gate.
  Widget _buildKbEditCard(OptimizerChatEntry entry, AppLocalizations l10n, ColorScheme colorScheme) {
    final state = entry.editState ?? KbEditState.pending;
    final isCreate = entry.oldContent == null;
    final pending = state == KbEditState.pending;
    final editId = entry.editId!;
    final expanded = _expandedKbEdits.contains(editId);
    final content = entry.newContent ?? '';
    // A model that truncates its output would silently gut the file; the length
    // drop is the cheapest signal for the most destructive failure mode.
    final suspiciousShrink = !isCreate &&
        entry.oldContent!.length > 200 &&
        content.length < entry.oldContent!.length ~/ 2;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: pending
              ? colorScheme.primary.withValues(alpha: 0.45)
              : colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 0),
            child: Row(
              children: [
                Icon(
                  isCreate ? Icons.note_add_outlined : Icons.edit_note_outlined,
                  size: 15,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  isCreate ? l10n.kbEditProposedCreate : l10n.kbEditProposedUpdate,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    entry.targetPath ?? '',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (entry.note != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
              child: Text(
                entry.note!,
                style: TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if (suspiciousShrink)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_outlined, size: 14, color: colorScheme.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l10n.kbEditShrinkWarning(entry.oldContent!.length, content.length),
                      style: TextStyle(fontSize: 11, color: colorScheme.error),
                    ),
                  ),
                ],
              ),
            ),
          // Collapsed by default: a knowledge file can run to thousands of
          // characters and would bury the rest of the conversation.
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 14, 0),
            child: Row(
              children: [
                // Flexible + ellipsis: the label carries a character count and
                // is translated, so its width is not knowable up front — an
                // unflexed child here would size past a narrow card.
                Flexible(
                  child: TextButton.icon(
                    onPressed: () => setState(() {
                      expanded ? _expandedKbEdits.remove(editId) : _expandedKbEdits.add(editId);
                    }),
                    icon: Icon(expanded ? Icons.expand_less : Icons.expand_more, size: 16),
                    label: Text(
                      expanded ? l10n.kbEditHide : l10n.kbEditShow(content.length),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11),
                    ),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (expanded)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(14, 4, 14, 0),
              padding: const EdgeInsets.all(10),
              constraints: const BoxConstraints(maxHeight: 320),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  content,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.45,
                    fontFamily: 'monospace',
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 10, 10),
            child: pending
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => widget.onRejectKbEdit(editId),
                        child: Text(l10n.kbEditReject, style: const TextStyle(fontSize: 12)),
                      ),
                      const SizedBox(width: 6),
                      FilledButton.tonalIcon(
                        onPressed: () => widget.onApplyKbEdit(editId),
                        icon: const Icon(Icons.save_outlined, size: 15),
                        label: Text(l10n.kbEditApply, style: const TextStyle(fontSize: 12)),
                        style: tonalButtonStyle(colorScheme)
                            .copyWith(visualDensity: VisualDensity.compact),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Icon(
                        switch (state) {
                          KbEditState.applied => Icons.check_circle_outline,
                          KbEditState.rejected => Icons.cancel_outlined,
                          _ => Icons.error_outline,
                        },
                        size: 14,
                        color: state == KbEditState.failed
                            ? colorScheme.error
                            : colorScheme.outline,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          switch (state) {
                            KbEditState.applied => l10n.kbEditApplied,
                            KbEditState.rejected => l10n.kbEditRejected,
                            _ => l10n.kbEditFailedShort,
                          },
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: state == KbEditState.failed
                                ? colorScheme.error
                                : colorScheme.outline,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPromptCard(OptimizerChatEntry entry, AppLocalizations l10n, ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.tertiary.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 8, 0),
            child: Row(
              children: [
                Icon(Icons.auto_awesome, size: 15, color: colorScheme.tertiary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n.optPromptVersion(entry.version ?? 1),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.tertiary,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy_outlined, size: 16),
                  tooltip: l10n.optCopy,
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: entry.text));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.optPromptCopied)),
                    );
                  },
                ),
                FilledButton.tonalIcon(
                  onPressed: () => widget.onApplyPrompt(entry.text),
                  icon: const Icon(Icons.check, size: 15),
                  label: Text(l10n.apply, style: const TextStyle(fontSize: 12)),
                  style: tonalButtonStyle(Theme.of(context).colorScheme)
                      .copyWith(visualDensity: VisualDensity.compact),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
            child: MarkdownBody(
              data: entry.text,
              selectable: true,
              styleSheet: MarkdownStyleSheet(
                p: TextStyle(color: colorScheme.onSurface, fontSize: 13, height: 1.45),
              ),
            ),
          ),
          if (entry.note != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Text(
                entry.note!,
                style: TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWorkingIndicator(AppLocalizations l10n, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 8),
          Text(
            l10n.optAgentWorking,
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar(AppLocalizations l10n, ColorScheme colorScheme) {
    final canSend = !widget.isBusy;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: Focus(
            onKeyEvent: (node, event) {
              if (canSend && _isCtrlEnter(event)) {
                widget.onSend();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: TextField(
              controller: widget.inputCtrl,
              minLines: 1,
              maxLines: 6,
              enabled: true,
              style: const TextStyle(fontSize: 13, height: 1.4),
              decoration: InputDecoration(
                hintText: l10n.optChatHint,
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
                filled: true,
                fillColor: colorScheme.surfaceContainerHigh,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.send_rounded, size: 20),
                  tooltip: l10n.optSend,
                  color: colorScheme.primary,
                  onPressed: canSend ? widget.onSend : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
