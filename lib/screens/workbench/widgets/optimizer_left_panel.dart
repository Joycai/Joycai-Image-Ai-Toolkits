import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/prompt_optimizer_agent.dart';
import '../../../state/workbench_ui_state.dart';
import 'knowledge_tree_panel.dart';
import 'optimizer_reference_panel.dart';

/// Which column the assistant shows on its left, which depends on the mode.
///
/// `A2 10h` swaps the reference-image strip for the knowledge tree in
/// library-edit mode. The swap lives in a widget of its own rather than in the
/// workbench's build so that the screen keeps handing the layout one stable
/// instance: a fresh widget there is rebuilt on every splitter-drag frame and
/// on every unrelated `AppState` notification, which is the note already
/// written above `rightPanelBuilder`.
class OptimizerLeftPanel extends StatelessWidget {
  /// The configured knowledge-base root, from the screen that validates it.
  final String? kbPath;

  const OptimizerLeftPanel({super.key, required this.kbPath});

  @override
  Widget build(BuildContext context) {
    // `select`, not `Consumer`: the mode changes about once a session while
    // this state object notifies on every reference image added, every picker
    // change and every optimizer transfer.
    final mode = context.select<WorkbenchUIState, AssistantMode>((s) => s.assistantMode);
    if (mode != AssistantMode.knowledgeEdit) return const OptimizerReferencePanel();

    // The pending list does have to be watched here — it drives the tree's
    // badges and its footer.
    return Consumer<WorkbenchUIState>(
      builder: (context, wui, _) => ListenableBuilder(
        listenable: wui.optimizerSession,
        builder: (context, _) => KnowledgeTreePanel(
          kbPath: kbPath,
          pendingKbEdits: PromptOptimizerAgent.pendingKbEdits(wui.optimizerSession),
        ),
      ),
    );
  }
}
