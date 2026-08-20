import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/image_metadata_service.dart';
import '../../../state/workbench_ui_state.dart';

/// The comparator's right-hand panel: the same four facts about each of the
/// two images, and what the pair adds up to.
///
/// Laid out to the design spec as label-left / value-right rows under a dotted
/// section heading, rather than the stacked label-over-value blocks it used to
/// draw — the two images are only comparable if their numbers line up in the
/// same column.
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
    _loadMetadata();
  }

  @override
  void dispose() {
    _workbenchUIState?.removeListener(_onWorkbenchUIStateChanged);
    super.dispose();
  }

  Future<void> _loadMetadata() async {
    final state = _workbenchUIState ?? Provider.of<WorkbenchUIState>(context, listen: false);

    if (state.comparatorRawPath == null && state.comparatorAfterPath == null) {
      if (mounted) {
        setState(() {
          _rawMeta = null;
          _afterMeta = null;
        });
      }
      return;
    }

    if (mounted) setState(() => _isLoading = true);

    final rawMeta = state.comparatorRawPath == null
        ? null
        : await ImageMetadataService().getMetadata(state.comparatorRawPath!);
    final afterMeta = state.comparatorAfterPath == null
        ? null
        : await ImageMetadataService().getMetadata(state.comparatorAfterPath!);

    if (mounted) {
      setState(() {
        _rawMeta = rawMeta;
        _afterMeta = afterMeta;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_rawMeta == null && _afterMeta == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.info_outline, size: 22, color: colorScheme.outlineVariant),
            const SizedBox(height: 10),
            Text(
              l10n.metadataSelectedNone,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.outline),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_rawMeta != null) ...[
            _SectionHeader(label: l10n.labelRaw, isAfter: false),
            ..._buildRows(_rawMeta!, l10n),
          ],
          if (_afterMeta != null) ...[
            if (_rawMeta != null) const SizedBox(height: 14),
            _SectionHeader(label: l10n.labelAfter, isAfter: true),
            ..._buildRows(_afterMeta!, l10n),
          ],
          if (_rawMeta != null && _afterMeta != null) ...[
            const SizedBox(height: 18),
            _SizeDeltaBox(raw: _rawMeta!, after: _afterMeta!, l10n: l10n),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildRows(ImageMetadata meta, AppLocalizations l10n) {
    final rows = <(String, String)>[
      if (meta.width > 0) (l10n.width, '${meta.width} px'),
      if (meta.height > 0) (l10n.height, '${meta.height} px'),
      if (meta.aspectRatio.isNotEmpty) (l10n.aspectRatio, meta.aspectRatio),
      (l10n.fileSize, meta.sizeString),
    ];

    return [
      for (var i = 0; i < rows.length; i++)
        _MetaRow(label: rows[i].$1, value: rows[i].$2, divided: i < rows.length - 1),
    ];
  }
}

/// A dotted heading naming which of the two images the rows below describe.
class _SectionHeader extends StatelessWidget {
  final String label;
  final bool isAfter;

  const _SectionHeader({required this.label, required this.isAfter});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // The result section takes the accent, the source stays neutral — the same
    // pairing the canvas badges and the footer chips use.
    final color = isAfter ? colorScheme.onAccentTint : colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: isAfter ? colorScheme.primary : colorScheme.outline,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                  color: color,
                ),
          ),
        ],
      ),
    );
  }
}

/// One "label … value" line. The value is monospaced so digits in the two
/// sections sit under each other.
class _MetaRow extends StatelessWidget {
  final String label;
  final String value;
  final bool divided;

  const _MetaRow({required this.label, required this.value, required this.divided});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: divided
          ? BoxDecoration(
              border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withAlpha(80))),
            )
          : null,
      child: Row(
        children: [
          Text(label, style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
          const Spacer(),
          SelectableText(
            value,
            // `.mono`, not `fontFamily: 'monospace'`. The bare generic is
            // whatever the engine falls back to — Courier New on Windows — and
            // it brings no tabular figures, so a column of dimensions still had
            // its digits at different widths. Lining those up down the column
            // is the one thing this panel exists for.
            style: textTheme.bodySmall?.mono.copyWith(
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

/// What the pair adds up to: how much lighter (or heavier) the result is.
///
/// The one fact on this panel that neither image carries on its own, and the
/// reason two of them are being read side by side.
class _SizeDeltaBox extends StatelessWidget {
  final ImageMetadata raw;
  final ImageMetadata after;
  final AppLocalizations l10n;

  const _SizeDeltaBox({required this.raw, required this.after, required this.l10n});

  @override
  Widget build(BuildContext context) {
    if (raw.fileSize <= 0) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    final delta = (after.fileSize - raw.fileSize) / raw.fileSize * 100;
    final shrank = delta <= 0;
    final percent = '${delta.abs().toStringAsFixed(1)}%';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        // `surface` on a `surfaceContainerLow` panel: a half-step up rather
        // than the step *down* `surfaceContainerHigh` became once the columns
        // moved. Same inversion the right panel's cards had — a summary that
        // reads as recessed rather than as the line the panel adds up to.
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colorScheme.surfaceContainerHigh),
      ),
      child: Row(
        children: [
          Icon(
            shrank ? Icons.arrow_downward : Icons.arrow_upward,
            size: 14,
            // The one accent on this panel, and `10n` spends it here: every
            // row above is a measurement, this is the one line that draws a
            // conclusion from them.
            color: colorScheme.onAccentTint,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              shrank ? l10n.comparatorSizeReduction(percent) : l10n.comparatorSizeIncrease(percent),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
