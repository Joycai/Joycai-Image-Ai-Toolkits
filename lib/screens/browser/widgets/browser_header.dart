import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../state/file_browser_state.dart';
import '../../../widgets/glass/glass_controls.dart' show measureGlassText;

/// The file area's 72px header — `B1a · 1a`.
///
/// Edge to edge on the column colour, not glass: the search field, the counts
/// and the view switch have to stay put, and a floating glass bar would sit
/// over the first row of files once the grid scrolls.
///
/// Folder block (or the drawer's hamburger on a narrow window) · title with
/// "{n} files · {n} selected" under it · search (up to 460, right-aligned) ·
/// staging button with its count · Grid/List · refresh.
///
/// When the row cannot hold the title and the search field's own content —
/// measured, not guessed — the search collapses to an icon button (`1c`),
/// and opening it gives the field the title's place until it is dismissed.
class BrowserHeader extends StatelessWidget {
  const BrowserHeader({
    super.key,
    required this.state,
    required this.stagingCount,
    required this.stagingOpen,
    required this.onStagingPressed,
    required this.searchController,
    required this.searchFocusNode,
    required this.searchOpen,
    required this.onSearchOpen,
    required this.onSearchChanged,
    required this.onRefresh,
    this.onOpenDrawer,
  });

  static const double height = 72;

  final FileBrowserState state;
  final int stagingCount;
  final bool stagingOpen;
  final VoidCallback onStagingPressed;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;

  /// Whether a collapsed search has been opened.
  final bool searchOpen;
  final VoidCallback onSearchOpen;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onRefresh;

  /// Non-null on a narrow window, where the directory column is a drawer and
  /// the hamburger takes the folder block's place.
  final VoidCallback? onOpenDrawer;

  static const double _searchMaxWidth = 460;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final titleStyle = textTheme.titleLarge!.copyWith(color: scheme.onSurface);
    final summaryStyle = textTheme.bodySmall!.copyWith(color: scheme.onSurfaceVariant);
    final selectedStyle = textTheme.bodySmall!.mono.copyWith(
      color: scheme.onAccentTint,
      fontWeight: FontWeight.w500,
    );

    final fileCount = state.filteredFiles.length;
    final selectedCount = state.selectedFiles.length;
    final filesLabel = l10n.filesCount(fileCount);
    const separator = '  ·  ';
    // `1c`: with the directory column behind the drawer, the subtitle takes
    // over its folder count.
    final String? foldersLabel =
        onOpenDrawer != null ? l10n.browserFoldersCount(state.sourceDirectories.length) : null;

    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrowForm = onOpenDrawer != null;
          final double leadWidth = narrowForm ? AppSize.large + AppSpace.s6 : AppSize.touch + 12;
          // Measured against the widest the summary can get — every file
          // selected — so selecting does not flip the header between forms.
          final double textWidth = math.max(
            measureGlassText(context, l10n.fileBrowser, titleStyle),
            measureGlassText(
                  context,
                  filesLabel + separator + (foldersLabel == null ? '' : foldersLabel + separator),
                  summaryStyle,
                ) +
                measureGlassText(context, l10n.imagesSelected(fileCount), selectedStyle),
          );
          const double controlsWidth =
              12 + AppSize.control + AppSpace.s6 + _ViewModeToggle.width + AppSpace.s6 + AppSize.control;
          final double searchMin = _BrowserSearchField.minWidthFor(context, l10n.searchFilesHint);
          final bool collapsed =
              leadWidth + textWidth + AppSpace.s16 + searchMin + controlsWidth > constraints.maxWidth;
          final bool showCollapsedField = collapsed && (searchOpen || searchController.text.isNotEmpty);

