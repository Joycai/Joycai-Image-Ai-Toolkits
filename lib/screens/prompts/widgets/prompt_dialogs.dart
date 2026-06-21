import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/prompt.dart';
import '../../../models/tag.dart';
import '../../../state/app_state.dart';
import '../../../widgets/color_picker_widget.dart';
import '../../../widgets/markdown_editor.dart';

/// Dialogs for the Prompt Library screen.
///
/// Each function owns its own UI and persistence (via [AppState]) and returns
/// a [Future] that resolves to `true` when the underlying data changed, so the
/// caller can reload its lists. This keeps [PromptsScreen] free of dialog markup
/// and database writes.

/// Create / edit a user prompt. Returns `true` if saved.
Future<bool> showPromptEditDialog(
  BuildContext context,
  AppLocalizations l10n, {
  Prompt? prompt,
  required List<Prompt> userPrompts,
  required List<PromptTag> tags,
}) async {
  final titleCtrl = TextEditingController(text: prompt?.title ?? '');
  final contentCtrl = MarkdownTextEditingController(text: prompt?.content ?? '');
  bool isMarkdown = prompt?.isMarkdown ?? true;

  final Set<int> selectedTagIds = {};
  if (prompt != null) {
    for (var t in prompt.tags) {
      if (t.id != null) selectedTagIds.add(t.id!);
    }
  } else {
    // Default to 'General' tag if creating new
    final generalTag = tags.cast<PromptTag?>().firstWhere((t) => t?.name == 'General', orElse: () => null);
    if (generalTag != null && generalTag.id != null) {
      selectedTagIds.add(generalTag.id!);
    }
  }

  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Row(
          children: [
            Icon(prompt == null ? Icons.add_circle_outline : Icons.edit_note, color: Colors.blue),
            const SizedBox(width: 12),
            Text(prompt == null ? l10n.newPrompt : l10n.editPrompt),
          ],
        ),
        content: SizedBox(
          width: math.min(MediaQuery.of(context).size.width * 0.9, 800),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.title,
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.title),
                  ),
                ),
                const SizedBox(height: 16),
                Text(l10n.tagCategory, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                _TagChips(tags: tags, selectedTagIds: selectedTagIds, setDialogState: setDialogState),
                const SizedBox(height: 16),
                MarkdownEditor(
                  controller: contentCtrl,
                  label: l10n.promptContent,
                  isMarkdown: isMarkdown,
                  onMarkdownChanged: (v) => setDialogState(() => isMarkdown = v),
                  initiallyPreview: false,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
          FilledButton(
            onPressed: () async {
              if (titleCtrl.text.isEmpty || contentCtrl.text.isEmpty) return;

              final appState = Provider.of<AppState>(context, listen: false);
              final Map<String, dynamic> data = {
                'title': titleCtrl.text,
                'content': contentCtrl.text,
                'is_markdown': isMarkdown ? 1 : 0,
                'sort_order': prompt?.sortOrder ?? (userPrompts.isEmpty ? 0 : userPrompts.map((p) => p.sortOrder).reduce(math.max) + 1),
              };
              if (prompt == null) {
                await appState.addPrompt(data, tagIds: selectedTagIds.toList());
              } else {
                await appState.updatePrompt(prompt.id!, data, tagIds: selectedTagIds.toList());
              }
              if (context.mounted) Navigator.pop(context, true);
            },
            child: Text(prompt == null ? l10n.save : l10n.update),
          ),
        ],
      ),
    ),
  );
  return saved ?? false;
}

