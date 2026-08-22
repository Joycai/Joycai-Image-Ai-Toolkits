import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../models/prompt.dart';
import '../../services/ai_rename_agent.dart';
import '../../services/database_service.dart';
import '../../services/task_queue_service.dart';
import '../../state/app_state.dart';
import '../../state/file_browser_state.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/chat_model_selector.dart';

class AiRenameDialog extends StatefulWidget {
  const AiRenameDialog({super.key});

  @override
  State<AiRenameDialog> createState() => _AiRenameDialogState();
}

class _AiRenameDialogState extends State<AiRenameDialog> {
  final TextEditingController _instructionController = TextEditingController();
  final DatabaseService _db = DatabaseService();
  bool _isProcessing = false;
  String? _batchProgress; // "current/total" while a multi-batch run is going
  int? _selectedModelDbId;
  SystemPrompt? _selectedSystemPrompt;
  List<Map<String, String>> _proposedRenames = [];
  Map<String, String> _conflicts = {};
  StreamSubscription? _taskSubscription;
  String? _currentTaskId;

  @override
  void initState() {
    super.initState();
    _loadLastSettings();
    
    // Setup task subscription
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final taskService = Provider.of<TaskQueueService>(context, listen: false);
      _taskSubscription = taskService.eventStream.listen((event) {
        if (_currentTaskId == null || event.taskId != _currentTaskId) return;

        if (event.type == TaskEventType.statusChanged) {
          if (event.data == TaskStatus.completed || event.data == TaskStatus.failed || event.data == TaskStatus.cancelled) {
            if (mounted) setState(() => _isProcessing = false);
          }
        }
      });
    });
  }

  @override
  void dispose() {
    _taskSubscription?.cancel();
    _instructionController.dispose();
    super.dispose();
  }

  Future<void> _loadLastSettings() async {
    final appState = Provider.of<AppState>(context, listen: false);
    final lastModelId = await appState.getSetting('last_ai_rename_model_id');
    final lastSystemPromptIdStr = await appState.getSetting('last_ai_rename_system_prompt_id');
    final lastInstructions = await appState.getSetting('last_ai_rename_instructions');
    
    final templates = await _db.getSystemPrompts(type: 'rename');
    SystemPrompt? initialSystemPrompt;
    
    if (lastSystemPromptIdStr != null) {
      final id = int.tryParse(lastSystemPromptIdStr);
      initialSystemPrompt = templates.cast<SystemPrompt?>().firstWhere((e) => e?.id == id, orElse: () => null);
    }
    
    // Fallback to first template if none selected or found
    initialSystemPrompt ??= templates.isNotEmpty ? templates.first : null;

    if (mounted) {
      setState(() {
        _selectedModelDbId = int.tryParse(lastModelId ?? '') ?? int.tryParse(appState.lastSelectedModelId ?? '');
        _selectedSystemPrompt = initialSystemPrompt;
        if (lastInstructions != null) {
          _instructionController.text = lastInstructions;
        }
      });
    }
  }

  Future<void> _showTemplatePicker() async {
    final l10n = AppLocalizations.of(context)!;
    
    final List<SystemPrompt> templates = await _db.getSystemPrompts(type: 'rename');
    
    if (!mounted) return;

    final SystemPrompt? selected = await AppDialog.show<SystemPrompt>(
      context,
      title: l10n.selectRenameTemplate,
      maxWidth: 420,
      maxHeight: MediaQuery.sizeOf(context).height * 0.6,
      content: templates.isEmpty
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text(l10n.noPromptsSaved)),
          )
        : ListView.builder(
            shrinkWrap: true,
            itemCount: templates.length,
            itemBuilder: (context, index) {
              final t = templates[index];
              return ListTile(
                title: Text(t.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                // ListTile's subtitle slot is `onSurfaceVariant`; the type slot
                // carries `onSurface`, so the muted tone is restated here.
                subtitle: Text(
                  t.content,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                onTap: () => Navigator.pop(context, t),
              );
            },
          ),
      actions: [
        AppButton(
          label: l10n.cancel,
          variant: AppButtonVariant.text,
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );

    if (selected != null) {
      setState(() {
        _selectedSystemPrompt = selected;
      });
    }
  }

  Future<void> _generateSuggestions() async {
    final appState = Provider.of<AppState>(context, listen: false);
    final fileBrowserState = appState.fileBrowserState;
    final selectedFiles = fileBrowserState.selectedFiles.toList();
    final l10n = AppLocalizations.of(context)!;

    if (_selectedModelDbId == null) {
      AppSnackBar.warning(
        context,
        l10n.noModelsConfigured,
        action: AppSnackBarAction(
          label: l10n.settings,
          onPressed: () {
            Navigator.pop(context); // Close dialog
            appState.navigateToScreen(6); // Settings screen index
          },
        ),
      );
      return;
    }

    if (_selectedSystemPrompt == null) {
      AppSnackBar.warning(context, l10n.selectTemplateFirst);
      return;
    }

    // Save current settings as last used
    final db = DatabaseService();
    db.saveSetting('last_ai_rename_model_id', _selectedModelDbId.toString());
    db.saveSetting('last_ai_rename_system_prompt_id', _selectedSystemPrompt?.id?.toString() ?? '');
    db.saveSetting('last_ai_rename_instructions', _instructionController.text);

    setState(() {
      _isProcessing = true;
      _batchProgress = null;
      _proposedRenames = [];
      _conflicts = {};
    });

    try {
      // Prepare the files list for the agent's list_files tool.
      final List<Map<String, String>> filesData = selectedFiles.map((f) => {
        'original_name': f.name,
        'path': f.path,
        'category': f.category.name,
      }).toList();

      // Tool-use agent loop: the model reads files via list_files and stages
      // renames via rename_file (dry-run — nothing touches disk here).
      final proposals = await AiRenameAgent.collectProposals(
        modelIdentifier: _selectedModelDbId,
        filesData: filesData,
        systemPrompt: _selectedSystemPrompt!.content,
        instructions: _instructionController.text.trim(),
        onBatchProgress: (current, total) {
          if (mounted && total > 1) {
            setState(() => _batchProgress = '$current/$total');
          }
        },
        isCancelled: () => !mounted,
      );

      final List<Map<String, String>> proposed = proposals.map((prop) => {
        'path': prop.path,
        'old_name': prop.oldName,
        'new_name': prop.newName,
      }).toList();

      await _detectConflicts(proposed);

      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _proposedRenames = proposed;
              _isProcessing = false;
            });
          }
        });
      }
    } catch (e) {
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() => _isProcessing = false);
            AppSnackBar.error(context, "Error: $e");
          }
        });
      }
    }
  }

  Future<void> _detectConflicts(List<Map<String, String>> proposed) async {
    final Map<String, String> conflicts = {};
    final Set<String> targetNames = {};
    
    for (var item in proposed) {
      final newName = item['new_name']!;
      final oldPath = item['path']!;
      final dir = p.dirname(oldPath);
      final newPath = p.join(dir, newName);

      // Conflict 1: Multiple files target the same name.
      // Values are stable keys, mapped to localized text at build time.
      if (targetNames.contains(newPath)) {
        conflicts[oldPath] = 'duplicate';
      }
      targetNames.add(newPath);

      // Conflict 2: Target name already exists on disk and is not one of our source files
      if (await File(newPath).exists() && !proposed.any((p) => p['path'] == newPath)) {
        conflicts[oldPath] = 'exists';
      }
    }
    _conflicts = conflicts;
  }

  Future<void> _applyRenames() async {
    if (_conflicts.isNotEmpty) return;

    final l10n = AppLocalizations.of(context)!;
    final appState = Provider.of<AppState>(context, listen: false);
    
    setState(() => _isProcessing = true);
    try {
      final taskService = Provider.of<TaskQueueService>(context, listen: false);
      final taskId = const Uuid().v4();

      setState(() {
        _currentTaskId = taskId;
        _isProcessing = true; // Ensure UI reflects processing immediately
      });

      // Submit the user-confirmed proposals — the executor applies exactly
      // what was previewed, without another LLM round-trip.
      await taskService.addTask(
        appState.fileBrowserState.selectedFiles.map((f) => f.path).toList(),
        _selectedModelDbId,
        {
          'proposals': _proposedRenames,
        },
        type: TaskType.aiRename,
        useStream: false,
        id: taskId,
      );
      
      if (mounted) {
        Navigator.pop(context);
        AppSnackBar.info(context, l10n.taskSubmitted);
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.error(context, "Failed to start task: $e");
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // Watched separately: AppState stopped forwarding its sub-states' changes,
    // so the selection count would otherwise freeze at whatever it was when the
    // dialog opened.
    final fileCount = context.watch<FileBrowserState>().selectedFiles.length;

    final chatModels = appState.chatModels;
    // Safety check: ensure the selected PK actually exists in the current list of chat models
    final effectiveModelDbId = chatModels.any((m) => m.id == _selectedModelDbId) ? _selectedModelDbId : null;

    return AppDialog(
      icon: Icons.auto_fix_high,
      title: l10n.aiBatchRename,
      subtitle: l10n.imagesSelected(fileCount),
      maxWidth: 640,
      maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ChatModelSelector(
            selectedModelId: effectiveModelDbId,
            label: l10n.model,
            onChanged: (v) => setState(() => _selectedModelDbId = v),
          ),
          const SizedBox(height: 16),

          // System template: the whole card opens the picker.
          Text(l10n.rulesInstructions, style: textTheme.titleSmall),
          const SizedBox(height: 8),
          Material(
            color: colorScheme.surfaceContainerHighest.withAlpha(80),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _showTemplatePicker,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.psychology_outlined, size: 22, color: colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedSystemPrompt?.title ?? l10n.noTemplateSelected,
                            style: textTheme.titleSmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (_selectedSystemPrompt != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              _selectedSystemPrompt!.content,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.labelMedium?.copyWith(color: colorScheme.outline),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.unfold_more, size: 18, color: colorScheme.outline),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          TextField(
            controller: _instructionController,
            minLines: 2,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: l10n.additionalInstructions,
              hintText: l10n.aiRenameInstructionsHint,
              alignLabelWithHint: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              fillColor: colorScheme.surface,
              filled: true,
            ),
          ),
          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            child: AppButton(
              label: l10n.generateSuggestions,
              icon: Icons.bolt,
              loading: _isProcessing,
              onPressed: _generateSuggestions,
            ),
          ),
          const SizedBox(height: 20),

          _buildPreviewSection(colorScheme, l10n),
        ],
      ),
      actions: [
        AppButton(
          label: l10n.cancel,
          variant: AppButtonVariant.text,
          onPressed: () => Navigator.pop(context),
        ),
        AppButton(
          label: l10n.applyRenames,
          onPressed: (_proposedRenames.isEmpty || _conflicts.isNotEmpty || _isProcessing) ? null : _applyRenames,
        ),
      ],
    );
  }

  Widget _buildPreviewSection(ColorScheme colorScheme, AppLocalizations l10n) {
    final textTheme = Theme.of(context).textTheme;

    // Waiting on the agent loop.
    if (_isProcessing && _proposedRenames.isEmpty) {
      return _buildPreviewPlaceholder(
        colorScheme,
        children: [
          const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
          const SizedBox(height: 12),
          Text(
            _batchProgress == null
                ? l10n.generatingSuggestions
                : '${l10n.generatingSuggestions} ($_batchProgress)',
            style: textTheme.bodySmall?.copyWith(color: colorScheme.outline),
          ),
        ],
      );
    }

    if (_proposedRenames.isEmpty) {
      return _buildPreviewPlaceholder(
        colorScheme,
        children: [
          Icon(Icons.drive_file_rename_outline, size: 32, color: colorScheme.outlineVariant),
          const SizedBox(height: 8),
          Text(l10n.noSuggestions, style: textTheme.bodySmall?.copyWith(color: colorScheme.outline)),
        ],
      );
    }

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: colorScheme.surfaceContainerHighest.withAlpha(80),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${l10n.renamePreviewTitle} (${_proposedRenames.length})',
                    style: textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_conflicts.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline, size: 13, color: colorScheme.onErrorContainer),
                        const SizedBox(width: 4),
                        Text(
                          l10n.conflictsFound(_conflicts.length),
                          style: textTheme.labelMedium?.copyWith(color: colorScheme.onErrorContainer),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          for (int i = 0; i < _proposedRenames.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 48),
            _buildPreviewItem(i, colorScheme, l10n),
          ],
        ],
      ),
    );
  }

  Widget _buildPreviewPlaceholder(ColorScheme colorScheme, {required List<Widget> children}) {
    return Container(
      width: double.infinity,
      height: 130,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withAlpha(50),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: children),
    );
  }

  Widget _buildPreviewItem(int index, ColorScheme colorScheme, AppLocalizations l10n) {
    final textTheme = Theme.of(context).textTheme;
    final item = _proposedRenames[index];
    final conflictKey = _conflicts[item['path']];
    final hasConflict = conflictKey != null;
    final conflictText = switch (conflictKey) {
      'duplicate' => l10n.conflictDuplicateTarget,
      'exists' => l10n.fileAlreadyExists,
      _ => conflictKey,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text('${index + 1}',
                  style: textTheme.labelMedium?.mono.copyWith(color: colorScheme.outline)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Both names in mono, as `12f` draws them. This list exists to
                // be read down the left edge — old name above, new name below,
                // five pairs at a time — and a proportional face puts the two
                // versions of the same stem at different widths, which is the
                // one comparison the dialog is for.
                Text(
                  item['old_name']!,
                  style: textTheme.labelMedium?.mono.copyWith(color: colorScheme.outline),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(
                      Icons.subdirectory_arrow_right,
                      size: 14,
                      color: hasConflict ? colorScheme.error : colorScheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        item['new_name']!,
                        style: textTheme.titleSmall?.mono.copyWith(
                          color: hasConflict ? colorScheme.error : colorScheme.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (hasConflict)
                  Padding(
                    padding: const EdgeInsets.only(left: 18, top: 3),
                    child: Text(
                      conflictText!,
                      style: textTheme.labelMedium?.copyWith(color: colorScheme.error),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: hasConflict
                ? Icon(Icons.error_outline, size: 16, color: colorScheme.error)
                : const Icon(Icons.check_circle_outline, size: 16, color: Colors.green),
          ),
        ],
      ),
    );
  }
}
