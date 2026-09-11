import 'package:flutter/material.dart';

import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_icon_button.dart';
import '../../../widgets/app_search_field.dart';
import '../../../widgets/app_segmented_control.dart';
import '../../../widgets/glass/glass_controls.dart';
import 'prompt_library_parts.dart';

/// Horizontal inset of both column headers.
const double _kHeaderPad = AppSpace.s22 - 2;

/// Gap between controls on a header row.
const double _kGap = AppSpace.s10;

/// What the search field is never squeezed below before something else folds.
/// A floor for a text input, not a breakpoint.
const double _kSearchFloor = 160;

/// Width of an [AppSegmentedControl] in its compact form: a 3px track inset,
/// and per segment 10px either side, the chip's invisible 1px edge and the
/// label measured at the selected weight.
double _segmentedWidth(BuildContext context, List<String> labels) {
  final style = Theme.of(context).textTheme.labelMedium!.copyWith(fontWeight: FontWeight.w600);
  double w = 6;
  for (final label in labels) {
    w += 2 + 20 + measureGlassText(context, label, style);
  }
  return w.ceilToDouble();
}

/// Width of an [AppButton] with a glyph: the theme's 14px sides, a 16px glyph
/// and Material's 8px gap, and the label at the filled weight.
double _buttonWidth(BuildContext context, String label) {
  final style = Theme.of(context).textTheme.labelLarge!.copyWith(fontWeight: FontWeight.w600);
  return (14 + AppSize.iconMd + 8 + measureGlassText(context, label, style) + 14).ceilToDouble();
}

/// The system-template type filter: All · Prompt Refiner · Batch Rename.
class PromptTemplateTypeSegmented extends StatelessWidget {
  const PromptTemplateTypeSegmented({super.key, required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  static List<String> labels(AppLocalizations l10n) => [l10n.filterAll, l10n.typeRefiner, l10n.typeRename];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AppSegmentedControl<String>(
      compact: true,
      segments: [
        AppSegment(value: 'all', label: l10n.filterAll),
        AppSegment(value: 'refiner', label: l10n.typeRefiner),
        AppSegment(value: 'rename', label: l10n.typeRename),
      ],
      value: value,
      onChanged: onChanged,
    );
  }
}

/// Import and export folded into one ⋮ (`C1 · 1b`, and the phone's app bar).
class PromptImportExportMenu extends StatelessWidget {
  const PromptImportExportMenu({
    super.key,
    required this.onImport,
    required this.onExport,
    this.boxed = true,
  });

  final VoidCallback onImport;
  final VoidCallback onExport;

  /// The header's outlined 32px box; false for a bare glyph on the phone's bar.
  final bool boxed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.file_upload_outlined, size: AppSize.iconMd),
          onPressed: onImport,
          child: Text(l10n.actionImport),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.file_download_outlined, size: AppSize.iconMd),
          onPressed: onExport,
          child: Text(l10n.actionExport),
        ),
      ],
      builder: (context, controller, _) {
        void toggle() => controller.isOpen ? controller.close() : controller.open();
        if (boxed) {
          return AppIconButton(
            icon: Icons.more_vert,
            tooltip: l10n.more,
            selected: controller.isOpen,
            onPressed: toggle,
          );
        }
        return IconButton(icon: const Icon(Icons.more_vert), tooltip: l10n.more, onPressed: toggle);
      },
    );
  }
}

/// The library column's 56px heading (`C1 · 1a` left): the accent tile, the
/// screen's name, and the Categories view as a toggle.
class PromptsSidebarHeader extends StatelessWidget {
  const PromptsSidebarHeader({
    super.key,
    required this.isCategories,
    required this.onToggleCategories,
  });

  final bool isCategories;
  final VoidCallback onToggleCategories;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          const PromptHeaderTile(icon: Icons.auto_awesome),
          const SizedBox(width: _kGap),
          Expanded(
            child: Text(
              l10n.promptLibrary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          AppIconButton(
            icon: Icons.label_outline,
            tooltip: l10n.categoriesTab,
            selected: isCategories,
            color: isCategories ? null : scheme.onSurfaceVariant,
            onPressed: onToggleCategories,
          ),
        ],
      ),
    );
  }
}

