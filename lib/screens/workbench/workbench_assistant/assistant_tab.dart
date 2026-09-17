part of '../workbench_screen.dart';

extension _AssistantTab on _WorkbenchScreenState {
  /// Tab 4's centre column: the chat view, gated on the session's flags and
  /// the queue task that is running its turn.
  Widget _buildAssistantChat() {
    return Consumer<WorkbenchUIState>(
      builder: (context, wui, _) {
        final session = wui.optimizerSession;
        // The chat view listens to the session itself; this host only
        // reads the two flags below. Rebuilding it for every notification
        // handed the view a new widget each time, past its own gating.
        return ListenableSelector<Object>(
          listenable: session,
          selector: () => (session.isRunning, session.usesKnowledgeBase),
          builder: (context) {
            // A Selector, not a `Provider.of(context)` up in the enclosing
            // build. Reading the queue there subscribed the *screen* to it,
            // so the 500ms progress tick of any unrelated image or video
            // task rebuilt the whole workbench — top bar, toolbar, chat
            // view and right panel — while this tab was open. The scan
            // still runs per notification; only a flip of the flag now
            // costs a rebuild, and only of this subtree.
            return Selector<TaskQueueService, String?>(
              // The task's *id*, not merely whether one exists: `10i`'s
              // 中断 has to name the task it is stopping, and a bool would
              // have had the abort handler re-scan the queue at the moment
              // it fires — after the state it was deciding from is gone.
              selector: (_, queue) => queue.queue
                  .cast<TaskItem?>()
                  .firstWhere(
                    (t) =>
                        t!.type == TaskType.promptRefine &&
                        t.parameters['sessionId'] == session.id &&
                        (t.status == TaskStatus.pending ||
                            t.status == TaskStatus.processing),
                    orElse: () => null,
                  )
                  ?.id,
              builder: (context, runningTaskId, _) {
                final isBusy = session.isRunning || runningTaskId != null;
                return _optIsLoadingData
                          ? const Center(child: CircularProgressIndicator())
                          : PromptOptimizerChatView(
                              inputCtrl: _optInputCtrl,
                              onSend: _handleOptimizerSend,
                              onRetry: _handleOptimizerRetry,
                              onApplyPrompt: _handleOptimizerApply,
                              onApplyKbEdit: (editId) => _handleKbEditApply(session, editId),
                              onRejectKbEdit: (editId) => _handleKbEditReject(session, editId),
                              onAnswerAskUser: _handleAskUserAnswer,
                              onDistill:
                                  session.usesKnowledgeBase ? _handleKbDistill : null,
                              onSaveFinalPrompt: _handleSaveFinalPrompt,
                              onOpenModelSettings: _handleOpenOptimizerModelSettings,
                              isBusy: isBusy,
                              // Only while there is a task to stop. A
                              // session whose `isRunning` outlived its
                              // task — the failure mode a crashed turn
                              // leaves behind — has nothing to cancel, and
                              // offering the button there would produce a
                              // control that does nothing when pressed.
                              onAbort: runningTaskId == null
                                  ? null
                                  : () => _handleOptimizerAbort(runningTaskId),
                            );
              },
            );
          },
        );
      },
    );
  }