/// Create / edit a system template. Returns `true` if saved.
Future<bool> showSystemPromptEditDialog(
  BuildContext context,
  AppLocalizations l10n, {
  SystemPrompt? prompt,
  required List<SystemPrompt> systemPrompts,
  required List<PromptTag> tags,
  required String defaultType,
}) async {
  final titleCtrl = TextEditingController(text: prompt?.title ?? '');
  final contentCtrl = MarkdownTextEditingController(text: prompt?.content ?? '');
  bool isMarkdown = prompt?.isMarkdown ?? true;
  String selectedType = prompt?.type ?? defaultType;

  final Set<int> selectedTagIds = {};
  if (prompt != null) {
    for (var t in prompt.tags) {
      if (t.id != null) selectedTagIds.add(t.id!);
    }
  }

  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Row(
          children: [
            Icon(selectedType == 'refiner' ? Icons.auto_fix_high : Icons.drive_file_rename_outline, color: Colors.purple),
            const SizedBox(width: 12),
            Text(prompt == null ? l10n.add : l10n.editPrompt),
          ],
        ),
        content: SizedBox(
          width: math.min(MediaQuery.of(context).size.width * 0.9, 800),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(controller: titleCtrl, decoration: InputDecoration(labelText: l10n.title, border: const OutlineInputBorder())),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 1,
                      child: DropdownButtonFormField<String>(
                        initialValue: selectedType,
                        decoration: InputDecoration(labelText: l10n.templateType, border: const OutlineInputBorder()),
                        items: [
                          DropdownMenuItem(value: 'refiner', child: Text(l10n.typeRefiner)),
                          DropdownMenuItem(value: 'rename', child: Text(l10n.typeRename)),
                        ],
                        onChanged: (v) => setDialogState(() => selectedType = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(l10n.tagCategory, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                _TagChips(tags: tags, selectedTagIds: selectedTagIds, setDialogState: setDialogState),
                const SizedBox(height: 16),
                MarkdownEditor(
                  controller: contentCtrl,
                  label: l10n.promptContent,
                  isMarkdown: isMarkdown,
                  onMarkdownChanged: (v) => setDialogState(() => isMarkdown = v),
                  initiallyPreview: false,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
          FilledButton(
            onPressed: () async {
              if (titleCtrl.text.isEmpty || contentCtrl.text.isEmpty) return;
              final appState = Provider.of<AppState>(context, listen: false);
              final data = {
                'title': titleCtrl.text,
                'content': contentCtrl.text,
                'type': selectedType,
                'is_markdown': isMarkdown ? 1 : 0,
                'sort_order': prompt?.sortOrder ?? (systemPrompts.isEmpty ? 0 : systemPrompts.map((p) => p.sortOrder).reduce(math.max) + 1),
              };
              if (prompt == null) {
                await appState.addSystemPrompt(data, tagIds: selectedTagIds.toList());
              } else {
                await appState.updateSystemPrompt(prompt.id!, data, tagIds: selectedTagIds.toList());
              }
              if (context.mounted) Navigator.pop(context, true);
            },
            child: Text(l10n.save),
          ),
        ],
      ),
    ),
  );
  return saved ?? false;
}

/// Create / edit a category tag. Returns `true` if saved.
Future<bool> showTagEditDialog(
  BuildContext context,
  AppLocalizations l10n, {
  PromptTag? tag,
  required List<PromptTag> tags,
}) async {
  final nameCtrl = TextEditingController(text: tag?.name ?? '');
  int selectedColor = tag?.color ?? AppConstants.tagColors.first.toARGB32();

  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) {
        return AlertDialog(
          title: Text(tag == null ? l10n.addCategory : l10n.editCategory),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: nameCtrl, decoration: InputDecoration(labelText: l10n.name)),
                  const SizedBox(height: 24),
                  ColorPickerWidget(
                    selectedColor: selectedColor,
                    onColorChanged: (color) {
                      setDialogState(() => selectedColor = color);
                    },
                    showHexInput: true,
                    showColorWheel: true,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
            ElevatedButton(
              onPressed: () async {
                final appState = Provider.of<AppState>(context, listen: false);
                final data = {
                  'name': nameCtrl.text,
                  'color': selectedColor,
                  'sort_order': tag?.sortOrder ?? (tags.isEmpty ? 0 : tags.map((t) => t.sortOrder).reduce(math.max) + 1),
                };
                if (tag == null) {
                  await appState.addPromptTag(data);
                } else {
                  await appState.updatePromptTag(tag.id!, data);
                }
                if (context.mounted) Navigator.pop(context, true);
              },
              child: Text(l10n.save),
            ),
          ],
        );
      },
    ),
  );
  return saved ?? false;
}

