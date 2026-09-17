part of '../crop_resize_toolbar.dart';

extension _WideRow on _CropResizeToolbarState {
  /// Steps [f] down until the row fits [width], and reports whether it does.
  bool _fitRow(BuildContext context, _Fit f, double width, {required String? info, required String samplingLabel}) {
    double measure() => _measureRow(
          context,
          f,
          info: info,
          customMode: _customRatioMode,
          samplingLabel: samplingLabel,
        );

    final steps = <VoidCallback>[
      // 1 · decoration.
      () => f.info = false,
      () => f.samplingName = false,
      // 2 · labels. The subtitle is the two-line button folding to one, which
      // the spec files here; the action labels go last — telling copy from
      // overwrite is the whole point of the bar.
      () => f.saveSubtitle = false,
      () => f.portraitPresets = false,
      () => f.ratioWords = false,
      () => f.resetLabel = false,
      () => f.overwriteLabel = false,
      // 3 · the ⋮ menu.
      () => f.folded = true,
    ];
    for (final step in steps) {
      if (measure() <= width) return true;
      step();
    }
    return measure() <= width;
  }

  Widget _buildSlot(BuildContext context, WorkbenchUIState uiState, double width) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final ink2 = GlassInk.maybeOf(context)?.ink2 ?? scheme.onSurfaceVariant;
    final source = uiState.cropResizeSourceImage;
    final meta = _meta;
    final info = source != null && meta != null && meta.width > 0
        ? l10n.cropResizeOriginalInfo(meta.width, meta.height, meta.sizeString)
        : null;
    final samplingLabel = _kSamplingLabels[uiState.samplingMethod] ?? uiState.samplingMethod;

    final f = _Fit()..saveSubtitle = _saveSubtitleFitsHeight(context);
    if (!_fitRow(context, f, width, info: info, samplingLabel: samplingLabel)) {
      return _buildStepFlow(context, l10n, uiState, width);
    }

    final busy = _processingAction != null;
    final children = <Widget>[
      if (f.info && info != null) ...[
        Text(info, maxLines: 1, softWrap: false, style: _infoStyle(context).copyWith(color: ink2)),
        const GlassDivider(),
      ],
      GlassSegmented<_RatioPreset>(
        segments: _ratioSegments(l10n, portrait: f.portraitPresets, icons: !f.ratioWords),
        value: _currentPreset(uiState.cropAspectRatio),
        onChanged: _selectRatioPreset,
        showLabels: f.ratioWords,
      ),
      if (_customRatioMode) _buildCustomRatioFields(context),
      _buildSizeGroup(context, l10n, uiState),
      if (!f.folded)
        MenuAnchor(
          menuChildren: _samplingMenuItems(context, uiState),
          builder: (context, controller, _) => _GlassMenuButton(
            label: f.samplingName ? samplingLabel : null,
            icon: Icons.grain,
            tooltip: l10n.cropResizeResample,
            open: controller.isOpen,
            onPressed: () => controller.isOpen ? controller.close() : controller.open(),
          ),
        ),
      const Expanded(child: SizedBox()),
      if (f.folded)
        _buildOverflowMenu(context, l10n, uiState, busy)
      else ...[
        // Ghost text: reset must not read as a peer of the two actions that
        // write a file.
        GlassIconButton(
          icon: f.resetLabel ? null : Icons.restart_alt,
          label: f.resetLabel ? l10n.reset : null,
          tooltip: f.resetLabel ? null : l10n.reset,
          onPressed: busy ? null : _handleReset,
        ),
        // The destructive action is named and red, and quieter than the safe
        // one beside it: text, never a fill.
        _Spinning(
          on: _processingAction == 'overwrite',
          color: scheme.error,
          child: GlassIconButton(
            icon: f.overwriteLabel ? null : Icons.warning_amber_rounded,
            label: f.overwriteLabel ? l10n.overwriteSource : null,
            tooltip: f.overwriteLabel ? null : l10n.overwriteSource,
            danger: true,
            onPressed: busy ? null : () => _handleSave(overwrite: true),
          ),
        ),
      ],
      // Never gives way.
      _TintedButton(
        label: l10n.saveCopy,
        subtitle: f.saveSubtitle ? l10n.cropResizeSaveDestinationHint : null,
        tooltip: f.saveSubtitle ? null : l10n.saveToTemp,
        loading: _processingAction == 'save',
        onPressed: busy ? null : () => _handleSave(overwrite: false),
      ),
    ];

