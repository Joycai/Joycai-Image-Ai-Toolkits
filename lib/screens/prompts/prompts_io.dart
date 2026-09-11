import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_semantic_colors.dart';
import '../../core/design_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../models/prompt.dart';
import '../../models/tag.dart';
import '../../state/app_state.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_snackbar.dart';

/// Import / export helpers for the Prompt Library.
///
/// These keep file-picking, JSON (de)serialization and user feedback out of the
/// screen widget. They show their own snackbars and dialogs via the given
/// [context]; callers should reload their lists after [importPrompts] succeeds.

/// Export tags + user/system prompts to a user-chosen JSON file.
Future<void> exportPrompts(
  BuildContext context,
  AppLocalizations l10n, {
  required List<PromptTag> tags,
  required List<Prompt> userPrompts,
  required List<SystemPrompt> systemPrompts,
}) async {
  final data = {
    'tags': tags.map((t) => t.toMap()).toList(),
    'user_prompts': userPrompts.map((p) => {
          ...p.toMap(),
          'tags': p.tags.map((t) => t.toMap()).toList(),
        }).toList(),
    'system_prompts': systemPrompts.map((p) => {
          ...p.toMap(),
          'tags': p.tags.map((t) => t.toMap()).toList(),
        }).toList(),
    'export_type': 'prompts_only',
    'version': 1,
  };

  final json = jsonEncode(data);
  final bytes = utf8.encode(json);

  // file_picker >= 12 writes `bytes` itself on every platform and returns the
  // destination as a Uri, so no follow-up write is needed here.
  final Uri? saved = await FilePicker.saveFile(
    fileName: 'joycai_prompts.json',
    type: FileType.custom,
    allowedExtensions: ['json'],
    bytes: bytes,
  );

  if (saved != null && context.mounted) {
    AppSnackBar.success(context, l10n.settingsExported);
  }
}

/// Pick a JSON file, prompt for merge/replace, and import the prompt data.
/// Returns `true` if data was imported (caller should reload).
///
/// The file is read before the mode dialog, so the dialog can say how many
/// prompts it holds and what each choice does to the current library. A file
/// that does not parse fails here, with the same message as a failed import.
Future<bool> importPrompts(BuildContext context, AppLocalizations l10n) async {
  final appState = Provider.of<AppState>(context, listen: false);
  final successMsg = l10n.settingsImported;

  final PlatformFile? picked = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['json']);
  if (!context.mounted || picked == null) return false;

  final Map<String, dynamic> data;
  try {
    final String content = utf8.decode(await picked.readAsBytes());
    data = jsonDecode(content) as Map<String, dynamic>;
  } catch (e) {
    if (context.mounted) AppSnackBar.error(context, l10n.importFailed(e.toString()));
    return false;
  }

  final int incoming = _listLength(data['user_prompts']) + _listLength(data['system_prompts']);
  final int current = (await appState.getPrompts()).length + (await appState.getSystemPrompts()).length;
  if (!context.mounted) return false;

  final String? importMode = await showDialog<String>(
    context: context,
    builder: (_) => _ImportModeDialog(fileName: picked.name, incoming: incoming, current: current),
  );

  if (importMode == null) return false;

  try {
    await appState.importPromptData(data, replace: importMode == 'replace');

    if (!context.mounted) return true;
    AppSnackBar.success(context, successMsg);
    return true;
  } catch (e) {
    if (!context.mounted) return false;
    AppSnackBar.error(context, l10n.importFailed(e.toString()));
    return false;
  }
}

int _listLength(Object? value) => value is List ? value.length : 0;

/// `C1 · 1d` 导入模式: the file and what it holds, and Merge or Replace All as
/// two option cards stating what each does to the library. The confirming
/// button names the chosen mode, and turns destructive for Replace All — that
/// one deletes the current library.
class _ImportModeDialog extends StatefulWidget {
  const _ImportModeDialog({required this.fileName, required this.incoming, required this.current});

  final String fileName;

  /// Prompts in the file.
  final int incoming;

  /// Prompts in the library now.
  final int current;

  @override
  State<_ImportModeDialog> createState() => _ImportModeDialogState();
}

class _ImportModeDialogState extends State<_ImportModeDialog> {
  String _mode = 'merge';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final replace = _mode == 'replace';

    return AppDialog(
      icon: Icons.file_upload_outlined,
      iconColor: context.semantic.warning,
      title: l10n.importMode,
      subtitle: l10n.importFileSummary(widget.fileName, widget.incoming),
      maxWidth: 400,
      scrollable: true,
      dividedHeading: false,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ModeOption(
            label: l10n.merge,
            detail: l10n.importMergeDetail(widget.current),
            selected: !replace,
            onTap: () => setState(() => _mode = 'merge'),
          ),
          const SizedBox(height: 8),
          _ModeOption(
            label: l10n.replaceAll,
            detail: l10n.importReplaceDetail(widget.current, widget.incoming),
            selected: replace,
            onTap: () => setState(() => _mode = 'replace'),
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
          label: replace ? l10n.replaceAll : l10n.merge,
          variant: replace ? AppButtonVariant.destructive : AppButtonVariant.primary,
          onPressed: () => Navigator.pop(context, _mode),
        ),
      ],
    );
  }
}

class _ModeOption extends StatelessWidget {
  const _ModeOption({
    required this.label,
    required this.detail,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String detail;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(AppRadius.control);

    return Semantics(
      selected: selected,
      button: true,
      child: AnimatedContainer(
        duration: AppMotion.durationOf(context, AppMotion.hover),
        curve: AppMotion.quick,
        decoration: BoxDecoration(
          color: selected ? scheme.accentTint : scheme.surfaceContainerLow,
          borderRadius: radius,
          border: Border.all(color: selected ? scheme.primary : scheme.outlineVariant),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: AppSpace.s10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: AnimatedContainer(
                      duration: AppMotion.durationOf(context, AppMotion.hover),
                      width: AppSize.iconMd,
                      height: AppSize.iconMd,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected ? scheme.primary : scheme.outline,
                          width: selected ? 5 : 1.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpace.s10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                            color: selected ? scheme.onAccentTint : scheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          detail,
                          style: textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: AppType.proseHeight,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