  /// Tab 4's slot in the floating glass toolbar (`A3a 1a`).
  Widget _buildAssistantToolControls() {
    return Consumer<WorkbenchUIState>(
      builder: (context, wui, _) {
        final session = wui.optimizerSession;
        return ListenableSelector<Object>(
          listenable: session,
          // Steps and pending edits derive from the transcript.
          selector: () => (session.transcript, session.isRunning, session.refinedPrompt),
          builder: (context) => Selector<TaskQueueService, String?>(
            selector: (_, queue) => queue.queue
                .cast<TaskItem?>()
                .firstWhere(
                  (t) =>
                      t!.type == TaskType.promptRefine &&
                      t.parameters['sessionId'] == session.id &&
                      (t.status == TaskStatus.pending ||
                          t.status == TaskStatus.processing),
                  orElse: () => null,
                )
                ?.id,
            builder: (context, runningTaskId, _) {
              final isBusy = session.isRunning || runningTaskId != null;
              return PromptOptimizerToolbar(
                      onNewSession: () => wui.newOptimizerSession(),
                      onHistory: _showAssistantHistory,
                      onApply: () => _handleOptimizerApply(session.refinedPrompt ?? ''),
                      isRefining: isBusy,
                      runningSteps:
                          isBusy ? PromptOptimizerAgent.currentTurnSteps(session) : null,
                      canApply: session.refinedPrompt != null,
                      pendingKbEdits:
                          PromptOptimizerAgent.pendingKbEdits(session).length,
                      onWriteAllKbEdits: isBusy
                          ? null
                          : () => _handleKbEditApplyAll(session),
                      onDiscardAllKbEdits: isBusy
                          ? null
                          : () => _handleKbEditRejectAll(session),
                      modeLabel: switch (session.mode) {
                        AssistantMode.systemPrompt =>
                          AppLocalizations.of(context)!.optModeSystemPrompt,
                        AssistantMode.knowledgeBase =>
                          AppLocalizations.of(context)!.optModeKnowledge,
                        AssistantMode.knowledgeEdit =>
                          AppLocalizations.of(context)!.optModeKnowledgeEdit,
                      },
                      modeIcon: switch (session.mode) {
                        AssistantMode.systemPrompt => Icons.notes_outlined,
                        AssistantMode.knowledgeBase => Icons.menu_book_outlined,
                        AssistantMode.knowledgeEdit => Icons.edit_note_outlined,
                      },
                    );
            },
          ),
        );
      },
    );
  }

  /// Tab 4's right panel — see the note at its call site in `build`.
  Widget _buildAssistantConfigPanel(ScrollController? scrollController, AppState appState) {
    return Consumer<WorkbenchUIState>(
      builder: (context, wui, _) => ListenableSelector<Object>(
        listenable: wui.optimizerSession,
        // Only what the panel draws from the session. It notifies
        // several times a request for the usage readout alone, which
        // listens on its own below; rebuilding the whole panel for each
        // was ~1,100 widget builds (render_probe, assistant).
        selector: () => (
          wui.optimizerSession.transcript,
          wui.optimizerSession.history.length,
          _optRunningForSession(wui.optimizerSession),
        ),
        builder: (context) => OptimizerConfigPanel(
          scrollController: scrollController,
          selectedModelDbId: wui.optSelectedModelDbId,
          selectedSysPrompt: wui.optSelectedSysPrompt,
          sysPromptTemplateId: wui.optSysPromptTemplateId,
          mode: wui.assistantMode,
          kbStatus: _kbStatus,
          kbPath: _kbPath,
          running: _optRunningForSession(wui.optimizerSession),
          pendingKbEdits: PromptOptimizerAgent.pendingKbEdits(wui.optimizerSession),
          onWriteAllKbEdits: () => _handleKbEditApplyAll(wui.optimizerSession),
          onDiscardAllKbEdits: () => _handleKbEditRejectAll(wui.optimizerSession),
          writePolicy: _kbWritePolicy,
          onWritePolicyChanged: _handleWritePolicyChanged,
          onModeChanged: _handleAssistantModeChange,
          onScaffoldKb: _handleScaffoldKb,
          sysPrompts: _optSysPrompts,
          citedKnowledgeFiles: PromptOptimizerAgent.citedKnowledgeFiles(
            wui.optimizerSession,
          ),
          transcript: wui.optimizerSession.transcript,
          contextUsageListenable: wui.optimizerSession,
          contextUsageOf: () => PromptOptimizerAgent.measureContext(
            wui.optimizerSession,
            // Read from the picker rather than from the last turn: pick a
            // different model and the same conversation is measured against
            // the new window immediately, which is the question the user is
            // asking when they switch.
            contextWindowTokens: appState.allModels
                .cast<LLMModel?>()
                .firstWhere(
                  (m) => m?.id == wui.optSelectedModelDbId,
                  orElse: () => null,
                )
                ?.contextWindow,
          ),
          onModelChanged: (v) => wui.setOptimizerModel(v),
          onSysPromptChanged: (v) => wui.setOptimizerSysPrompt(v),
          onSysPromptTemplateChanged: (id, content) =>
              wui.setOptimizerSysPromptTemplate(id, content),
          onSaveTemplate: _handleSaveSysPromptTemplate,
        ),
      ),
    );
  }
}
