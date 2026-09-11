import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_semantic_colors.dart';
import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/image_metadata_service.dart';
import '../../../state/app_state.dart';
import '../../../state/workbench_ui_state.dart';

/// The comparator's right-hand column (`A5 · 1c`): the same four facts about
/// each of the two images, what the pair adds up to, and where to pick another.
///
/// Cards laid in the column (panel ground, hairline, r16) on the column ground
/// the host already paints. Label-left / value-right rows with the value in
/// mono, so the two images' numbers line up in the same column.
class MetadataInspector extends StatefulWidget {
  final ScrollController? scrollController;
  const MetadataInspector({super.key, this.scrollController});

  @override
  State<MetadataInspector> createState() => _MetadataInspectorState();
}

class _MetadataInspectorState extends State<MetadataInspector> {
  ImageMetadata? _rawMeta;
  ImageMetadata? _afterMeta;
  bool _isLoading = false;
  WorkbenchUIState? _workbenchUIState;

  /// The pair of paths the last load was started for. A change to the layout
  /// or the sync switch notifies the same state, and re-reading both files for
  /// it flashed the spinner over numbers that had not changed.
  String? _requestedRaw;
  String? _requestedAfter;
  bool _requested = false;

  @override
  void initState() {
    super.initState();
    _loadMetadata();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_workbenchUIState == null) {
      _workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);
      _workbenchUIState!.addListener(_onWorkbenchUIStateChanged);
    }
  }

  void _onWorkbenchUIStateChanged() {
    final state = _workbenchUIState!;
    if (_requested &&
        state.comparatorRawPath == _requestedRaw &&
        state.comparatorAfterPath == _requestedAfter) {
      return;
    }
    _loadMetadata();
  }

  @override
  void dispose() {
    _workbenchUIState?.removeListener(_onWorkbenchUIStateChanged);
    super.dispose();
  }

  Future<void> _loadMetadata() async {
    final state = _workbenchUIState ?? Provider.of<WorkbenchUIState>(context, listen: false);
    final rawPath = state.comparatorRawPath;
    final afterPath = state.comparatorAfterPath;
    _requested = true;
    _requestedRaw = rawPath;
    _requestedAfter = afterPath;

    if (rawPath == null && afterPath == null) {
      if (mounted) {
        setState(() {
          _rawMeta = null;
          _afterMeta = null;
          _isLoading = false;
        });
      }
      return;
    }

    if (mounted) setState(() => _isLoading = true);

    final service = ImageMetadataService();
    final rawMeta = rawPath == null ? null : await service.getMetadata(rawPath);
    final afterMeta = afterPath == null ? null : await service.getMetadata(afterPath);

    // A newer pair was asked for while these were being read.
    if (rawPath != _requestedRaw || afterPath != _requestedAfter) return;

    if (mounted) {
      setState(() {
        _rawMeta = rawMeta;
        _afterMeta = afterMeta;
        _isLoading = false;
      });
    }
  }

  void _openLibrary() {
    final appState = Provider.of<AppState>(context, listen: false);
    // Leave the sheet or drawer this column was opened in first: the gallery
    // tab has a right panel of its own, and it would come up already open.
    if (widget.scrollController != null) {
      // Only the phone sheet (a modal route) hands a controller in.
      Navigator.of(context).maybePop();
    } else {
      final scaffold = Scaffold.maybeOf(context);
      if (scaffold != null && scaffold.isEndDrawerOpen) scaffold.closeEndDrawer();
    }
    appState.setWorkbenchTab(0);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final hasAny = _rawMeta != null || _afterMeta != null;

    final Widget content;
    if (_isLoading && !hasAny) {
      content = const Padding(
        padding: EdgeInsets.all(AppSpace.s22),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (!hasAny) {
      content = _Card(
        child: Text(
          l10n.metadataSelectedNone,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
      );
    } else {
      final cards = <Widget>[
        if (_rawMeta != null) _MetaCard(caption: l10n.labelRaw, rows: _rows(_rawMeta!, l10n)),
        if (_afterMeta != null) _MetaCard(caption: l10n.labelAfter, rows: _rows(_afterMeta!, l10n)),
        if (_rawMeta != null && _afterMeta != null && _rawMeta!.fileSize > 0)
          _SizeDeltaCard(raw: _rawMeta!, after: _afterMeta!),
        _PickCard(onPick: _openLibrary),
      ];
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpace.s10),
            cards[i],
          ],
        ],
      );
    }

    // Always a scrollable, so the phone sheet's controller has something to
    // drive in every state.
    return SingleChildScrollView(
      controller: widget.scrollController,
      padding: const EdgeInsets.all(AppSpace.s10),
      child: content,
    );
  }

  List<(String, String)> _rows(ImageMetadata meta, AppLocalizations l10n) => [
        if (meta.width > 0) (l10n.width, '${meta.width} px'),
        if (meta.height > 0) (l10n.height, '${meta.height} px'),
        if (meta.aspectRatio.isNotEmpty) (l10n.aspectRatio, meta.aspectRatio),
        (l10n.fileSize, meta.sizeString),
      ];
}

