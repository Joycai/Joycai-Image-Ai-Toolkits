import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_theme.dart';
import '../../core/design_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../models/pricing_group.dart';
import '../../state/app_state.dart';
import '../glass/app_glass.dart';
import '../glass/glass_controls.dart';
import 'fee_group_dialogs.dart';
import 'fee_group_draft.dart';
import 'fee_group_editor_fields.dart';

/// The phone's fee-group editor (`D2 · 1h` 全屏编辑页): a glass header with
/// back, the title and delete; the fields; the models using the group,
/// read-only; and a glass bar pinned at the foot with Cancel and a tinted
/// Save.
///
/// Pushed over the usage screen with no transition (the design's 切屏 0ms).
/// Pops with the saved group's id, or null when nothing was written.
class FeeGroupEditPage extends StatefulWidget {
  const FeeGroupEditPage({super.key, this.group});

  final PricingGroup? group;

  /// Opens the page for [group] (null to add one).
  static Future<int?> push(BuildContext context, {PricingGroup? group}) {
    return Navigator.of(context).push<int?>(
      PageRouteBuilder<int?>(
        fullscreenDialog: true,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, _, _) => FeeGroupEditPage(group: group),
      ),
    );
  }

  @override
  State<FeeGroupEditPage> createState() => _FeeGroupEditPageState();
}

class _FeeGroupEditPageState extends State<FeeGroupEditPage> {
  late final FeeGroupDraft _draft = FeeGroupDraft(widget.group);
  bool _saving = false;

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  Future<void> _save(AppState appState) async {
    if (_saving || !_draft.canSave) return;
    setState(() => _saving = true);
    final id = await _draft.save(appState);
    if (!mounted) return;
    Navigator.of(context).pop(id);
  }

  Future<void> _delete(AppState appState, PricingGroup group, int modelCount) async {
    final deleted = await confirmDeleteFeeGroup(context, appState, group, modelCount: modelCount);
    if (deleted && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final appState = Provider.of<AppState>(context);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final group = widget.group;
    final models = group == null
        ? const <String>[]
        : [for (final m in appState.allModels) if (m.feeGroupId == group.id) m.modelName];
    final top = MediaQuery.paddingOf(context).top;
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppGlass(
            grade: GlassGrade.bar,
            edges: GlassEdges.bottom,
            shadow: false,
            child: Padding(
              padding: EdgeInsets.only(top: top),
              child: SizedBox(
                height: 56,
                child: Builder(
                  builder: (context) => Row(
                    children: [
                      const SizedBox(width: AppSpace.s6),
                      GlassIconButton(
                        icon: Icons.arrow_back,
                        tooltip: l10n.cancel,
                        size: AppSize.large,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: AppSpace.s6),
                      Expanded(
                        child: Text(
                          group == null ? l10n.newFeeGroup : l10n.editGroupTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.headlineMedium?.copyWith(color: GlassInk.maybeOf(context)?.ink),
                        ),
                      ),
                      if (group != null)
                        GlassIconButton(
                          icon: Icons.delete_outline,
                          tooltip: l10n.deleteGroup,
                          danger: true,
                          size: AppSize.large,
                          onPressed: () => _delete(appState, group, models.length),
                        ),
                      const SizedBox(width: AppSpace.s6),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  FeeGroupEditorFields(draft: _draft, narrow: true),
                  if (group != null) ...[
                    const SizedBox(height: 12),
                    _ModelsUsingGroup(models: models),
                  ],
                ],
              ),
            ),
          ),
          // `1h`: the one fixed glass bar — Cancel beside the tinted Save.
          AppGlass(
            grade: GlassGrade.bar,
            edges: GlassEdges.top,
            shadow: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(12, AppSpace.s10, 12, AppSpace.s10 + bottom),
              child: ListenableBuilder(
                listenable: _draft,
                builder: (context, _) {
                  final canSave = _draft.canSave && !_saving;
                  return Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: AppSize.touch,
                          child: TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: TextButton.styleFrom(
                              foregroundColor: scheme.onAccentTint,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
                            ),
                            child: Text(l10n.cancel, style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Semantics(
                          button: true,
                          enabled: canSave,
                          label: l10n.save,
                          child: GestureDetector(
                            onTap: canSave ? () => _save(appState) : null,
                            child: AppTintedGlass(
                              enabled: canSave,
                              child: SizedBox(
                                height: AppSize.touch,
                                child: Center(
                                  child: _saving
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : Text(
                                          l10n.save,
                                          style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `1h` 使用它的模型: the group's consumers, read-only, one 40 line each.
class _ModelsUsingGroup extends StatelessWidget {
  const _ModelsUsingGroup({required this.models});

  final List<String> models;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.s4),
          child: Text(l10n.modelsUsingGroup, style: textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: AppSpace.s4),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: models.isEmpty
              ? SizedBox(
                  height: AppSize.large,
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(l10n.feeGroupUnused, style: textTheme.labelSmall?.mono.copyWith(color: scheme.outline)),
                  ),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, name) in models.indexed)
                      Container(
                        height: AppSize.large,
                        alignment: AlignmentDirectional.centerStart,
                        decoration: i == 0
                            ? null
                            : BoxDecoration(border: Border(top: BorderSide(color: scheme.outlineVariant))),
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.mono.copyWith(color: scheme.onSurface),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
