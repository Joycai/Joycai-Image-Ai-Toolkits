import 'package:flutter/material.dart';

import '../../../core/app_semantic_colors.dart';
import '../../../core/app_theme.dart';
import '../../../core/constants.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/browser_file.dart';
import '../../../services/image_metadata_service.dart';
import '../../../widgets/drag/app_drag_session.dart';
import 'browser_drag_chip.dart';

/// The ground and glyph colour of a file type's icon plate (`B1a · 1b`):
/// image info · video error · audio warning · text success · other track.
///
/// These are the type's identity and do not follow the accent.
({Color background, Color foreground}) browserFileTypeColors(BuildContext context, FileCategory category) {
  final scheme = Theme.of(context).colorScheme;
  final semantic = context.semantic;
  return switch (category) {
    FileCategory.image => (background: semantic.infoContainer, foreground: semantic.info),
    FileCategory.video => (background: scheme.errorContainer, foreground: scheme.error),
    FileCategory.audio => (background: semantic.warningContainer, foreground: semantic.warning),
    FileCategory.text => (background: semantic.successContainer, foreground: semantic.success),
    FileCategory.all || FileCategory.other => (
        background: scheme.surfaceContainerHighest,
        foreground: scheme.onSurfaceVariant,
      ),
  };
}

/// One row of the list view — `B1a · 1b`.
///
/// Opaque on the column colour, unlike the grid: the row carries a check, a
/// staging mark and a three-part mono subtitle, and translucency would leave
/// that subtitle unreadable over the backdrop. 56 tall with a hairline under
/// it; selected rows take the 12% wash and the name the deep ink.
class BrowserFileListRow extends StatefulWidget {
  const BrowserFileListRow({
    super.key,
    required this.file,
    required this.isSelected,
    required this.isStaged,
    required this.onTap,
    this.onDoubleTap,
    required this.onSecondaryTap,
    this.dragPayload = const [],
  });

  static const double height = 56;

  final BrowserFile file;
  final bool isSelected;
  final bool isStaged;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;
  final ValueChanged<Offset> onSecondaryTap;

  /// What dragging this row carries — the whole selection when the row is
  /// part of it, this one file otherwise. Empty disables dragging.
  final List<BrowserFile> dragPayload;

  @override
  State<BrowserFileListRow> createState() => _BrowserFileListRowState();
}

class _BrowserFileListRowState extends State<BrowserFileListRow> {
  bool _hovered = false;

  /// This row's files are being dragged.
  bool _dragging = false;

  void _dragStarted() {
    setState(() => _dragging = true);
    AppDragSession.begin(widget.dragPayload);
  }

  /// Wired to every end callback: `onDragEnd` is skipped once the row has
  /// been unmounted — a drop that moved its file away — and the session must
  /// end regardless.
  void _dragEnded() {
    if (mounted && _dragging) setState(() => _dragging = false);
    AppDragSession.end();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final selected = widget.isSelected;
    final plate = browserFileTypeColors(context, widget.file.category);

    final Color ground = selected
        ? Color.alphaBlend(scheme.accentTint, scheme.surfaceContainerLow)
        : _hovered
            ? Color.alphaBlend(scheme.onSurface.withValues(alpha: 0.04), scheme.surfaceContainerLow)
            : scheme.surfaceContainerLow;

    final row = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onDoubleTap: widget.onDoubleTap,
      onSecondaryTapDown: (details) => widget.onSecondaryTap(details.globalPosition),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: AppMotion.durationOf(context, AppMotion.hover),
          curve: AppMotion.quick,
          height: BrowserFileListRow.height,
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.s16),
          decoration: BoxDecoration(
            color: ground,
            border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: plate.background,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(widget.file.icon, size: AppSize.iconLg, color: plate.foreground),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.file.name,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall!.mono.copyWith(
                        color: selected ? scheme.onAccentTint : scheme.onSurface,
                        fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 2),
                    _ListRowSubtitle(file: widget.file),
                  ],
                ),
              ),
              if (widget.isStaged) ...[
                const SizedBox(width: 12),
                const _StagedBadge(),
              ],
              const SizedBox(width: 12),
              _SelectionCircle(selected: selected),
            ],
          ),
        ),
      ),
    );

    if (widget.dragPayload.isEmpty) return row;

    return Draggable<List<BrowserFile>>(
      data: widget.dragPayload,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: BrowserFileDragChip(count: widget.dragPayload.length),
      onDragStarted: _dragStarted,
      onDragEnd: (_) => _dragEnded(),
      onDragCompleted: _dragEnded,
      onDraggableCanceled: (_, _) => _dragEnded(),
      // `00d`: dragged out of the list, the row stays where it is at half
      // strength — it may not move at all, and a list that reflows mid-drag
      // loses the folder the user was aiming at. An Opacity in place rather
      // than `childWhenDragging`, so the row keeps its state.
      child: Opacity(opacity: _dragging ? 0.5 : 1, child: row),
    );
  }
}

/// `8.2 MB | 2026-09-11 14:02 | 4000×3000 (4:3)` — mono 11 in the secondary
/// ink. The dimensions arrive later, read from the file's header.
class _ListRowSubtitle extends StatefulWidget {
  const _ListRowSubtitle({required this.file});

  final BrowserFile file;

  @override
  State<_ListRowSubtitle> createState() => _ListRowSubtitleState();
}

class _ListRowSubtitleState extends State<_ListRowSubtitle> {
  String _dimensions = '';

  @override
  void initState() {
    super.initState();
    if (widget.file.category == FileCategory.image) _loadDimensions();
  }

  @override
  void didUpdateWidget(_ListRowSubtitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.file.path != oldWidget.file.path) {
      _dimensions = '';
      if (widget.file.category == FileCategory.image) _loadDimensions();
    }
  }

  Future<void> _loadDimensions() async {
    final path = widget.file.path;
    final metadata = await ImageMetadataService().getMetadata(path);
    if (metadata != null && mounted && widget.file.path == path) {
      setState(() {
        _dimensions = ' | ${metadata.width}×${metadata.height} (${metadata.aspectRatio})';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = AppConstants.formatFileSize(widget.file.size);
    final modified = widget.file.modified.toString().substring(0, 16);
    return Text(
      '$size | $modified$_dimensions',
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.labelSmall!.mono.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w400,
          ),
    );
  }
}

/// The staging mark on an opaque row: track under the secondary ink. The
/// grid's version sits on a photograph and takes the image plate instead.
class _StagedBadge extends StatelessWidget {
  const _StagedBadge();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_outlined, size: 12, color: scheme.onSurfaceVariant),
          const SizedBox(width: AppSpace.s4),
          Text(
            l10n.stagedBadge,
            maxLines: 1,
            style: Theme.of(context).textTheme.labelSmall!.mono.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w400,
                ),
          ),
        ],
      ),
    );
  }
}

/// A 20px check: the accent solid under its ink when selected, a 1.5px
/// hairline ring when not.
class _SelectionCircle extends StatelessWidget {
  const _SelectionCircle({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: AppMotion.durationOf(context, AppMotion.hover),
      curve: AppMotion.quick,
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? scheme.primary : Colors.transparent,
        border: Border.all(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: 1.5,
        ),
      ),
      child: selected ? Icon(Icons.check, size: AppSize.iconSm, color: scheme.onPrimary) : null,
    );
  }
}
