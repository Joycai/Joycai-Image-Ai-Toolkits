part of '../workbench_screen.dart';

extension _AssistantActions on _WorkbenchScreenState {
  /// The toolbar badge's text (`A3d 4a`): what the session works from, then
  /// which preset or which use. One place, because the toolbar is measured
  /// with this label before it is built with it.
  String _assistantBadgeLabel(AppLocalizations l10n, WorkbenchUIState wui) {
    switch (wui.assistantMode) {
      case AssistantMode.knowledgeBase:
        return l10n.optModeBadge(l10n.optModeKnowledge, l10n.optModeKnowledgeWrite);
      case AssistantMode.knowledgeEdit:
        return l10n.optModeBadge(l10n.optModeKnowledge, l10n.optModeKnowledgeEdit);
      case AssistantMode.systemPrompt:
        final id = wui.optSysPromptTemplateId;
        final preset = _optSysPrompts.cast<SystemPrompt?>().firstWhere(
              (p) => p?.id == id,
              orElse: () => null,
            );
        return l10n.optModeBadge(
          l10n.optModeSystemPrompt,
          preset?.title ?? l10n.optPresetBuiltinName,
        );
    }
  }

  /// Task preset ⇄ knowledge base is a different conversation, not a setting
  /// of this one: the histories cannot continue each other. So the switch
  /// starts a new session, and says where the old one went (`A3d 4d`).
  Future<void> _handleAssistantModeChange(AssistantMode next) async {
    final workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);
    final session = workbenchUIState.optimizerSession;
    if (session.mode == next) return;
    // The panel greys the switch during a turn; this is the gate that holds
    // if something else asks.
    if (_optRunningForSession(session)) return;
    if (session.transcript.isNotEmpty) {
      final l10n = AppLocalizations.of(context)!;
      final target = next == AssistantMode.systemPrompt
          ? l10n.optModeSystemPrompt
          : l10n.optModeKnowledge;
      final confirmed = await AppDialog.show<bool>(
        context,
        title: l10n.optModeSwitchTitle(target),
        content: Text(l10n.optModeSwitchBody),
        actions: [
          AppButton(
            label: l10n.cancel,
            variant: AppButtonVariant.text,
            onPressed: () => Navigator.pop(context, false),
          ),
          AppButton(label: l10n.optModeSwitchStart, onPressed: () => Navigator.pop(context, true)),
        ],
      );
      if (confirmed != true) return;
    }
    workbenchUIState.setAssistantMode(next);
  }

  /// Ensures a usable knowledge-base root, then initializes it with the starter
  /// files. Only ever acts on a folder that is not already a knowledge base —
  /// the button is disabled at [KbStatus.ok], and both the picker path below
  /// and [KnowledgeBaseStarter.scaffold] re-check independently.
  Future<void> _handleScaffoldKb() async {
    final l10n = AppLocalizations.of(context)!;
    final kb = KnowledgeBaseService();
    var stored = await kb.getRoot();

    // No folder yet, or the stored one is gone: ask where to put it rather than
    // silently recreating a directory the user may have deliberately moved.
    if (stored == null || !Directory(stored).existsSync()) {
      final picked = await FilePicker.getDirectoryPath();
      if (picked == null) return;
      await kb.setRoot(picked);
      stored = picked;
    }
    final root = stored;

    // The status that enabled the button describes the *previous* root. A
    // freshly picked folder may already be someone's knowledge base, so refuse
    // before touching it — with a real explanation rather than a raw error.
    if (KnowledgeBaseStarter.isInitialized(root)) {
      await _refreshKbStatus();
      if (!mounted) return;
      AppSnackBar.info(context, l10n.kbScaffoldAlreadyInit(KnowledgeBaseService.entryFileName));
      return;
    }

    if (!mounted) return;
    final confirmed = await AppDialog.show<bool>(
      context,
      content: Text(l10n.kbScaffoldConfirm(root)),
      actions: [
        AppButton(
          label: l10n.cancel,
          variant: AppButtonVariant.text,
          onPressed: () => Navigator.pop(context, false),
        ),
        AppButton(label: l10n.confirm, onPressed: () => Navigator.pop(context, true)),
      ],
    );
    if (confirmed != true) return;

    try {
      final result = await KnowledgeBaseStarter.scaffold(root);
      await _refreshKbStatus();
      if (!mounted) return;
      AppSnackBar.success(context, l10n.kbScaffoldDone(result.created.length));
    } catch (e) {
      if (!mounted) return;
      AppSnackBar.error(context, l10n.kbScaffoldFailed('$e'));
    }
  }

  Future<void> _handleKbEditApply(PromptOptimizerSession session, String editId) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      await PromptOptimizerAgent.applyStagedKbEdit(session: session, editId: editId);
      // Writing README.md can flip missingEntry -> ok, which re-enables the
      // knowledge modes in the config panel.
      await _refreshKbStatus();
    } catch (e) {
      if (!mounted) return;
      AppSnackBar.error(context, l10n.kbEditFailed('$e'));
    }
  }

  void _handleKbEditReject(PromptOptimizerSession session, String editId) {
    PromptOptimizerAgent.rejectStagedKbEdit(session: session, editId: editId);
  }

  /// `10h`'s 全部写入 / 全部丢弃.
  ///
  /// The ids are collected before anything is answered, because resolving one
  /// edit rebuilds the transcript and iterating the live list while it changes
  /// underneath would skip half of them. Writes go one at a time and in order,
  /// so a failure part-way leaves the edits before it on disk and the rest
  /// still pending — which is what the cards will then show.
  Future<void> _handleKbEditApplyAll(PromptOptimizerSession session) async {
    final ids = [
      for (final e in PromptOptimizerAgent.pendingKbEdits(session)) e.editId!,
    ];
    for (final id in ids) {
      if (!mounted) return;
      await _handleKbEditApply(session, id);
    }
  }

  void _handleKbEditRejectAll(PromptOptimizerSession session) {
    for (final e in PromptOptimizerAgent.pendingKbEdits(session).toList()) {
      PromptOptimizerAgent.rejectStagedKbEdit(session: session, editId: e.editId!);
    }
  }

  void _handleOptimizerApply(String prompt) {
    if (_appState == null || prompt.isEmpty) return;
    // Provenance hand-off #1: remember which version this text is, so a
    // generation run with it unchanged can be tagged. The version is looked
    // up by text rather than taken as "the latest" — every prompt card has
    // its own apply button, so the user can apply v2 after v3 exists.
    final session =
        Provider.of<WorkbenchUIState>(context, listen: false).optimizerSession;
    final version =
        PromptProvenance.versionForPromptText(session.transcript, prompt);
    _appState!.appliedAssistantPrompt = version == null
        ? null
        : AppliedAssistantPrompt(
            sessionId: session.id, version: version, text: prompt);
    _appState!.updateWorkbenchConfig(prompt: prompt);
    _appState!.setWorkbenchTab(0);
    AppSnackBar.info(context, AppLocalizations.of(context)!.promptApplied);
  }
}
