part of '../workbench_screen.dart';

extension _AssistantHistorySheet on _WorkbenchScreenState {
  /// Bottom sheet listing persisted assistant conversations with restore /
  /// rename / delete actions.
  Future<void> _showAssistantHistory() async {
    final l10n = AppLocalizations.of(context)!;
    final workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);
    final sessions = await workbenchUIState.listAssistantSessions();
    if (!mounted) return;
    if (sessions.isEmpty) {
      AppSnackBar.info(context, l10n.optNoHistory);
      return;
    }
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: sessions.length,
            itemBuilder: (itemContext, index) {
              final meta = sessions[index];
              final isCurrent = meta.id == workbenchUIState.optimizerSession.id;
              final colorScheme = Theme.of(itemContext).colorScheme;
              return ListTile(
                dense: true,
                selected: isCurrent,
                leading: Icon(
                  switch (meta.mode) {
                    AssistantMode.knowledgeBase => Icons.menu_book_outlined,
                    AssistantMode.knowledgeEdit => Icons.edit_note_outlined,
                    AssistantMode.systemPrompt => Icons.tune,
                  },
                  size: 18,
                ),
                title: Text(
                  (meta.title == null || meta.title!.isEmpty) ? meta.id : meta.title!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  meta.updatedAt.toLocal().toString().substring(0, 16),
                  style: Theme.of(context).textTheme.labelMedium?.metricsOnly,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      tooltip: l10n.rename,
                      onPressed: () async {
                        final ctrl = TextEditingController(text: meta.title ?? '');
                        final newTitle = await AppDialog.show<String>(
                          sheetContext,
                          title: l10n.rename,
                          content: TextField(
                            controller: ctrl,
                            autofocus: true,
                            style: Theme.of(sheetContext).textTheme.bodyMedium,
                            textAlignVertical: TextAlignVertical.center,
                            decoration: InputDecoration(
                              isDense: true,
                              constraints: const BoxConstraints.tightFor(height: AppSize.control),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: AppSpace.s10,
                                vertical: pinnedFieldInset(
                                  sheetContext,
                                  Theme.of(sheetContext).textTheme.bodyMedium,
                                  AppSize.control,
                                ),
                              ),
                            ),
                          ),
                          actions: [
                            AppButton(
                              label: l10n.cancel,
                              variant: AppButtonVariant.text,
                              onPressed: () => Navigator.pop(sheetContext),
                            ),
                            AppButton(
                              label: l10n.confirm,
                              onPressed: () => Navigator.pop(sheetContext, ctrl.text.trim()),
                            ),
                          ],
                        );
                        if (newTitle != null && newTitle.isNotEmpty) {
                          await workbenchUIState.renameAssistantSession(meta.id, newTitle);
                          final refreshed = await workbenchUIState.listAssistantSessions();
                          sessions..clear()..addAll(refreshed);
                          setSheetState(() {});
                        }
                      },
                    ),
                    IconButton(
                      icon: Icon(Icons.delete_outline, size: 18, color: colorScheme.error),
                      tooltip: l10n.delete,
                      onPressed: () async {
                        final confirmed = await AppDialog.show<bool>(
                          sheetContext,
                          content: Text(l10n.optDeleteSessionConfirm),
                          actions: [
                            AppButton(
                              label: l10n.cancel,
                              variant: AppButtonVariant.text,
                              onPressed: () => Navigator.pop(sheetContext, false),
                            ),
                            AppButton(
                              label: l10n.delete,
                              onPressed: () => Navigator.pop(sheetContext, true),
                            ),
                          ],
                        );
                        if (confirmed == true) {
                          await workbenchUIState.deleteAssistantSession(meta.id);
                          sessions.removeAt(index);
                          setSheetState(() {});
                        }
                      },
                    ),
                  ],
                ),
                onTap: isCurrent
                    ? null
                    : () async {
                        Navigator.pop(sheetContext);
                        await workbenchUIState.restoreAssistantSession(meta.id);
                      },
              );
            },
          ),
        ),
      ),
    );
  }
}
