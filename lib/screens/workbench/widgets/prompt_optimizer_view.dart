import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/responsive.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/task_queue_service.dart';
import '../../../state/app_state.dart';
import '../../../widgets/markdown_editor.dart';

class PromptOptimizerView extends StatelessWidget {
  final MarkdownTextEditingController currentPromptCtrl;
  final MarkdownTextEditingController refinedPromptCtrl;

  const PromptOptimizerView({
    super.key,
    required this.currentPromptCtrl,
    required this.refinedPromptCtrl,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final appState = Provider.of<AppState>(context);
    final taskService = Provider.of<TaskQueueService>(context);
    final isRefining = taskService.queue.any(
      (t) => t.type == TaskType.promptRefine && t.status == TaskStatus.processing,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < Responsive.mobileBreakpoint;

        if (isNarrow) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Expanded(flex: 2, child: _buildInputSection(l10n, appState, true)),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: isRefining
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.arrow_downward_rounded, color: Colors.grey, size: 20),
                ),
                Expanded(flex: 3, child: _buildOutputSection(l10n, appState, true, isRefining)),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _buildInputSection(l10n, appState, false)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Center(
                  child: isRefining
                      ? const SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.arrow_forward_rounded, color: Colors.grey, size: 32),
                ),
              ),
              Expanded(child: _buildOutputSection(l10n, appState, false, isRefining)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInputSection(AppLocalizations l10n, AppState appState, bool isNarrow) {
    return MarkdownEditor(
      controller: currentPromptCtrl,
      label: l10n.roughPrompt,
      isMarkdown: appState.isMarkdownRefinerSource,
      onMarkdownChanged: (v) => appState.setIsMarkdownRefinerSource(v),
      maxLines: isNarrow ? 8 : 25,
      initiallyPreview: false,
      expand: true,
    );
  }

  Widget _buildOutputSection(AppLocalizations l10n, AppState appState, bool isNarrow, bool isRefining) {
    return Stack(
      children: [
        MarkdownEditor(
          controller: refinedPromptCtrl,
          label: l10n.optimizedPrompt,
          isMarkdown: appState.isMarkdownRefinerTarget,
          onMarkdownChanged: (v) => appState.setIsMarkdownRefinerTarget(v),
          maxLines: isNarrow ? 12 : 25,
          initiallyPreview: true,
          isRefined: true,
          expand: true,
        ),
        if (isRefining)
          const Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(minHeight: 2, backgroundColor: Colors.transparent),
          ),
      ],
    );
  }
}
