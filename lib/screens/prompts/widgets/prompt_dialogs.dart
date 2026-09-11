import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_theme.dart';
import '../../../core/constants.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/prompt.dart';
import '../../../models/tag.dart';
import '../../../state/app_state.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/app_field_size.dart';
import '../../../widgets/app_labelled_field.dart';
import '../../../widgets/app_segmented_control.dart';
import '../../../widgets/color_picker_widget.dart';
import '../../../widgets/markdown_editor.dart';
import 'prompt_library_parts.dart';

/// Dialogs for the Prompt Library screen (`C1 · 1d`).
///
/// Each function owns its own UI and persistence (via [AppState]) and returns
/// a [Future] that resolves to `true` when the underlying data changed, so the
/// caller can reload its lists. This keeps [PromptsScreen] free of dialog markup
/// and database writes.
///
/// All of them are the [AppDialog] shell: an opaque panel, a 44px icon plate,
/// captions over 32px column-filled fields, the footer on the column colour.

/// A 32px single-line field on the column fill, as dialog forms draw it.
Widget _dialogField(BuildContext context, TextEditingController controller, {bool autofocus = false}) {
  final scheme = Theme.of(context).colorScheme;
  return SizedBox(
    height: AppSize.control,
    child: TextField(
      controller: controller,
      autofocus: autofocus,
      style: Theme.of(context).textTheme.bodyMedium,
      textAlignVertical: TextAlignVertical.center,
      decoration: InputDecoration(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.s10),
      ),
    ),
  );
}

/// Create / edit a user prompt. Returns `true` if saved.
///
/// [initialTitle] / [initialContent] prefill a *new* prompt (ignored when
/// editing an existing one) — the assistant's "save final prompt to library"
/// entry point arrives here with the staged prompt already written.
Future<bool> showPromptEditDialog(
  BuildContext context,
  AppLocalizations l10n, {
  Prompt? prompt,
  required List<Prompt> userPrompts,
  required List<PromptTag> tags,
  String? initialTitle,
  String? initialContent,
}) async {
  final titleCtrl = TextEditingController(text: prompt?.title ?? initialTitle ?? '');
  final contentCtrl =
      MarkdownTextEditingController(text: prompt?.content ?? initialContent ?? '');
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
      builder: (context, setDialogState) => AppDialog(
        icon: Icons.edit_note,
        title: prompt == null ? l10n.newPrompt : l10n.editPrompt,
        subtitle: l10n.promptEditorSubtitle,
        maxWidth: 520,
        scrollable: true,
        dividedHeading: false,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppLabelledField(
              label: l10n.title,
              size: AppFieldSize.regular,
              child: _dialogField(context, titleCtrl, autofocus: prompt == null && titleCtrl.text.isEmpty),
            ),
            if (tags.isNotEmpty) ...[
              const SizedBox(height: AppSpace.s16),
              AppLabelledField(
                label: l10n.tagCategory,
                size: AppFieldSize.regular,
                child: _TagChips(tags: tags, selectedTagIds: selectedTagIds, setDialogState: setDialogState),
              ),
            ],
            const SizedBox(height: AppSpace.s16),
            AppLabelledField(
              label: l10n.promptContent,
              size: AppFieldSize.regular,
              child: MarkdownEditor(
                controller: contentCtrl,
                label: l10n.promptContent,
                isMarkdown: isMarkdown,
                onMarkdownChanged: (v) => setDialogState(() => isMarkdown = v),
                initiallyPreview: false,
              ),
            ),
          ],
        ),
        actions: [
          AppButton(
            label: l10n.cancel,
            variant: AppButtonVariant.text,
            onPressed: () => Navigator.pop(context),
          ),
          AppButton(
            label: prompt == null ? l10n.save : l10n.update,
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
      builder: (context, setDialogState) {
        final typeStyle = promptTemplateTypeStyle(context, selectedType);
        return AppDialog(
          icon: typeStyle.icon,
          iconColor: typeStyle.glyph,
          title: prompt == null ? l10n.newTemplate : l10n.editPrompt,
          maxWidth: 520,
          scrollable: true,
          dividedHeading: false,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppLabelledField(
                label: l10n.title,
                size: AppFieldSize.regular,
                child: _dialogField(context, titleCtrl, autofocus: prompt == null),
              ),
              const SizedBox(height: AppSpace.s16),
              AppLabelledField(
                label: l10n.templateType,
                size: AppFieldSize.regular,
                child: AppSegmentedControl<String>(
                  compact: true,
                  segments: [
                    AppSegment(value: 'refiner', label: l10n.typeRefiner, icon: Icons.text_snippet_outlined),
                    AppSegment(value: 'rename', label: l10n.typeRename, icon: Icons.drive_file_rename_outline),
                  ],
                  value: selectedType,
                  onChanged: (v) => setDialogState(() => selectedType = v),
                ),
              ),
              if (tags.isNotEmpty) ...[
                const SizedBox(height: AppSpace.s16),
                AppLabelledField(
                  label: l10n.tagCategory,
                  size: AppFieldSize.regular,
                  child: _TagChips(tags: tags, selectedTagIds: selectedTagIds, setDialogState: setDialogState),
                ),
              ],
              const SizedBox(height: AppSpace.s16),
              AppLabelledField(
                label: l10n.promptContent,
                size: AppFieldSize.regular,
                child: MarkdownEditor(
                  controller: contentCtrl,
                  label: l10n.promptContent,
                  isMarkdown: isMarkdown,
                  onMarkdownChanged: (v) => setDialogState(() => isMarkdown = v),
                  initiallyPreview: false,
                ),
              ),
            ],
          ),
          actions: [
            AppButton(
              label: l10n.cancel,
              variant: AppButtonVariant.text,
              onPressed: () => Navigator.pop(context),
            ),
            AppButton(
              label: l10n.save,
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
            ),
          ],
        );
      },
    ),
  );
  return saved ?? false;
}

