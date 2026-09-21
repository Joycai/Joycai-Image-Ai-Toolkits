part of 'video_config_panel.dart';

/// Pairs cells into rows of two, in order. A cell that spans the row, or a
/// half left without a partner, takes the full width.
Widget _paramGrid(List<_ParamCell> cells) {
  final rows = <Widget>[];
  _ParamCell? pending;
  for (final cell in cells) {
    if (cell.spansRow) {
      if (pending != null) {
        rows.add(pending);
        pending = null;
      }
      rows.add(cell);
    } else if (pending == null) {
      pending = cell;
    } else {
      rows.add(Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: pending),
          const SizedBox(width: _kParamGap),
          Expanded(child: cell),
        ],
      ));
      pending = null;
    }
  }
  if (pending != null) rows.add(pending);

  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final (index, row) in rows.indexed) ...[
        if (index > 0) const SizedBox(height: _kParamGap),
        row,
      ],
    ],
  );
}

/// One control per parameter the selected model declares (`A2 · 1a` grid).
/// The parameters come from the model; nothing here names one.
extension _ParamControls on _VideoConfigPanelState {
  Widget _buildVideoParamControl(
    ParamSpec spec,
    LLMModel model,
    AppState appState,
    AppLocalizations l10n,
  ) {
    final theme = Theme.of(context);
    final current = appState.getVideoParam(model, spec);
    switch (spec.control) {
      case ParamControl.dropdown:
        return AppDropdown<String>(
          size: AppFieldSize.regular,
          height: _kParamControlHeight,
          value: current,
          items: [
            for (final o in spec.options)
              AppDropdownItem(value: o.value, label: _videoOptionLabel(l10n, spec.key, o.value)),
          ],
          onChanged: (v) {
            if (v != null) appState.setVideoParam(model, spec.key, v);
          },
        );
      case ParamControl.segmented:
        // `1a` 「质量」: equal shares on the track, the chosen one lifted out
        // on the panel's ground.
        return AppSegmentedControl<String>(
          segments: spec.options
              .map((o) => AppSegment(
                    value: o.value,
                    label: _videoOptionLabel(l10n, spec.key, o.value),
                  ))
              .toList(),
          value: current,
          onChanged: (v) => appState.setVideoParam(model, spec.key, v),
          compact: true,
          expand: true,
          style: AppSegmentStyle.raised,
        );
      case ParamControl.customSize:
        // Not currently used by any video family — filtered out of the grid.
        return const SizedBox.shrink();
      case ParamControl.slider:
        final lo = spec.min ?? 1;
        final hi = spec.max ?? 15;
        final parsed = int.tryParse(current) ?? int.tryParse(spec.defaultValue) ?? lo;
        final value = parsed < lo ? lo : (parsed > hi ? hi : parsed);
        return SizedBox(
          height: _kParamControlHeight,
          child: Row(
            children: [
              Expanded(
                child: SliderTheme(
                  // Material's 24px overlay would otherwise decide the row's
                  // height instead of the grid's control height.
                  data: SliderTheme.of(context).copyWith(
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                  ),
                  child: Slider(
                    value: value.toDouble(),
                    min: lo.toDouble(),
                    max: hi.toDouble(),
                    divisions: hi - lo,
                    label: '${value}s',
                    onChanged: (v) => appState.setVideoParam(model, spec.key, v.round().toString()),
                  ),
                ),
              ),
              SizedBox(
                width: 30,
                child: Text(
                  '${value}s',
                  textAlign: TextAlign.end,
                  style: theme.textTheme.labelSmall?.mono.copyWith(color: theme.colorScheme.onSurface),
                ),
              ),
            ],
          ),
        );
    }
  }

  String _videoParamLabel(AppLocalizations l10n, String labelKey) {
    switch (labelKey) {
      case 'videoSeconds':
        return l10n.videoSeconds;
      case 'quality':
        return l10n.quality;
      case 'aspectRatio':
        return l10n.aspectRatio;
      case 'resolution':
        return l10n.resolution;
      default:
        return labelKey;
    }
  }

  String _videoOptionLabel(AppLocalizations l10n, String paramKey, String value) {
    if (value == 'not_set') return l10n.optionAuto;
    if (paramKey == 'videoQuality') {
      switch (value) {
        case 'standard':
          return l10n.videoQualityStandard;
        case 'high':
          return l10n.videoQualityHigh;
      }
    }
    if (paramKey == 'seconds') return '${value}s';
    return value;
  }
}

/// One cell of the parameter grid: an 11px secondary caption over its control.
class _ParamCell extends StatelessWidget {
  const _ParamCell({required this.label, required this.control, this.spansRow = false});

  final String label;
  final Widget control;

  /// A slider, or a segmented track with more than two options, needs the
  /// whole row rather than half of it.
  final bool spansRow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpace.s4),
          control,
        ],
      ),
    );
  }
}