          final Widget lead = narrowForm
              ? SizedBox.square(
                  dimension: AppSize.large,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.menu),
                    tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
                    onPressed: onOpenDrawer,
                  ),
                )
              : Container(
                  width: AppSize.touch,
                  height: AppSize.touch,
                  decoration: BoxDecoration(
                    color: scheme.accentTint,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: Icon(Icons.folder_open_outlined, size: 24, color: scheme.primary),
                );

          final Widget titleBlock = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.fileBrowser,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: titleStyle,
              ),
              const SizedBox(height: 2),
              Text.rich(
                TextSpan(
                  style: summaryStyle,
                  children: [
                    TextSpan(text: filesLabel),
                    if (foldersLabel != null) ...[
                      const TextSpan(text: separator),
                      TextSpan(text: foldersLabel),
                    ],
                    if (selectedCount > 0) ...[
                      const TextSpan(text: separator),
                      TextSpan(text: l10n.imagesSelected(selectedCount), style: selectedStyle),
                    ],
                  ],
                ),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          );

          final field = _BrowserSearchField(
            controller: searchController,
            focusNode: searchFocusNode,
            hint: l10n.searchFilesHint,
            onChanged: onSearchChanged,
          );

          final controls = <Widget>[
            const SizedBox(width: 12),
            _StagingButton(count: stagingCount, open: stagingOpen, onPressed: onStagingPressed),
            const SizedBox(width: AppSpace.s6),
            _ViewModeToggle(value: state.viewMode, onChanged: state.setViewMode),
            const SizedBox(width: AppSpace.s6),
            SizedBox.square(
              dimension: AppSize.control,
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.refresh, size: AppSize.iconLg),
                tooltip: l10n.refresh,
                onPressed: onRefresh,
              ),
            ),
          ];

          final double leadGap = narrowForm ? AppSpace.s6 : 12;

          if (showCollapsedField) {
            return Row(
              children: [
                lead,
                SizedBox(width: leadGap),
                Expanded(child: field),
                ...controls,
              ],
            );
          }

          if (collapsed) {
            return Row(
              children: [
                lead,
                SizedBox(width: leadGap),
                Expanded(child: titleBlock),
                const SizedBox(width: AppSpace.s6),
                SizedBox.square(
                  dimension: AppSize.control,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.search, size: AppSize.iconLg),
                    tooltip: l10n.searchFilesHint,
                    onPressed: onSearchOpen,
                  ),
                ),
                ...controls,
              ],
            );
          }

          return Row(
            children: [
              lead,
              SizedBox(width: leadGap),
              titleBlock,
              const SizedBox(width: AppSpace.s16),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: _searchMaxWidth),
                    child: field,
                  ),
                ),
              ),
              ...controls,
            ],
          );
        },
      ),
    );
  }
}

/// The header's search: 32 tall at r10 on the panel colour with a hairline.
/// Focused, the edge takes the accent and a 3px `--ring` sits outside it
/// (`B1a · 1b`). On the right, the key that reaches it (`Ctrl+F`) while at
/// rest, the key that leaves it (`Esc`) while focused, and a clear button
/// once there is a query.
class _BrowserSearchField extends StatefulWidget {
  const _BrowserSearchField({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final ValueChanged<String> onChanged;

  static String get _shortcutLabel => Platform.isMacOS ? '⌘F' : 'Ctrl+F';

  static TextStyle _keyStyle(BuildContext context) =>
      Theme.of(context).textTheme.labelSmall!.mono.copyWith(fontWeight: FontWeight.w400);

  /// The field's own content at rest: glyph, hint and shortcut.
  static double minWidthFor(BuildContext context, String hint) {
    final textTheme = Theme.of(context).textTheme;
    return AppSpace.s10 +
        AppSize.iconMd +
        8 +
        measureGlassText(context, hint, textTheme.bodyMedium!) +
        8 +
        measureGlassText(context, _shortcutLabel, _keyStyle(context)) +
        AppSpace.s10;
  }

  @override
  State<_BrowserSearchField> createState() => _BrowserSearchFieldState();
}

class _BrowserSearchFieldState extends State<_BrowserSearchField> {
  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_changed);
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(_BrowserSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_changed);
      widget.focusNode.addListener(_changed);
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_changed);
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _clear() {
    widget.controller.clear();
    widget.onChanged('');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final focused = widget.focusNode.hasFocus;
    final hasText = widget.controller.text.isNotEmpty;
    const none = InputBorder.none;

    return AnimatedContainer(
      duration: AppMotion.durationOf(context, AppMotion.hover),
      curve: AppMotion.quick,
      height: AppSize.control,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: focused ? scheme.primary : scheme.outlineVariant),
        // A spread shadow is a ring here because the field is opaque: the
        // part of it under the panel fill never shows.
        boxShadow: focused ? [BoxShadow(color: scheme.accentRing, spreadRadius: 3)] : null,
      ),
      child: Row(
        children: [
          const SizedBox(width: AppSpace.s10),
          Icon(Icons.search, size: AppSize.iconMd, color: scheme.outline),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: widget.focusNode,
              onChanged: widget.onChanged,
              style: textTheme.bodyMedium?.copyWith(color: scheme.onSurface),
              textAlignVertical: TextAlignVertical.center,
              decoration: InputDecoration(
                isCollapsed: true,
                filled: false,
                contentPadding: EdgeInsets.zero,
                hintText: widget.hint,
                hintStyle: textTheme.bodyMedium?.copyWith(color: scheme.outline),
                border: none,
                enabledBorder: none,
                focusedBorder: none,
                disabledBorder: none,
                errorBorder: none,
                focusedErrorBorder: none,
              ),
            ),
          ),
          if (hasText) ...[
            SizedBox.square(
              dimension: AppSize.compact,
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: Icon(Icons.close, size: AppSize.iconSm, color: scheme.onSurfaceVariant),
                tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
                onPressed: _clear,
              ),
            ),
            const SizedBox(width: 2),
          ] else ...[
            const SizedBox(width: 8),
            ExcludeSemantics(
              child: Text(
                focused ? AppLocalizations.of(context)!.browserSearchEscHint : _BrowserSearchField._shortcutLabel,
                maxLines: 1,
                style: _BrowserSearchField._keyStyle(context).copyWith(color: scheme.outline),
              ),
            ),
            const SizedBox(width: AppSpace.s10),
          ],
        ],
      ),
    );
  }
}