/// Create / edit a category tag. Returns `true` if saved.
///
/// [promptCount] is how many prompts the category holds, for the live preview.
Future<bool> showTagEditDialog(
  BuildContext context,
  AppLocalizations l10n, {
  PromptTag? tag,
  required List<PromptTag> tags,
  int promptCount = 0,
}) async {
  final nameCtrl = TextEditingController(text: tag?.name ?? '');
  int selectedColor = tag?.color ?? AppConstants.tagColors.first.toARGB32();

  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) {
        return AppDialog(
          icon: Icons.label_outline,
          title: tag == null ? l10n.addCategory : l10n.editCategory,
          subtitle: l10n.categoryColorHint,
          maxWidth: 400,
          scrollable: true,
          dividedHeading: false,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppLabelledField(
                label: l10n.name,
                size: AppFieldSize.regular,
                child: _dialogField(context, nameCtrl, autofocus: tag == null),
              ),
              const SizedBox(height: AppSpace.s16),
              ColorPickerWidget(
                selectedColor: selectedColor,
                onColorChanged: (color) {
                  setDialogState(() => selectedColor = color);
                },
                showHexInput: true,
                showColorWheel: true,
              ),
              const SizedBox(height: AppSpace.s16),
              _CategoryPreview(nameController: nameCtrl, color: Color(selectedColor), count: promptCount),
            ],
          ),
          actions: [
            AppButton(
              label: l10n.cancel,
              variant: AppButtonVariant.text,
              onPressed: () => Navigator.pop(context),
            ),
            AppButton(
              label: l10n.save,
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
  final deleted = await AppDialog.show<bool>(
    context,
    icon: Icons.delete_outline,
    iconColor: Theme.of(context).colorScheme.error,
    title: l10n.deletePromptConfirmTitle,
    maxWidth: 400,
    content: Text(l10n.deletePromptConfirmMessage(prompt.title)),
    actions: [
      AppButton(
        label: l10n.cancel,
        variant: AppButtonVariant.text,
        autofocus: true,
        onPressed: () => Navigator.pop(context),
      ),
      AppButton(
        label: l10n.delete,
        variant: AppButtonVariant.destructive,
        onPressed: () async {
          final appState = Provider.of<AppState>(context, listen: false);
          if (isSystem) {
            await appState.deleteSystemPrompt(prompt.id);
          } else {
            await appState.deletePrompt(prompt.id);
          }
          if (context.mounted) Navigator.pop(context, true);
        },
      ),
    ],
  );
  return deleted ?? false;
}

/// Confirm-and-delete a category tag. Returns `true` if deleted.
Future<bool> showDeleteTagConfirm(
  BuildContext context,
  AppLocalizations l10n,
  PromptTag tag,
) async {
  final deleted = await AppDialog.show<bool>(
    context,
    icon: Icons.delete_outline,
    iconColor: Theme.of(context).colorScheme.error,
    title: l10n.delete,
    maxWidth: 400,
    content: Text(l10n.deleteCategoryConfirmMessage(tag.name)),
    actions: [
      AppButton(
        label: l10n.cancel,
        variant: AppButtonVariant.text,
        autofocus: true,
        onPressed: () => Navigator.pop(context),
      ),
      AppButton(
        label: l10n.delete,
        variant: AppButtonVariant.destructive,
        onPressed: () async {
          final appState = Provider.of<AppState>(context, listen: false);
          await appState.deletePromptTag(tag.id!);
          if (context.mounted) Navigator.pop(context, true);
        },
      ),
    ],
  );
  return deleted ?? false;
}

/// Confirm bulk deletion of [count] items. Returns `true` if confirmed.
///
/// [titles] lists what is about to go, in mono, so the confirmation names the
/// prompts rather than only counting them.
Future<bool> showBulkDeleteConfirm(
  BuildContext context,
  AppLocalizations l10n,
  int count, {
  List<String> titles = const [],
}) async {
  const int shown = 8;
  final scheme = Theme.of(context).colorScheme;
  final monoStyle = Theme.of(context).textTheme.labelSmall!.mono.copyWith(
        fontWeight: FontWeight.w400,
        color: scheme.onSurfaceVariant,
      );

  final confirmed = await AppDialog.show<bool>(
    context,
    icon: Icons.delete_outline,
    iconColor: scheme.error,
    title: l10n.deleteNPromptsConfirm(count),
    maxWidth: 400,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.actionCannotBeUndone),
        if (titles.isNotEmpty) ...[
          const SizedBox(height: AppSpace.s10),
          Container(
            padding: const EdgeInsets.all(AppSpace.s10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final t in titles.take(shown))
                  Text(t, maxLines: 1, overflow: TextOverflow.ellipsis, style: monoStyle),
                if (titles.length > shown) Text('+${titles.length - shown}', style: monoStyle),
              ],
            ),
          ),
        ],
      ],
    ),
    actions: [
      AppButton(
        label: l10n.cancel,
        variant: AppButtonVariant.text,
        autofocus: true,
        onPressed: () => Navigator.pop(context, false),
      ),
      AppButton(
        label: l10n.delete,
        variant: AppButtonVariant.destructive,
        onPressed: () => Navigator.pop(context, true),
      ),
    ],
  );
  return confirmed ?? false;
}