/// Confirm-and-delete a single prompt (user or system). Returns `true` if deleted.
Future<bool> showDeletePromptConfirm(
  BuildContext context,
  AppLocalizations l10n,
  dynamic prompt, {
  required bool isSystem,
}) async {
  final colorScheme = Theme.of(context).colorScheme;
  final deleted = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.deletePromptConfirmTitle),
      content: Text(l10n.deletePromptConfirmMessage(prompt.title)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.error,
            foregroundColor: colorScheme.onError,
          ),
          onPressed: () async {
            final appState = Provider.of<AppState>(context, listen: false);
            if (isSystem) {
              await appState.deleteSystemPrompt(prompt.id);
            } else {
              await appState.deletePrompt(prompt.id);
            }
            if (context.mounted) Navigator.pop(context, true);
          },
          child: Text(l10n.delete),
        ),
      ],
    ),
  );
  return deleted ?? false;
}

/// Confirm-and-delete a category tag. Returns `true` if deleted.
Future<bool> showDeleteTagConfirm(
  BuildContext context,
  AppLocalizations l10n,
  PromptTag tag,
) async {
  final colorScheme = Theme.of(context).colorScheme;
  final deleted = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.delete),
      content: Text(l10n.deleteCategoryConfirmMessage(tag.name)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.error,
            foregroundColor: colorScheme.onError,
          ),
          onPressed: () async {
            final appState = Provider.of<AppState>(context, listen: false);
            await appState.deletePromptTag(tag.id!);
            if (context.mounted) Navigator.pop(context, true);
          },
          child: Text(l10n.delete),
        ),
      ],
    ),
  );
  return deleted ?? false;
}

/// Confirm bulk deletion of [count] items. Returns `true` if confirmed.
Future<bool> showBulkDeleteConfirm(
  BuildContext context,
  AppLocalizations l10n,
  int count,
) async {
  final colorScheme = Theme.of(context).colorScheme;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.deleteNPromptsConfirm(count)),
      content: Text(l10n.actionCannotBeUndone),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.error,
            foregroundColor: colorScheme.onError,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.delete),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Pick categories to apply in bulk. Returns the chosen tag ids, or `null` if cancelled.
Future<List<int>?> showBulkCategorizeDialog(
  BuildContext context,
  AppLocalizations l10n,
  List<PromptTag> tags,
) async {
  final Set<int> targetTagIds = {};

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(l10n.bulkCategorize),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.selectCategoriesToApply),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: tags.map((t) {
                final isSelected = targetTagIds.contains(t.id);
                return FilterChip(
                  label: Text(t.name),
                  selected: isSelected,
                  onSelected: (val) {
                    setDialogState(() {
                      if (val) {
                        targetTagIds.add(t.id!);
                      } else {
                        targetTagIds.remove(t.id!);
                      }
                    });
                  },
                );
              }).toList(),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.apply),
          ),
        ],
      ),
    ),
  );

  if (confirmed != true) return null;
  return targetTagIds.toList();
}

/// Selectable category chips shared by the prompt/system-prompt edit dialogs.
class _TagChips extends StatelessWidget {
  final List<PromptTag> tags;
  final Set<int> selectedTagIds;
  final StateSetter setDialogState;

  const _TagChips({
    required this.tags,
    required this.selectedTagIds,
    required this.setDialogState,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: tags.map((t) {
        final id = t.id!;
        final isSelected = selectedTagIds.contains(id);
        final color = Color(t.color);
        return FilterChip(
          label: Text(t.name, style: TextStyle(fontSize: 12, color: isSelected ? Colors.white : color)),
          selected: isSelected,
          onSelected: (val) {
            setDialogState(() {
              if (val) {
                selectedTagIds.add(id);
              } else {
                selectedTagIds.remove(id);
              }
            });
          },
          selectedColor: color,
          checkmarkColor: Colors.white,
        );
      }).toList(),
    );
  }
}
