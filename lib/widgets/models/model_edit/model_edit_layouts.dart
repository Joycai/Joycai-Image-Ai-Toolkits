part of '../model_edit_dialog.dart';

/// The three forms of one state (`1a` dialog, `1e` phone page, `1e` add
/// dialog), their heading, footer and bar, and the column arrangements.
extension _Layouts on _ModelEditDialogState {
  /// `1a`: the 840 dialog.
  Widget _buildEditDialog(BuildContext context) {
    return AppDialog(
      maxWidth: _ModelEditDialogState._dialogWidth,
      maxHeight: 880,
      scrollable: true,
      dividedHeading: true,
      titleWidget: _editHeading(context),
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.s22, vertical: 20),
      content: ModelEditFieldScope(
        metrics: ModelEditMetrics.desktop,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final twoColumns =
                constraints.maxWidth >=
                _ModelEditDialogState._minColumnWidth * 2 + _ModelEditDialogState._columnGap;
            return twoColumns ? _twoColumns(context) : _singleColumn(context, pairFields: true);
          },
        ),
      ),
      actionsOverride: _editFooter(context),
    );
  }

  /// `1e`: the phone page. The bar is the screen's one glass layer; the form
  /// scrolls under it.
  Widget _buildPhonePage(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final insets = MediaQuery.paddingOf(context);

    return Dialog.fullscreen(
      backgroundColor: scheme.surfaceContainerLow,
      child: ModelEditFieldScope(
        metrics: ModelEditMetrics.phoneForm,
        child: Builder(
          builder: (context) => Stack(
            children: [
              Positioned.fill(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    12,
                    insets.top +
                        _ModelEditDialogState._phoneBarHeight +
                        _ModelEditDialogState._sectionGap,
                    12,
                    insets.bottom + _ModelEditDialogState._sectionGap,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _singleColumn(context, pairFields: false),
                      const SizedBox(height: _ModelEditDialogState._sectionGap),
                      AppButton(
                        label: widget.l10n.deleteModel,
                        icon: Icons.delete_outline,
                        variant: AppButtonVariant.destructiveText,
                        onPressed: _confirmDelete,
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(top: 0, left: 0, right: 0, child: _phoneBar(context)),
            ],
          ),
        ),
      ),
    );
  }

  /// `1e` right: the 520 add dialog. Channel is asked only when the caller
  /// did not open it from one.
  Widget _buildAddDialog(BuildContext context, {required bool phone}) {
    final l10n = widget.l10n;

    return AppDialog(
      maxWidth: _ModelEditDialogState._addDialogWidth,
      maxHeight: 680,
      scrollable: true,
      icon: Icons.add,
      title: l10n.addModel,
      subtitle: l10n.addModelSubtitle,
      content: ModelEditFieldScope(
        metrics: phone ? ModelEditMetrics.phoneDialog : ModelEditMetrics.desktop,
        child: Builder(
          builder: (context) {
            final size = _fieldSize(context);
            final name = _nameField(size);
            final channel = widget.preChannelId == null ? _channelField(size) : null;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _kindSegmentedControl(context),
                const SizedBox(height: _ModelEditDialogState._fieldGap),
                _idField(size, autofocus: true, helper: l10n.addModelIdHelper),
                const SizedBox(height: AppSpace.s6),
                _presetBar(context),
                const SizedBox(height: _ModelEditDialogState._fieldGap),
                if (channel == null)
                  name
                else if (phone) ...[
                  name,
                  const SizedBox(height: _ModelEditDialogState._fieldGap),
                  channel,
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: name),
                      const SizedBox(width: _ModelEditDialogState._fieldGap),
                      Expanded(child: channel),
                    ],
                  ),
                if (_isChatGroup) ...[
                  const SizedBox(height: _ModelEditDialogState._fieldGap),
                  ModelEditCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.s10,
                      vertical: AppSpace.s4,
                    ),
                    child: ModelEditToggleRow(
                      title: l10n.supportsMultimodalInput,
                      value: _isMultimodal,
                      onChanged: _setMultimodal,
                    ),
                  ),
                ],
                const SizedBox(height: _ModelEditDialogState._sectionGap),
                // Everything else starts on Auto or its default; say so, so the
                // missing controls read as deferred rather than absent.
                ModelEditNotice(tone: ModelEditTone.info, text: l10n.addModelDefaultsNote),
              ],
            );
          },
        ),
      ),
      actions: [
        AppButton(
          label: l10n.cancel,
          variant: AppButtonVariant.text,
          onPressed: () => Navigator.pop(context),
        ),
        AppButton(label: l10n.add, onPressed: _canSave ? _save : null),
      ],
    );
  }

  // --- Chrome -------------------------------------------------------------

  String? _resolvedProtocolSummary(BuildContext context) {
    final l10n = widget.l10n;
    if (_routeMode) {
      final current = _currentRoute;
      return current == null ? null : routeLabel(l10n, current);
    }
    final menu = _menu;
    if (menu == null) return null;
    final effective = _activePin ?? menu.auto;
    return effective == null ? null : wireProtocolLabel(l10n, effective);
  }

  String _liveHeaderSummary(BuildContext context) {
    final l10n = widget.l10n;
    final channel = _selectedChannel;
    final fee = _selectedFeeGroup;
    final proto = _resolvedProtocolSummary(context);
    return [
      idCtrl.text.trim(),
      channel?.displayName ?? '',
      proto ?? '',
      fee?.name ?? (_matchedPreset != null ? l10n.modelDefaultPricingShort : l10n.noFeeGroup),
    ].where((s) => s.isNotEmpty).join(' · ');
  }

  /// 3-way kind switcher (`chat` / `image` / `video`); multimodal lives inside
  /// the `chat` family's behavior card.
  Widget _kindSegmentedControl(BuildContext context) {
    final l10n = widget.l10n;
    return AppSegmentedControl<String>(
      expand: true,
      compact: true,
      style: AppSegmentStyle.raised,
      track: AppSegmentTrack.fill,
      value: _primaryKind,
      onChanged: _selectPrimaryKind,
      segments: [
        AppSegment(value: 'chat', label: l10n.kindChat, icon: modelKindIcon('chat')),
        AppSegment(value: 'image', label: l10n.kindImage, icon: modelKindIcon('image')),
        AppSegment(value: 'video', label: l10n.kindVideo, icon: modelKindIcon('video')),
      ],
    );
  }

  /// Live model identity header + pinned 3-way kind segmented control.
  Widget _editHeading(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final trimmedName = nameCtrl.text.trim();
    final trimmedId = idCtrl.text.trim();
    final liveTitle = trimmedName.isNotEmpty
        ? trimmedName
        : (trimmedId.isNotEmpty ? trimmedId : widget.l10n.editModel);
    final subtitle = _liveHeaderSummary(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ModelKindPlate(tag, size: AppSize.touch),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          liveTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleLarge,
                        ),
                      ),
                      const SizedBox(width: AppSpace.s6),
                      ModelKindBadge(tag),
                    ],
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelSmall?.mono.copyWith(
                        fontWeight: FontWeight.w400,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            IconButton(
              icon: const Icon(Icons.close, size: AppSize.iconMd),
              tooltip: widget.l10n.close,
              onPressed: () => Navigator.pop(context),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(
                width: AppSize.iconButton,
                height: AppSize.iconButton,
              ),
              style: IconButton.styleFrom(
                foregroundColor: scheme.onSurfaceVariant,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _kindSegmentedControl(context),
      ],
    );
  }

  /// `1a`: delete on the left in the error ink; cancel and save on the right.
  Widget _editFooter(BuildContext context) {
    final l10n = widget.l10n;
    return Row(
      children: [
        AppButton(
          label: l10n.deleteModel,
          icon: Icons.delete_outline,
          variant: AppButtonVariant.destructiveText,
          onPressed: _confirmDelete,
        ),
        const Spacer(),
        AppButton(
          label: l10n.cancel,
          variant: AppButtonVariant.text,
          onPressed: () => Navigator.pop(context),
        ),
        const SizedBox(width: AppSpace.s6),
        AppButton(label: l10n.save, onPressed: _canSave ? _save : null),
      ],
    );
  }

  /// `1e`: back, title over the mono ID, and Save as tinted glass.
  Widget _phoneBar(BuildContext context) {
    final l10n = widget.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final top = MediaQuery.paddingOf(context).top;
    final enabled = _canSave;

    return AppGlass(
      grade: GlassGrade.bar,
      edges: GlassEdges.bottom,
      shadow: false,
      child: Padding(
        padding: EdgeInsets.only(top: top),
        child: SizedBox(
          height: _ModelEditDialogState._phoneBarHeight,
          child: Builder(
            builder: (context) {
              final ink = GlassInk.maybeOf(context)?.ink ?? scheme.onSurface;
              return Padding(
                padding: const EdgeInsetsDirectional.only(start: AppSpace.s6, end: 12),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      color: ink,
                      tooltip: l10n.back,
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: AppSpace.s4),
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          final trimmedName = nameCtrl.text.trim();
                          final trimmedId = idCtrl.text.trim();
                          final liveTitle = trimmedName.isNotEmpty
                              ? trimmedName
                              : (trimmedId.isNotEmpty ? trimmedId : l10n.editModel);
                          final subtitle = _liveHeaderSummary(context);
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      liveTitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: textTheme.titleLarge?.copyWith(color: ink),
                                    ),
                                  ),
                                  const SizedBox(width: AppSpace.s6),
                                  ModelKindBadge(tag),
                                ],
                              ),
                              if (subtitle.isNotEmpty)
                                Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.labelSmall?.mono.copyWith(
                                    fontWeight: FontWeight.w400,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    MergeSemantics(
                      child: Semantics(
                        button: true,
                        enabled: enabled,
                        label: l10n.save,
                        child: AppActionTarget(
                          excludeChildSemantics: true,
                          onTap: enabled ? _save : null,
                          child: AppTintedGlass(
                            enabled: enabled,
                            child: SizedBox(
                              height: AppSize.control,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 14),
                                child: Center(
                                  child: Text(
                                    l10n.save,
                                    style: textTheme.labelLarge?.metricsOnly.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: enabled ? scheme.onPrimary : scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // --- Layouts ------------------------------------------------------------

  Widget _twoColumns(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: Center(
              child: SizedBox(
                width: 1,
                height: double.infinity,
                child: ColoredBox(color: scheme.outlineVariant),
              ),
            ),
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _stack([
                _identitySection(context, pairFields: true),
                _billingSection(context),
              ]),
            ),
            const SizedBox(width: _ModelEditDialogState._columnGap),
            Expanded(child: _stack(_requestSections(context))),
          ],
        ),
      ],
    );
  }

  /// Kind-driven request & behavior column:
  /// - Image / Video show protocol & capabilities + collapsible transport.
  /// - Chat / Multimodal show routes or protocol + combined Token Budget +
  ///   reasoning + multimodal/agent/search behavior + collapsible transport.
  List<Widget> _requestSections(BuildContext context) {
    if (!_isChatGroup) {
      return [
        if (_showProtocolSection) _protocolSection(context),
        if (_showGenerationProfile) _generationProfileSection(context),
        ModelEditHelperText(widget.l10n.mediaModelChatControlsHiddenNote),
        _transportSection(context),
      ];
    }
    return [
      if (_routeMode)
        _routeSection(context)
      else if (_showProtocolSection)
        _protocolSection(context),
      if (_showGenerationProfile) _generationProfileSection(context),
      _tokenBudgetSection(context),
      _reasoningSection(context),
      _behaviorSection(context),
      _transportSection(context),
    ];
  }

  Widget _singleColumn(BuildContext context, {required bool pairFields}) {
    final phone = ModelEditMetrics.of(context).phone;
    return _stack([
      if (phone) _kindSegmentedControl(context),
      _identitySection(context, pairFields: pairFields),
      _billingSection(context),
      ..._requestSections(context),
    ]);
  }

  Widget _stack(List<Widget> sections) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (int i = 0; i < sections.length; i++) ...[
        if (i > 0) const SizedBox(height: _ModelEditDialogState._sectionGap),
        sections[i],
      ],
    ],
  );

  AppFieldSize _fieldSize(BuildContext context) =>
      ModelEditMetrics.of(context).phone ? AppFieldSize.large : AppFieldSize.regular;

  /// A section's caption; [scope] is its `D1f` scope, when there is one.
  Widget _caption(String text, {AppSectionTone tone = AppSectionTone.neutral, InlineSpan? scope}) =>
      AppSectionLabel(text, padding: EdgeInsets.zero, tone: tone, suffix: scope);

  // --- Identity -----------------------------------------------------------
}