    return Row(children: _spaced(children));
  }

  /// Width, the aspect link, height (`1a`: 72×32 inputs on the glass edge,
  /// mono values, a 28px lens between them that is the accent when on).
  ///
  /// The link sits between the two fields, not after both — it is the control
  /// that links them.
  Widget _buildSizeGroup(BuildContext context, AppLocalizations l10n, WorkbenchUIState uiState) {
    final maintain = uiState.maintainAspectRatio;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _GlassNumberField(controller: _widthController, label: l10n.width, width: _kFieldWidth),
        const SizedBox(width: _kFieldGap),
        GlassIconButton(
          icon: maintain ? Icons.link : Icons.link_off,
          size: _kLinkSize,
          active: maintain,
          tooltip: l10n.maintainAspectRatio,
          onPressed: () => uiState.setMaintainAspectRatio(!maintain),
        ),
        const SizedBox(width: _kFieldGap),
        _GlassNumberField(controller: _heightController, label: l10n.height, width: _kFieldWidth),
      ],
    );
  }

  /// Only rendered once the "Custom" segment is selected — folded away
  /// otherwise instead of permanently occupying toolbar width.
  Widget _buildCustomRatioFields(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final glass = GlassInk.maybeOf(context);
    final edge = glass?.edge ?? scheme.outlineVariant;
    final ink2 = glass?.ink2 ?? scheme.onSurfaceVariant;

    return Container(
      width: _kCustomFieldsWidth,
      height: AppSize.control,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: edge),
      ),
      child: Row(
        children: [
          Expanded(child: _BareNumberField(controller: _ratioXController, textAlign: TextAlign.center)),
          Text(':', style: _valueStyle(context).copyWith(color: ink2)),
          Expanded(child: _BareNumberField(controller: _ratioYController, textAlign: TextAlign.center)),
        ],
      ),
    );
  }

  List<Widget> _samplingMenuItems(BuildContext context, WorkbenchUIState uiState) {
    final scheme = Theme.of(context).colorScheme;
    return [
      for (final entry in _kSamplingLabels.entries)
        MenuItemButton(
          leadingIcon: Icon(
            Icons.check,
            size: AppSize.iconMd,
            color: entry.key == uiState.samplingMethod ? scheme.primary : Colors.transparent,
          ),
          onPressed: () => uiState.setSamplingMethod(entry.key),
          child: Text(entry.value),
        ),
    ];
  }

  /// Step 3: reset, overwrite and the resampler behind one ⋮.
  Widget _buildOverflowMenu(
    BuildContext context,
    AppLocalizations l10n,
    WorkbenchUIState uiState,
    bool busy,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return MenuAnchor(
      menuChildren: [
        SubmenuButton(
          leadingIcon: const Icon(Icons.grain, size: AppSize.iconLg),
          menuChildren: _samplingMenuItems(context, uiState),
          child: Text(l10n.cropResizeResample),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.restart_alt, size: AppSize.iconLg),
          onPressed: busy ? null : _handleReset,
          child: Text(l10n.reset),
        ),
        const Divider(height: 9),
        MenuItemButton(
          leadingIcon: Icon(Icons.warning_amber_rounded, size: AppSize.iconLg, color: scheme.error),
          onPressed: busy ? null : () => _handleSave(overwrite: true),
          child: Text(l10n.overwriteSource, style: TextStyle(color: scheme.error)),
        ),
      ],
      builder: (context, controller, _) => _Spinning(
        on: _processingAction == 'overwrite',
        color: scheme.error,
        child: GlassIconButton(
          icon: Icons.more_vert,
          tooltip: l10n.more,
          active: controller.isOpen,
          onPressed: () => controller.isOpen ? controller.close() : controller.open(),
        ),
      ),
    );
  }
}
