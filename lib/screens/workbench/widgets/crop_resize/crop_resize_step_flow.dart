part of 'crop_resize_toolbar.dart';

extension _StepFlow on _CropResizeToolbarState {
  /// The narrow step flow (`A4 · 1b`): what the slot shows when even the most
  /// degraded single row does not fit. The glass bar's own back button leads
  /// the row, so this starts at Aspect Ratio.
  Widget _buildStepFlow(
    BuildContext context,
    AppLocalizations l10n,
    WorkbenchUIState uiState,
    double width,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final busy = _processingAction != null;

    bool labels = true;
    bool saveLabel = true;
    double measure() {
      final parts = <double>[
        GlassIconButton.widthFor(context, label: labels ? l10n.aspectRatio : null),
        GlassIconButton.widthFor(context, label: labels ? l10n.resize : null),
        _kMinSpacer,
        saveLabel ? _TintedButton.widthFor(context, label: l10n.save, icon: true) : AppSize.control,
      ];
      return parts.fold<double>(0, (a, b) => a + b) + _kGap * (parts.length - 1);
    }

    if (measure() > width) labels = false;
    if (measure() > width) saveLabel = false;

    return Row(
      children: _spaced([
        GlassIconButton(
          icon: Icons.aspect_ratio,
          label: labels ? l10n.aspectRatio : null,
          tooltip: labels ? null : l10n.aspectRatio,
          onPressed: () => _showRatioSheet(context, l10n, uiState),
        ),
        GlassIconButton(
          icon: Icons.photo_size_select_large,
          label: labels ? l10n.resize : null,
          tooltip: labels ? null : l10n.resize,
          onPressed: () => _showResizeDialog(context, l10n, uiState),
        ),
        const Expanded(child: SizedBox()),
        MenuAnchor(
          menuChildren: [
            MenuItemButton(
              leadingIcon: const Icon(Icons.save_alt, size: AppSize.iconLg),
              onPressed: busy ? null : () => _handleSave(overwrite: false),
              child: Text(l10n.saveToTemp),
            ),
            MenuItemButton(
              leadingIcon: Icon(
                Icons.warning_amber_rounded,
                size: AppSize.iconLg,
                color: scheme.error,
              ),
              onPressed: busy ? null : () => _handleSave(overwrite: true),
              child: Text(l10n.overwriteSource, style: TextStyle(color: scheme.error)),
            ),
            const Divider(height: 9),
            MenuItemButton(
              leadingIcon: const Icon(Icons.restart_alt, size: AppSize.iconLg),
              onPressed: busy ? null : _handleReset,
              child: Text(l10n.reset),
            ),
          ],
          builder: (context, controller, _) => _TintedButton(
            icon: Icons.save_outlined,
            label: l10n.save,
            showLabel: saveLabel,
            tooltip: saveLabel ? null : l10n.save,
            loading: busy,
            onPressed: busy
                ? null
                : () => controller.isOpen ? controller.close() : controller.open(),
          ),
        ),
      ]),
    );
  }

  /// The step flow's ratio sheet (`1b` 「比例表」). Custom stays on the wide
  /// bar, where its X:Y fields have room.
  void _showRatioSheet(BuildContext context, AppLocalizations l10n, WorkbenchUIState uiState) {
    final current = _currentPreset(uiState.cropAspectRatio);
    final options = <(_RatioPreset, String)>[
      (_RatioPreset.free, l10n.cropResizeFreeRatio),
      (_RatioPreset.r1x1, '1:1'),
      (_RatioPreset.r4x3, '4:3'),
      (_RatioPreset.r16x9, '16:9'),
      (_RatioPreset.r3x4, '3:4'),
      (_RatioPreset.r9x16, '9:16'),
    ];

    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        final textTheme = Theme.of(sheetContext).textTheme;
        final scheme = Theme.of(sheetContext).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.s10,
              AppSpace.s6,
              AppSpace.s10,
              AppSpace.s10,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                  child: Text(l10n.aspectRatio, style: textTheme.titleLarge),
                ),
                for (final (preset, label) in options)
                  ListTile(
                    selected: preset == current,
                    title: Text(
                      label,
                      style: preset == _RatioPreset.free
                          ? textTheme.bodyMedium!.metricsOnly
                          : textTheme.bodyMedium!.metricsOnly.mono,
                    ),
                    trailing: preset == current
                        ? Icon(Icons.check, size: AppSize.iconMd, color: scheme.primary)
                        : null,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _selectRatioPreset(preset);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// The step flow's resize dialog (`1b` 「调整尺寸」): the two fields with the
  /// link between them, the aspect toggle, the resampler. The fields are the
  /// bar's own controllers, so what is typed here is live.
  void _showResizeDialog(BuildContext context, AppLocalizations l10n, WorkbenchUIState uiState) {
    final meta = _meta;
    AppDialog.show<void>(
      context,
      title: l10n.resize,
      subtitle: meta != null && meta.width > 0
          ? l10n.cropResizeOriginalInfo(meta.width, meta.height, meta.sizeString)
          : null,
      maxWidth: 380,
      content: ListenableBuilder(
        listenable: uiState,
        builder: (context, _) {
          final scheme = Theme.of(context).colorScheme;
          final textTheme = Theme.of(context).textTheme;
          final maintain = uiState.maintainAspectRatio;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: _DialogNumberField(controller: _widthController, label: l10n.width),
                  ),
                  const SizedBox(width: AppSpace.s6),
                  Tooltip(
                    message: l10n.maintainAspectRatio,
                    child: Semantics(
                      button: true,
                      toggled: maintain,
                      label: l10n.maintainAspectRatio,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () => uiState.setMaintainAspectRatio(!maintain),
                          child: Container(
                            width: AppSize.large,
                            height: AppSize.large,
                            decoration: BoxDecoration(
                              color: maintain ? scheme.accentTint : Colors.transparent,
                              borderRadius: BorderRadius.circular(AppRadius.control),
                            ),
                            child: Icon(
                              maintain ? Icons.link : Icons.link_off,
                              size: AppSize.iconMd,
                              color: maintain ? scheme.primary : scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpace.s6),
                  Expanded(
                    child: _DialogNumberField(controller: _heightController, label: l10n.height),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.s10),
              AppToggleRow(
                title: l10n.maintainAspectRatio,
                value: maintain,
                onChanged: uiState.setMaintainAspectRatio,
              ),
              const Divider(),
              Row(
                children: [
                  Expanded(child: Text(l10n.cropResizeResample, style: textTheme.bodyMedium)),
                  SizedBox(
                    width: 140,
                    child: AppDropdown<String>(
                      size: AppFieldSize.regular,
                      height: appButtonMinHeight,
                      value: uiState.samplingMethod,
                      items: [
                        for (final entry in _kSamplingLabels.entries)
                          AppDropdownItem(value: entry.key, label: entry.value),
                      ],
                      onChanged: (v) {
                        if (v != null) uiState.setSamplingMethod(v);
                      },
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
      actions: [
        AppButton(
          label: l10n.close,
          variant: AppButtonVariant.text,
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }
}