/// The way into the staging column: 32 at r10 on the panel colour, `inbox`,
/// with a 16px count badge in the accent's solid form. Open, it takes the
/// selected form — the 12% wash, the ring, the glyph in the accent.
class _StagingButton extends StatelessWidget {
  const _StagingButton({required this.count, required this.open, required this.onPressed});

  final int count;
  final bool open;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    final button = Tooltip(
      message: l10n.stagingArea,
      child: Material(
        color: open ? scheme.accentTint : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          side: BorderSide(color: open ? scheme.accentRing : scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox.square(
            dimension: AppSize.control,
            child: Icon(
              Icons.inbox_outlined,
              size: AppSize.iconMd,
              color: open ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );

    return Semantics(
      button: true,
      selected: open,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          button,
          // A badge rather than a number in the label: at zero the button is
          // still there — the feature has to be findable before anything is
          // in it — and a badge can be absent without the button resizing.
          if (count > 0)
            Positioned(
              top: -5,
              right: -5,
              child: IgnorePointer(
                child: Container(
                  constraints: const BoxConstraints(minWidth: AppSpace.s16),
                  height: AppSpace.s16,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.s4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    '$count',
                    maxLines: 1,
                    style: Theme.of(context).textTheme.labelSmall!.mono.copyWith(
                          color: scheme.onPrimary,
                          fontWeight: FontWeight.w600,
                          height: 1,
                          letterSpacing: 0,
                        ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Grid / List: a track at r10 with 2px of padding, the chosen view a 28px
/// panel piece at r6 lifted out of it. Neutral, not the accent — on this
/// screen the accent means a selected file.
class _ViewModeToggle extends StatelessWidget {
  const _ViewModeToggle({required this.value, required this.onChanged});

  static const double width = 2 + AppSize.compact * 2 + 2;

  final BrowserViewMode value;
  final ValueChanged<BrowserViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ViewSegment(
            icon: Icons.grid_view,
            tooltip: l10n.browserViewGrid,
            selected: value == BrowserViewMode.grid,
            onTap: () => onChanged(BrowserViewMode.grid),
          ),
          _ViewSegment(
            icon: Icons.view_list_outlined,
            tooltip: l10n.browserViewList,
            selected: value == BrowserViewMode.list,
            onTap: () => onChanged(BrowserViewMode.list),
          ),
        ],
      ),
    );
  }
}

class _ViewSegment extends StatefulWidget {
  const _ViewSegment({required this.icon, required this.tooltip, required this.selected, required this.onTap});

  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_ViewSegment> createState() => _ViewSegmentState();
}

class _ViewSegmentState extends State<_ViewSegment> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = widget.selected;

    return Semantics(
      button: true,
      selected: selected,
      child: Tooltip(
        message: widget.tooltip,
        child: MouseRegion(
          cursor: selected ? SystemMouseCursors.basic : SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: selected ? null : widget.onTap,
            child: AnimatedContainer(
              duration: AppMotion.durationOf(context, AppMotion.state),
              curve: AppMotion.enter,
              width: AppSize.compact,
              height: AppSize.compact,
              decoration: BoxDecoration(
                color: selected
                    ? scheme.surface
                    : (_hovered ? scheme.onSurface.withValues(alpha: 0.06) : scheme.onSurface.withValues(alpha: 0)),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                boxShadow: selected ? scheme.shadowRaised : null,
              ),
              child: Icon(
                widget.icon,
                size: AppSize.iconMd,
                color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
