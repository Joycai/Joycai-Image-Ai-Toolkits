part of '../workbench_screen.dart';

extension _AssistantTurns on _WorkbenchScreenState {
  /// Runs a turn some other surface already staged into the session — same
  /// guards as [_handleOptimizerSend], minus the composer text.
  Future<void> _runRequestedAssistantTurn(WorkbenchUIState workbenchUIState) async {
    final l10n = AppLocalizations.of(context)!;
    final session = workbenchUIState.optimizerSession;

    // A turn already in flight owns the session; starting a second one would
    // corrupt its history. Same guard as _handleAskUserAnswer / _handleRetry.
    if (session.isRunning) return;
    if (workbenchUIState.optSelectedModelDbId == null || _appState == null) {
      AppSnackBar.warning(context, l10n.noModelsConfigured);
      return;
    }
    if (session.usesKnowledgeBase) {
      await _refreshKbStatus();
      if (_kbStatus != KbStatus.ok) {
        if (mounted) {
          AppSnackBar.warning(context, AppLocalizations.of(context)!.optKbNotConfigured);
        }
        return;
      }
    }
    await _enqueueAssistantTurn(workbenchUIState, session);
  }

  /// Stages the distill request (`20d`) and runs it as a normal agent turn.
  Future<void> _handleKbDistill() async {
    final l10n = AppLocalizations.of(context)!;
    final workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);
    final session = workbenchUIState.optimizerSession;

    if (workbenchUIState.optSelectedModelDbId == null || _appState == null) {
      AppSnackBar.warning(context, l10n.noModelsConfigured);
      return;
    }
    await _refreshKbStatus();
    if (_kbStatus != KbStatus.ok) {
      if (mounted) {
        AppSnackBar.warning(context, AppLocalizations.of(context)!.optKbNotConfigured);
      }
      return;
    }