/// The list column's 56px heading (`C1 · 1a` right, `1b`).
///
/// Three forms: the list controls (view switch, template type, search,
/// import / export, create), the Categories view's title and create button,
/// and — while prompts are selected — close, count, Categorize and Delete.
///
/// The column beside it is drag-resizable, so this is anywhere from a phone's
/// width to a monitor's on the same device. It degrades by measuring its
/// controls against the width it gets, in this order: import and export fold
/// into ⋮, the template type moves to a strip under the header, the create
/// button keeps only its glyph.
class PromptsMainHeader extends StatelessWidget {
  const PromptsMainHeader({
    super.key,
    required this.view,
    required this.onViewChanged,
    required this.searchController,
    required this.systemType,
    required this.onSystemTypeChanged,
    required this.addLabel,
    required this.onAdd,
    required this.onImport,
    required this.onExport,
    required this.selectionCount,
    required this.onClearSelection,
    required this.onCategorize,
    required this.onDelete,
  });

  /// 0 user prompts · 1 system templates · 2 categories.
  final int view;
  final ValueChanged<int> onViewChanged;
  final TextEditingController searchController;
  final String systemType;
  final ValueChanged<String> onSystemTypeChanged;
  final String addLabel;
  final VoidCallback onAdd;
  final VoidCallback onImport;
  final VoidCallback onExport;
  final int selectionCount;
  final VoidCallback onClearSelection;
  final VoidCallback onCategorize;
  final VoidCallback onDelete;

