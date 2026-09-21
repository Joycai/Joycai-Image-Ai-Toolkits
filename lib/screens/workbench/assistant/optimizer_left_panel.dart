import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/assistant/prompt_optimizer_agent.dart';
import '../../../state/workbench_ui_state.dart';
import '../../../widgets/ui/app_segmented_control.dart';
import '../../../widgets/ui/listenable_selector.dart';
import 'knowledge_tree_panel.dart';
import 'optimizer_reference_panel.dart';

/// Which column the assistant shows on its left, which depends on the mode.
///
/// `A2 10h` puts the knowledge tree here in maintenance mode. `A3d 4e` keeps
/// the reference images reachable beside it, behind a two-segment switch: they
/// are still sent with every message in that mode, and a column that hid them
/// left the user unable to see — or remove — what the assistant was given.
/// Every other mode shows the reference images alone. The choice lives in a
/// widget of its own rather than in the workbench's build so that the screen
/// keeps handing the layout one stable instance: a fresh widget there is rebuilt on every splitter-drag frame and
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

    return _MaintenanceLeftPanel(kbPath: kbPath);
  }
}

/// The maintenance column: documents or reference images, documents first.
class _MaintenanceLeftPanel extends StatefulWidget {
  const _MaintenanceLeftPanel({required this.kbPath});

  final String? kbPath;

  @override
  State<_MaintenanceLeftPanel> createState() => _MaintenanceLeftPanelState();
}

class _MaintenanceLeftPanelState extends State<_MaintenanceLeftPanel> {
  bool _showReferences = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final referenceCount = context.select<WorkbenchUIState, int>(
      (s) => s.optimizerReferenceImages.length,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.s10,
            AppSpace.s10,
            AppSpace.s10,
            0,
          ),
          child: AppSegmentedControl<bool>(
            segments: [
              // No count on the documents: the tree's own caption carries it,
              // and it is the tree that knows.
              AppSegment(value: false, label: l10n.optLeftDocs),
              AppSegment(value: true, label: l10n.optLeftRefs(referenceCount)),
            ],
            value: _showReferences,
            onChanged: (v) => setState(() => _showReferences = v),
            expand: true,
            compact: true,
            style: AppSegmentStyle.raised,
          ),
        ),
        Expanded(
          // The tree is kept alive behind the references: it holds which
          // folders are open and what was searched for, and a look at the
          // images should not cost it that. The references are built only
          // while shown — their panel follows every session notification,
          // several a request, which an offstage copy would pay for unseen
          // (`rebuild_scope_test`).
          child: Stack(
            fit: StackFit.expand,
            children: [
              Offstage(
                offstage: _showReferences,
                // Offstage stops paint and hit-testing, not focus: without
                // this the hidden search box keeps taking the keystrokes.
                child: ExcludeFocus(
                  excluding: _showReferences,
                  child:
                      // The pending list does have to be watched here — it
                      // drives the tree's badges and its footer.
                      Consumer<WorkbenchUIState>(
                        builder: (context, wui, _) => ListenableSelector<Object>(
                          listenable: wui.optimizerSession,
                          // The pending list is derived from the transcript, which
                          // the session replaces on every change; nothing else it
                          // notifies for shows here.
                          selector: () => wui.optimizerSession.transcript,
                          builder: (context) => KnowledgeTreePanel(
                            kbPath: widget.kbPath,
                            pendingKbEdits: PromptOptimizerAgent.pendingKbEdits(
                              wui.optimizerSession,
                            ),
                          ),
                        ),
                      ),
                ),
              ),
              if (_showReferences) const OptimizerReferencePanel(),
            ],
          ),
        ),
      ],
    );
  }
}
