import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:provider/provider.dart';

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
  final void Function(String prompt) onApplyPrompt;
  final bool isBusy;

  const PromptOptimizerChatView({
    super.key,
    required this.inputCtrl,
    required this.onSend,
    required this.onApplyPrompt,
    required this.isBusy,
  });

  @override
  State<PromptOptimizerChatView> createState() => _PromptOptimizerChatViewState();
}

class _PromptOptimizerChatViewState extends State<PromptOptimizerChatView> {
  final ScrollController _scrollCtrl = ScrollController();
  PromptOptimizerSession? _session;
  int _lastTranscriptLength = 0;

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
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 780),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildEntry(entry, l10n, colorScheme),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEntry(OptimizerChatEntry entry, AppLocalizations l10n, ColorScheme colorScheme) {
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
          child: Container(
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
        );
    }
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
                  style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
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
