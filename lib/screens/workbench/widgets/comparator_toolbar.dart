import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../state/workbench_ui_state.dart';
import '../../../widgets/app_switch.dart';
import '../../../widgets/glass/app_glass.dart';
import '../../../widgets/glass/glass_controls.dart';
import '../workbench_layout.dart';

/// The comparator's controls in the workbench's floating glass toolbar
/// (`A5 · 1c`, `A5 · 1d`): how the two images are arranged, whether the panes
/// move together, clear, and the metadata panel.
///
/// It fills the slot the toolbar leaves after the back button and the tool
/// switch — no ground, no frame of its own — and degrades inside that slot by
/// measurement, never by breakpoint, in this order: the actions lose their
/// labels (sync becomes a link toggle, clear and metadata bare glyphs with
/// tooltips), the layout switch loses its labels, then sync and clear fold
/// into a ⋮ menu. The layout switch never gives way; if even the folded row
/// does not fit, it scrolls rather than clipping.
class ComparatorToolbar extends StatelessWidget {
  const ComparatorToolbar({super.key});

  /// The bar's gap between neighbouring controls.
  static const double _gap = 4;

  static List<GlassSegment<ComparatorLayout>> _segments(AppLocalizations l10n) => [
        GlassSegment(
          value: ComparatorLayout.sideBySide,
          label: l10n.compareLayoutSideBySide,
          icon: Icons.vertical_split,
        ),
        GlassSegment(
          value: ComparatorLayout.stacked,
          label: l10n.compareLayoutStacked,
          icon: Icons.view_agenda_outlined,
        ),
        GlassSegment(
          value: ComparatorLayout.slider,
          label: l10n.compareLayoutSlider,
          icon: Icons.tonality,
        ),
      ];

  /// The inline sync control: 10 · label · 6 · 36px switch · 10.
  static double _syncInlineWidth(BuildContext context, String label) =>
      10 + measureGlassText(context, label, GlassIconButton.labelStyle(context)) + 6 + AppSwitch.size.width + 10;

  static double _measure(
    BuildContext context,
    AppLocalizations l10n, {
    required bool actionLabels,
    required bool layoutLabels,
    required bool folded,
  }) {
    double w = GlassDivider.extent;
    w += GlassSegmented.widthFor(context, _segments(l10n), showLabels: layoutLabels);
    if (!folded) {
      w += _gap + (actionLabels ? _syncInlineWidth(context, l10n.compareSyncTransform) : AppSize.control);
    }
    // The spacer never closes below one gap.
    w += _gap;
    w += folded
        ? AppSize.control
        : GlassIconButton.widthFor(context, label: actionLabels ? l10n.clear : null, hasIcon: false);
    w += _gap + GlassIconButton.widthFor(context, label: actionLabels ? l10n.metadata : null);
    return w.ceilToDouble();
  }

