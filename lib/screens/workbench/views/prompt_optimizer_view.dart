import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../state/app_state.dart';
import '../../../widgets/markdown_editor.dart';

class PromptOptimizerView extends StatelessWidget {
  final TextEditingController currentPromptCtrl;
  final TextEditingController refinedPromptCtrl;

  const PromptOptimizerView({
    super.key,
    required this.currentPromptCtrl,
    required this.refinedPromptCtrl,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final appState = Provider.of<AppState>(context);
    
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 600;
        
        if (isNarrow) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildInputSection(l10n, appState, true),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Icon(Icons.arrow_downward_rounded, color: Colors.grey),
                ),
                _buildOutputSection(l10n, appState, true),
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
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Center(child: Icon(Icons.arrow_forward_rounded, color: Colors.grey, size: 32)),
              ),
              Expanded(child: _buildOutputSection(l10n, appState, false)),
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
      expand: !isNarrow,
    );
  }

  Widget _buildOutputSection(AppLocalizations l10n, AppState appState, bool isNarrow) {
    return MarkdownEditor(
      controller: refinedPromptCtrl,
      label: l10n.optimizedPrompt,
      isMarkdown: appState.isMarkdownRefinerTarget,
      onMarkdownChanged: (v) => appState.setIsMarkdownRefinerTarget(v),
      maxLines: isNarrow ? 12 : 25,
      initiallyPreview: true,
      isRefined: true,
      expand: !isNarrow,
    );
  }
}
