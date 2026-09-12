import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/app_image.dart';
import '../../../state/app_state.dart';
import '../../../state/gallery_state.dart';
import '../../../state/workbench_ui_state.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/glass/app_glass.dart';
import '../../../widgets/glass/glass_controls.dart';
import 'gallery_file_actions.dart';

/// Empties the temporary workspace, behind a confirmation.
///
/// Asked rather than done outright: the workspace is assembled by hand and
/// there is no undo. The message says the files survive — this drops
/// references, it deletes nothing from disk.
void confirmClearTempWorkspace(
  BuildContext context,
  GalleryState galleryState,
  AppLocalizations l10n,
) {
  final count = galleryState.droppedImages.length;
  AppDialog.show<void>(
    context,
    title: l10n.clearTempWorkspaceConfirmTitle,
    icon: Icons.delete_sweep_outlined,
    iconColor: Theme.of(context).colorScheme.error,
    content: Text(l10n.clearTempWorkspaceConfirmMessage(count)),
    actions: [
      AppButton(
        label: l10n.cancel,
        variant: AppButtonVariant.text,
        onPressed: () => Navigator.pop(context),
      ),
      AppButton(
        label: l10n.clearTempWorkspace,
        variant: AppButtonVariant.destructive,
        onPressed: () {
          galleryState.clearDroppedImages();
          Navigator.pop(context);
        },
      ),
    ],
  );
}

/// The floating bar that appears while images are selected (`A1 · 1a`, `1c`).
///
/// Batch actions moved here from the toolbar: they only mean something when
/// there is a selection, and a bar that exists only then says so. G2 glass,
/// 44 tall at r16, centred at the bottom of the gallery; it enters from 12px
/// below on M3 and leaves the same way.
///
/// Source and result views: select all · clear · send to assistant · share.
/// Workspace view: select all · clear · send to assistant · remove from
/// workspace · clear workspace (destructive, confirmed).
///
/// When the column is too narrow for the labels, the labelled actions keep
/// only their glyphs and name themselves in tooltips.
/// The slice of [GalleryState] this bar draws.
///
/// Narrower than a `watch` because the bar hangs over the gallery on every
/// gallery tab: subscribed to the whole notifier it rebuilt — glass shell,
/// five buttons and all — for a rescan, a view change, even a drag of the
/// thumbnail-size slider, none of which it shows.
///
/// [selected] compares by identity, which [GalleryState] guarantees.
typedef _BarInputs = ({
  List<AppImage> selected,
  GalleryViewMode viewMode,
  bool hasDropped,
});

_BarInputs _barInputs(GalleryState s) => (
      selected: s.selectedImages,
      viewMode: s.viewMode,
      hasDropped: s.droppedImages.isNotEmpty,
    );

class GallerySelectionBar extends StatelessWidget {
  const GallerySelectionBar({super.key});

  static const double height = 44;

  /// Space the gallery leaves below its last row while the bar can show.
  static const double clearance = height + 12 + AppSpace.s10;

  @override
  Widget build(BuildContext context) {
    final inputs = context.select<GalleryState, _BarInputs>(_barInputs);
    final count = inputs.selected.length;
    final visible = count > 0;
    final duration = AppMotion.sceneOf(context);

    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, 0.3),
        duration: duration,
        curve: AppMotion.emphasized,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: visible
              ? duration
              : Duration(milliseconds: (duration.inMilliseconds * AppMotion.exitFactor).round()),
          curve: AppMotion.emphasized,
          child: LayoutBuilder(
            builder: (context, constraints) =>
                _BarContent(inputs: inputs, count: count, maxWidth: constraints.maxWidth),
          ),
        ),
      ),
    );
  }
}

class _BarContent extends StatelessWidget {
  const _BarContent({required this.inputs, required this.count, required this.maxWidth});

  final _BarInputs inputs;
  final int count;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    // The actions only ever *call* the notifier, so they read it unlistened;
    // what the bar draws comes off [inputs].
    final gallery = Provider.of<GalleryState>(context, listen: false);
    final isTemp = inputs.viewMode == GalleryViewMode.temp;
    final canClearWorkspace = isTemp && inputs.hasDropped;
    final selected = inputs.selected;

    final countStyle = Theme.of(context).textTheme.bodySmall!.metricsOnly.copyWith(
          fontWeight: FontWeight.w600,
          color: scheme.onAccentTint,
        );
    final countLabel = l10n.selectedCount(count);

    final actions = <({IconData? icon, IconData compactIcon, String label, VoidCallback onTap, bool danger})>[
      (
        icon: null,
        compactIcon: Icons.select_all,
        label: l10n.selectAll,
        onTap: gallery.selectAllImages,
        danger: false,
      ),
      (
        icon: null,
        compactIcon: Icons.deselect,
        label: l10n.clear,
        onTap: gallery.clearImageSelection,
        danger: false,
      ),
      (
        icon: Icons.auto_awesome_outlined,
        compactIcon: Icons.auto_awesome_outlined,
        label: l10n.selectionSendToAssistant,
        onTap: () {
          context.read<WorkbenchUIState>().addAssistantImages(List.of(selected));
          context.read<AppState>().setWorkbenchTab(4);
        },
        danger: false,
      ),
      if (isTemp)
        (
          icon: Icons.remove_circle_outline,
          compactIcon: Icons.remove_circle_outline,
          label: l10n.removeFromWorkspace,
          onTap: () {
            for (final image in List.of(selected)) {
              gallery.removeDroppedImage(image.path);
            }
          },
          danger: false,
        )
      else
        (
          icon: Icons.ios_share,
          compactIcon: Icons.ios_share,
          label: l10n.shareCount(count),
          onTap: () {
            // The share sheet's anchor on iPad: the bar's own centre.
            final box = context.findRenderObject() as RenderBox?;
            final origin = box == null ? Offset.zero : box.localToGlobal(box.size.center(Offset.zero));
            shareImageFiles(context, List.of(selected), l10n, position: origin);
          },
          danger: false,
        ),
      if (canClearWorkspace)
        (
          icon: Icons.delete_sweep_outlined,
          compactIcon: Icons.delete_sweep_outlined,
          label: l10n.clearTempWorkspace,
          onTap: () => confirmClearTempWorkspace(context, gallery, l10n),
          danger: true,
        ),
    ];

    // Groups: [select all, clear] | [send, share/remove] | [clear workspace].
    final dividerAfter = <int>{1, if (canClearWorkspace) actions.length - 2};

    double fullWidth() {
      double w = 14 + measureGlassText(context, countLabel, countStyle) + 6 + 6;
      for (int i = 0; i < actions.length; i++) {
        final a = actions[i];
        w += GlassIconButton.widthFor(context, label: a.label, hasIcon: a.icon != null) + 4;
        if (dividerAfter.contains(i)) w += GlassDivider.extent + 4;
      }
      return w;
    }

    final compact = fullWidth() > maxWidth;

    final children = <Widget>[
      Text(countLabel, style: countStyle),
      const SizedBox(width: 6),
    ];
    for (int i = 0; i < actions.length; i++) {
      final a = actions[i];
      children.add(GlassIconButton(
        icon: compact ? a.compactIcon : a.icon,
        label: compact ? null : a.label,
        tooltip: compact ? a.label : null,
        danger: a.danger,
        onPressed: a.onTap,
      ));
      if (dividerAfter.contains(i) && i != actions.length - 1) children.add(const GlassDivider());
    }

    return SizedBox(
      height: GallerySelectionBar.height,
      child: AppGlass(
        grade: GlassGrade.float,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        padding: const EdgeInsets.fromLTRB(14, 0, 6, 0),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
    );
  }
}