/// A card laid in the column: panel ground, hairline, r16, 10 inside.
class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpace.s10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: child,
    );
  }
}

/// The 11/500 tracked caption in the deep ink.
class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w500,
            letterSpacing: AppType.trackedLabelSpacing,
            color: Theme.of(context).colorScheme.onAccentTint,
          ),
    );
  }
}

/// One image's facts under its role caption.
class _MetaCard extends StatelessWidget {
  const _MetaCard({required this.caption, required this.rows});

  final String caption;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Caption(caption),
          for (final row in rows) ...[
            const SizedBox(height: 8),
            _MetaRow(label: row.$1, value: row.$2),
          ],
        ],
      ),
    );
  }
}

/// One "label … value" line. The value is monospaced so digits in the two
/// cards sit under each other.
class _MetaRow extends StatelessWidget {
  final String label;
  final String value;

  const _MetaRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(width: AppSpace.s10),
        SelectableText(
          value,
          // `.mono`, not `fontFamily: 'monospace'`. The bare generic is
          // whatever the engine falls back to — Courier New on Windows — and
          // it brings no tabular figures, so a column of dimensions still had
          // its digits at different widths. Lining those up down the column
          // is the one thing this panel exists for.
          style: textTheme.bodySmall?.mono.copyWith(color: colorScheme.onSurface),
        ),
      ],
    );
  }
}

/// What the pair adds up to: how much lighter (or heavier) the result is.
///
/// Success ink when the result is smaller, warning ink when it grew — the one
/// line on this column that draws a conclusion rather than stating a
/// measurement.
class _SizeDeltaCard extends StatelessWidget {
  const _SizeDeltaCard({required this.raw, required this.after});

  final ImageMetadata raw;
  final ImageMetadata after;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final semantic = AppSemanticColors.of(context);
    final textTheme = Theme.of(context).textTheme;

    final delta = (after.fileSize - raw.fileSize) / raw.fileSize * 100;
    final shrank = delta <= 0;
    final percent = '${delta.abs().toStringAsFixed(1)}%';
    final sentence = shrank ? l10n.comparatorSizeReduction(percent) : l10n.comparatorSizeIncrease(percent);
    final statusInk = shrank ? semantic.onSuccessContainer : semantic.onWarningContainer;

    // The figure is set apart in mono at 600 (`A5 · 1c`); the sentence around
    // it is whatever the locale wraps the placeholder in.
    final base = textTheme.bodySmall?.copyWith(color: colorScheme.onSurface);
    final figure = textTheme.bodySmall?.mono.copyWith(color: statusInk, fontWeight: FontWeight.w600);
    final at = sentence.indexOf(percent);
    final InlineSpan span = at < 0
        ? TextSpan(text: sentence, style: base?.copyWith(color: statusInk))
        : TextSpan(
            style: base,
            children: [
              TextSpan(text: sentence.substring(0, at)),
              TextSpan(text: percent, style: figure),
              TextSpan(text: sentence.substring(at + percent.length)),
            ],
          );

    return _Card(
      child: Row(
        children: [
          Icon(
            shrank ? Icons.trending_down : Icons.trending_up,
            size: AppSize.iconMd,
            color: shrank ? semantic.success : semantic.warning,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text.rich(span)),
        ],
      ),
    );
  }
}

/// Where to pick another image for either side (`A5 · 1c`). The comparator is
/// filled from an image's context menu in the gallery, so both go there.
class _PickCard extends StatelessWidget {
  const _PickCard({required this.onPick});

  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Caption(l10n.selectFromLibrary),
          const SizedBox(height: AppSpace.s6),
          Row(
            children: [
              Expanded(child: _OutlineAction(label: l10n.comparatorPickRaw, onPressed: onPick)),
              const SizedBox(width: AppSpace.s6),
              Expanded(child: _OutlineAction(label: l10n.comparatorPickAfter, onPressed: onPick)),
            ],
          ),
        ],
      ),
    );
  }
}

/// A 32px hairline-outlined action with its label in the deep ink.
class _OutlineAction extends StatelessWidget {
  const _OutlineAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          height: AppSize.control,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.s6),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onAccentTint,
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