    final result = await workbenchUIState.requestKbDistill();
    if (!mounted) return;
    switch (result) {
      case KbDistillStageResult.staged:
        await _enqueueAssistantTurn(workbenchUIState, session);
      case KbDistillStageResult.nothingToDistill:
        AppSnackBar.warning(context, l10n.optDistillDisabledTooltip);
      case KbDistillStageResult.alreadyPending:
        AppSnackBar.warning(context, l10n.optDistillAlreadyPending);
      case KbDistillStageResult.busy:
      case KbDistillStageResult.notKnowledgeSession:
        break; // The chip is hidden/disabled in these states; nothing to say.
    }
  }

  /// Opens the prompt-library save dialog prefilled with the final staged
  /// prompt (`20d`·d). The dialog owns persistence, like every prompt edit.
  Future<void> _handleSaveFinalPrompt() async {
    final l10n = AppLocalizations.of(context)!;
    final workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);
    final session = workbenchUIState.optimizerSession;
    final refined = session.refinedPrompt;
    final appState = _appState;
    if (refined == null || appState == null) return;

    final prompts = await appState.getPrompts();
    final tags = await appState.getPromptTags();
    if (!mounted) return;
    await showPromptEditDialog(
      context,
      l10n,
      userPrompts: prompts,
      tags: tags,
      initialTitle: session.title,
      initialContent: refined,
    );
  }

  /// Whether a turn of [session] is queued or running.
  ///
  /// Read straight off the queue rather than through the `Selector` the centre
  /// column uses — the right panel is built from a different callback, outside
  /// that builder's scope — and without subscribing to it, because the panel
  /// is rebuilt by the session's own notifications and subscribing here would
  /// hand it every unrelated task's 500ms progress tick. The cost is that the
  /// brief queued-but-not-yet-started window is not repainted for: the panel
  /// catches up when `isRunning` flips, which is when it has something new to
  /// say anyway.
  bool _optRunningForSession(PromptOptimizerSession session) {
    if (session.isRunning) return true;
    final queue = Provider.of<TaskQueueService>(context, listen: false).queue;
    return queue.any((t) =>
        t.type == TaskType.promptRefine &&
        t.parameters['sessionId'] == session.id &&
        (t.status == TaskStatus.pending || t.status == TaskStatus.processing));
  }

  /// Opens a model's editor — the max-output setting lives there — from a
  /// reply the output limit cut. [modelDbId] is the row the reply came from;
  /// null (an entry that does not know) falls back to the picker. The same
  /// dialog the models page opens; a model deleted since is a no-op.
  void _handleOpenOptimizerModelSettings(int? modelDbId) {
    final appState = _appState;
    if (appState == null) return;
    final l10n = AppLocalizations.of(context)!;
    final workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);
    final dbId = modelDbId ?? workbenchUIState.optSelectedModelDbId;
    final model = appState.allModels.cast<LLMModel?>().firstWhere((m) => m?.id == dbId, orElse: () => null);
    if (model == null) return;
    showDialog(
      context: context,
      useSafeArea: false,
      builder: (context) => ModelEditDialog(l10n: l10n, appState: appState, model: model),
    );
  }

  /// Sends one user turn of the optimizer conversation: the message is added
  /// to the session immediately (so it shows in the chat), then a queue task
  Future<void> _handleOptimizerSend() async {
    final l10n = AppLocalizations.of(context)!;
    final workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);
    final text = _optInputCtrl.text.trim();
    if (text.isEmpty) return;

    if (workbenchUIState.optSelectedModelDbId == null || _appState == null) {
      AppSnackBar.warning(context, l10n.noModelsConfigured);
      return;
    }

    final session = workbenchUIState.optimizerSession;

    // Knowledge modes require a valid knowledge base before sending.
    if (session.usesKnowledgeBase) {
      await _refreshKbStatus();
      if (_kbStatus != KbStatus.ok) {
        if (mounted) {
          AppSnackBar.warning(context, AppLocalizations.of(context)!.optKbNotConfigured);
        }
        return;
      }
    }

    // Free text while a question card is pending answers it: pair the
    // dangling ask_user call first so the history the turn sends is valid,
    // then let the reply flow in as a normal user turn.
    final pendingAsk = session.pendingAskUser;
    if (pendingAsk != null) {
      PromptOptimizerAgent.resolvePendingAskUserAsFreeText(
        session: session,
        callId: pendingAsk.callId,
      );
    }

    session.addUserTurn(text);
    _optInputCtrl.clear();

    await _enqueueAssistantTurn(workbenchUIState, session);
  }

  /// Sends the structured answers of an ask_user card and resumes the agent.
  Future<void> _handleAskUserAnswer(String callId, List<AskUserAnswer> answers) async {
    final l10n = AppLocalizations.of(context)!;
    final workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);
    final session = workbenchUIState.optimizerSession;
    if (session.isRunning) return;

    if (workbenchUIState.optSelectedModelDbId == null || _appState == null) {
      AppSnackBar.warning(context, l10n.noModelsConfigured);
      return;
    }
    if (session.usesKnowledgeBase) {
      await _refreshKbStatus();
      if (_kbStatus != KbStatus.ok) {
        if (mounted) {
          AppSnackBar.warning(context, AppLocalizations.of(context)!.optKbNotConfigured);
        }
        return;
      }
    }

    PromptOptimizerAgent.answerAskUser(session: session, callId: callId, answers: answers);
    await _enqueueAssistantTurn(workbenchUIState, session);
  }

  /// Re-runs the agent turn after a failure. The pending user message and any
  /// completed tool results are still in the session history, so nothing has
  /// to be typed or re-read again.
  Future<void> _handleOptimizerRetry() async {
    final l10n = AppLocalizations.of(context)!;
    final workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);
    final session = workbenchUIState.optimizerSession;
    if (session.isRunning || session.history.isEmpty) return;

    if (workbenchUIState.optSelectedModelDbId == null || _appState == null) {
      AppSnackBar.warning(context, l10n.noModelsConfigured);
      return;
    }
    if (session.usesKnowledgeBase) {
      await _refreshKbStatus();
      if (_kbStatus != KbStatus.ok) {
        if (mounted) {
          AppSnackBar.warning(context, AppLocalizations.of(context)!.optKbNotConfigured);
        }
        return;
      }
    }

    await _enqueueAssistantTurn(workbenchUIState, session);
  }

  /// Stops the turn in flight, from `10i`'s 中断 button or the Esc key.
  ///
  /// Cancelling the *task* rather than reaching into the session: the queue
  /// owns the run, and it is what threads the cancellation flag the agent's
  /// tool loop already polls between batches. Nothing is rolled back — the
  /// steps that did complete stay in the transcript, which is what makes a
  /// stopped turn something the user can read rather than an erased one.
  Future<void> _handleOptimizerAbort(String taskId) async {
    final taskService = Provider.of<TaskQueueService>(context, listen: false);
    await taskService.cancelTask(taskId);
  }

  Future<void> _enqueueAssistantTurn(
    WorkbenchUIState workbenchUIState,
    PromptOptimizerSession session,
  ) async {
    // Read here rather than when the session was created: the switches live in
    // settings, the session can outlive several changes to them, and the
    // question the policy answers is about the turn now going out.
    session.writePolicy = _kbWritePolicy;
    try {
      final taskService = Provider.of<TaskQueueService>(context, listen: false);
      await taskService.addTask(
        workbenchUIState.optimizerReferenceImages.map((f) => f.path).toList(),
        workbenchUIState.optSelectedModelDbId!,
        {
          'sessionId': session.id,
          'mode': session.mode.name,
          if (session.mode == AssistantMode.systemPrompt)
            'systemPrompt': workbenchUIState.optSelectedSysPrompt,
        },
        type: TaskType.promptRefine,
        useStream: false,
        id: const Uuid().v4(),
      );
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        AppSnackBar.error(context, l10n.refineFailed(e.toString()));
      }
    }
  }
}