  static const double height = 56;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth - _kHeaderPad * 2;
        if (selectionCount > 0) return _bar(context, _buildSelection(context, width));
        if (view == 2) return _bar(context, _buildCategories(context, width));
        return _buildLists(context, width);
      },
    );
  }

  Widget _bar(BuildContext context, Widget child) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: _kHeaderPad),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: child,
    );
  }

  TextStyle _titleStyle(BuildContext context) =>
      Theme.of(context).textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w600);

  Widget _buildSelection(BuildContext context, double width) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final countLabel = l10n.nSelected(selectionCount);

    final full = AppSize.iconButton +
        _kGap +
        measureGlassText(context, countLabel, _titleStyle(context)) +
        _kGap +
        _buttonWidth(context, l10n.categorize) +
        AppSpace.s6 +
        _buttonWidth(context, l10n.delete);
    final labelled = full <= width;

    return Row(
      children: [
        AppIconButton(icon: Icons.close, tooltip: l10n.cancel, onPressed: onClearSelection),
        const SizedBox(width: _kGap),
        Expanded(
          child: Text(
            countLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _titleStyle(context).copyWith(color: scheme.onAccentTint),
          ),
        ),
        const SizedBox(width: _kGap),
        if (labelled) ...[
          AppButton(
            label: l10n.categorize,
            icon: Icons.label_outline,
            variant: AppButtonVariant.secondary,
            onPressed: onCategorize,
          ),
          const SizedBox(width: AppSpace.s6),
          AppButton(
            label: l10n.delete,
            icon: Icons.delete_outline,
            variant: AppButtonVariant.destructive,
            onPressed: onDelete,
          ),
        ] else ...[
          AppIconButton(icon: Icons.label_outline, tooltip: l10n.categorize, onPressed: onCategorize),
          const SizedBox(width: AppSpace.s6),
          AppIconButton(
            icon: Icons.delete_outline,
            tooltip: l10n.delete,
            color: scheme.error,
            onPressed: onDelete,
          ),
        ],
      ],
    );
  }

  Widget _buildCategories(BuildContext context, double width) {
    final l10n = AppLocalizations.of(context)!;
    final full = AppSize.control +
        _kGap +
        measureGlassText(context, l10n.categoriesTab, _titleStyle(context)) +
        _kGap +
        _buttonWidth(context, l10n.addCategory);

    return Row(
      children: [
        const PromptHeaderTile(icon: Icons.label_outline),
        const SizedBox(width: _kGap),
        Expanded(
          child: Text(
            l10n.categoriesTab,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _titleStyle(context),
          ),
        ),
        const SizedBox(width: _kGap),
        _CreateButton(label: l10n.addCategory, iconOnly: full > width, onPressed: onAdd),
      ],
    );
  }

  Widget _buildLists(BuildContext context, double width) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final isSystem = view == 1;

    final viewLabels = [l10n.userPrompts, l10n.systemTemplates];
    final viewWidth = _segmentedWidth(context, viewLabels);
    final typeWidth = _segmentedWidth(context, PromptTemplateTypeSegmented.labels(l10n));
    final ioLabelled = _buttonWidth(context, l10n.actionImport) + AppSpace.s6 + _buttonWidth(context, l10n.actionExport);
    final addLabelled = _buttonWidth(context, addLabel);

    bool ioFolded = false;
    bool typeInHeader = isSystem;
    bool addIconOnly = false;

    double measure() {
      double w = viewWidth + _kGap + _kSearchFloor + _kGap;
      if (typeInHeader) w += typeWidth + _kGap;
      w += ioFolded ? AppSize.iconButton : ioLabelled;
      w += _kGap + (addIconOnly ? AppSize.iconButton : addLabelled);
      return w;
    }

    if (measure() > width) ioFolded = true;
    if (isSystem && measure() > width) typeInHeader = false;
    if (measure() > width) addIconOnly = true;

    final row = Row(
      children: [
        AppSegmentedControl<int>(
          compact: true,
          style: AppSegmentStyle.raised,
          segments: [
            AppSegment(value: 0, label: l10n.userPrompts),
            AppSegment(value: 1, label: l10n.systemTemplates),
          ],
          value: view,
          onChanged: onViewChanged,
        ),
        const SizedBox(width: _kGap),
        if (typeInHeader) ...[
          PromptTemplateTypeSegmented(value: systemType, onChanged: onSystemTypeChanged),
          const SizedBox(width: _kGap),
        ],
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: ioFolded ? 240 : 360),
              child: SizedBox(
                height: AppSize.control,
                child: AppSearchField(controller: searchController, hint: l10n.filterPrompts),
              ),
            ),
          ),
        ),
        const SizedBox(width: _kGap),
        if (ioFolded)
          PromptImportExportMenu(onImport: onImport, onExport: onExport)
        else ...[
          AppButton(
            label: l10n.actionImport,
            icon: Icons.file_upload_outlined,
            variant: AppButtonVariant.secondary,
            onPressed: onImport,
          ),
          const SizedBox(width: AppSpace.s6),
          AppButton(
            label: l10n.actionExport,
            icon: Icons.file_download_outlined,
            variant: AppButtonVariant.secondary,
            onPressed: onExport,
          ),
        ],
        const SizedBox(width: _kGap),
        _CreateButton(label: addLabel, iconOnly: addIconOnly, onPressed: onAdd),
      ],
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _bar(context, row),
        if (isSystem && !typeInHeader)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: _kHeaderPad, vertical: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: PromptTemplateTypeSegmented(value: systemType, onChanged: onSystemTypeChanged),
            ),
          ),
      ],
    );
  }
}

/// The header's one solid accent: labelled, or its glyph alone when the row
/// has no room.
class _CreateButton extends StatelessWidget {
  const _CreateButton({required this.label, required this.iconOnly, required this.onPressed});

  final String label;
  final bool iconOnly;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (!iconOnly) return AppButton(label: label, icon: Icons.add, onPressed: onPressed);
    return Tooltip(
      message: label,
      child: FilledButton(
        style: FilledButton.styleFrom(
          minimumSize: const Size(AppSize.iconButton, AppSize.iconButton),
          fixedSize: const Size(AppSize.iconButton, AppSize.iconButton),
          padding: EdgeInsets.zero,
        ),
        onPressed: onPressed,
        child: const Icon(Icons.add, size: AppSize.iconMd),
      ),
    );
  }
}