  /// The width these controls take with everything labelled — what the
  /// toolbar weighs its tool switch against.
  static double preferredWidth(BuildContext context) => _measure(
        context,
        AppLocalizations.of(context)!,
        actionLabels: true,
        layoutLabels: true,
        folded: false,
      );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) => _build(context, constraints.maxWidth));
  }

  Widget _build(BuildContext context, double width) {
    final l10n = AppLocalizations.of(context)!;
    final uiState = context.watch<WorkbenchUIState>();
    final panelDetached = context.watch<WorkbenchLayoutState>().rightPanelDetached;

    final hasImages = uiState.comparatorRawPath != null || uiState.comparatorAfterPath != null;
    // The curtain layers both images through one transform, so there is
    // nothing left for a sync switch to decide.
    final syncApplies = uiState.comparatorLayout != ComparatorLayout.slider;
    final syncOn = syncApplies && uiState.comparatorSyncTransform;
    final VoidCallback? toggleSync = syncApplies ? uiState.toggleComparatorSyncTransform : null;
    final VoidCallback? clear = hasImages ? uiState.clearComparator : null;

    bool actionLabels = true;
    bool layoutLabels = true;
    bool folded = false;
    double measure() => _measure(
          context,
          l10n,
          actionLabels: actionLabels,
          layoutLabels: layoutLabels,
          folded: folded,
        );

    final bounded = width.isFinite;
    if (bounded) {
      if (measure() > width) actionLabels = false;
      if (measure() > width) layoutLabels = false;
      if (measure() > width) folded = true;
    }
    final fits = bounded && measure() <= width;

    final row = Row(
      mainAxisSize: fits ? MainAxisSize.max : MainAxisSize.min,
      children: [
        const GlassDivider(),
        // A view switch, not a mode: the selected lens stays neutral.
        GlassSegmented<ComparatorLayout>(
          segments: _segments(l10n),
          value: uiState.comparatorLayout,
          onChanged: uiState.setComparatorLayout,
          showLabels: layoutLabels,
        ),
        if (!folded) ...[
          const SizedBox(width: _gap),
          if (actionLabels)
            _SyncSwitch(label: l10n.compareSyncTransform, value: syncOn, onToggle: toggleSync)
          else
            GlassIconButton(
              icon: Icons.link,
              tooltip: l10n.compareSyncTransform,
              active: syncOn,
              onPressed: toggleSync,
            ),
        ],
        if (fits) const Expanded(child: SizedBox()) else const SizedBox(width: _gap),
        if (folded)
          _ComparatorOverflowMenu(syncOn: syncOn, onToggleSync: toggleSync, onClear: clear)
        else
          GlassIconButton(
            icon: actionLabels ? null : Icons.clear,
            label: actionLabels ? l10n.clear : null,
            tooltip: actionLabels ? null : l10n.clear,
            danger: true,
            onPressed: clear,
          ),
        const SizedBox(width: _gap),
        GlassIconButton(
          icon: Icons.info_outline,
          label: actionLabels ? l10n.metadata : null,
          tooltip: actionLabels ? null : l10n.metadata,
          // Where the panel is part of the layout this switches it; where it
          // is a drawer or a sheet it is opened rather than toggled — so the
          // lens is only ever shown where "on" is true.
          active: !panelDetached && uiState.comparatorShowMetadata,
          onPressed: () {
            if (panelDetached) {
              context.read<WorkbenchLayoutState>().openRightPanel();
            } else {
              uiState.toggleComparatorMetadata();
            }
          },
        ),
      ],
    );

    if (fits || !bounded) return row;
    return SingleChildScrollView(scrollDirection: Axis.horizontal, child: row);
  }
}

/// "Sync Zoom & Pan" with its switch inline (`A5 · 1c`): one 32px target, so
/// the label toggles as well as the track.
class _SyncSwitch extends StatefulWidget {
  const _SyncSwitch({required this.label, required this.value, required this.onToggle});

  final String label;
  final bool value;

  /// Null in the curtain layout, where there is nothing to sync.
  final VoidCallback? onToggle;

  @override
  State<_SyncSwitch> createState() => _SyncSwitchState();
}

class _SyncSwitchState extends State<_SyncSwitch> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final glass = GlassInk.maybeOf(context);
    final ink = glass?.ink ?? scheme.onSurface;
    final ink2 = glass?.ink2 ?? scheme.onSurfaceVariant;
    final enabled = widget.onToggle != null;

    return Semantics(
      toggled: widget.value,
      enabled: enabled,
      label: widget.label,
      onTap: widget.onToggle,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onToggle,
          child: AnimatedContainer(
            duration: AppMotion.durationOf(context, AppMotion.hover),
            curve: AppMotion.quick,
            height: AppSize.control,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: _hovering && enabled ? ink.withValues(alpha: 0.08) : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.label,
                  maxLines: 1,
                  style: GlassIconButton.labelStyle(context).copyWith(
                    color: enabled ? ink : ink2.withValues(alpha: ink2.a * 0.6),
                  ),
                ),
                const SizedBox(width: 6),
                AppSwitch(
                  value: widget.value,
                  onChanged: enabled ? (_) => widget.onToggle!() : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Sync and clear, folded: the last step before the row scrolls.
class _ComparatorOverflowMenu extends StatelessWidget {
  const _ComparatorOverflowMenu({
    required this.syncOn,
    required this.onToggleSync,
    required this.onClear,
  });

  final bool syncOn;
  final VoidCallback? onToggleSync;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          leadingIcon: Icon(Icons.link, size: AppSize.iconLg, color: syncOn ? scheme.primary : null),
          trailingIcon: syncOn ? Icon(Icons.check, size: AppSize.iconMd, color: scheme.primary) : null,
          onPressed: onToggleSync,
          child: Text(l10n.compareSyncTransform),
        ),
        MenuItemButton(
          leadingIcon: Icon(
            Icons.clear,
            size: AppSize.iconLg,
            color: onClear != null ? scheme.error : null,
          ),
          onPressed: onClear,
          child: Text(
            l10n.clear,
            style: onClear != null ? TextStyle(color: scheme.error) : null,
          ),
        ),
      ],
      builder: (context, controller, _) => GlassIconButton(
        icon: Icons.more_vert,
        tooltip: l10n.more,
        active: controller.isOpen,
        onPressed: () => controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}