/// Pick categories to apply in bulk. Returns the chosen tag ids, or `null` if cancelled.
///
/// [count] names how many prompts the choice lands on, under the title.
Future<List<int>?> showBulkCategorizeDialog(
  BuildContext context,
  AppLocalizations l10n,
  List<PromptTag> tags, {
  int? count,
}) async {
  final Set<int> targetTagIds = {};

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) {
        final scheme = Theme.of(context).colorScheme;
        return AppDialog(
          icon: Icons.label_outline,
          title: l10n.bulkCategorize,
          subtitle: count == null ? null : l10n.nSelected(count),
          maxWidth: 400,
          scrollable: true,
          dividedHeading: false,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.selectCategoriesToApply,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              _TagChips(tags: tags, selectedTagIds: targetTagIds, setDialogState: setDialogState),
            ],
          ),
          actions: [
            AppButton(
              label: l10n.cancel,
              variant: AppButtonVariant.text,
              onPressed: () => Navigator.pop(context, false),
            ),
            AppButton(
              label: l10n.apply,
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        );
      },
    ),
  );

  if (confirmed != true) return null;
  return targetTagIds.toList();
}

/// Selectable category chips shared by the prompt, template and bulk dialogs:
/// 28px pills with the identity dot; chosen ones take the accent wash.
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
      spacing: AppSpace.s6,
      runSpacing: AppSpace.s6,
      children: [
        for (final t in tags)
          PromptCategoryChip(
            label: t.name,
            color: Color(t.color),
            selected: selectedTagIds.contains(t.id),
            onTap: () => setDialogState(() {
              final id = t.id!;
              if (!selectedTagIds.remove(id)) selectedTagIds.add(id);
            }),
          ),
      ],
    );
  }
}

/// The live preview under the category editor: the colour's circle and the
/// name as it is being typed, on the column fill.
class _CategoryPreview extends StatelessWidget {
  const _CategoryPreview({required this.nameController, required this.color, required this.count});

  final TextEditingController nameController;
  final Color color;
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: AppSpace.s10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: nameController,
        builder: (context, value, _) {
          final empty = value.text.trim().isEmpty;
          return Row(
            children: [
              PromptCategoryDot(color: color, size: 20),
              const SizedBox(width: AppSpace.s10),
              Expanded(
                child: Text(
                  empty ? l10n.name : value.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: empty ? scheme.outline : scheme.onSurface,
                      ),
                ),
              ),
              const SizedBox(width: AppSpace.s10),
              Text(
                l10n.promptCount(count),
                style: Theme.of(context).textTheme.labelSmall!.mono.copyWith(
                      fontWeight: FontWeight.w400,
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          );
        },
      ),
    );
  }
}
