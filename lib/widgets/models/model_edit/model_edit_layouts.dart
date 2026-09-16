part of '../model_edit_dialog.dart';

/// The three forms of one state (`1a` dialog, `1e` phone page, `1e` add
/// dialog), their heading, footer and bar, and the column arrangements.
extension _Layouts on _ModelEditDialogState {
  /// `1a`: the 920 dialog.
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
            final twoColumns = constraints.maxWidth >= _ModelEditDialogState._minColumnWidth * 2 + _ModelEditDialogState._columnGap;
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
                    insets.top + _ModelEditDialogState._phoneBarHeight + _ModelEditDialogState._sectionGap,
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
      maxHeight: 640,
      scrollable: true,
      icon: Icons.add,
      title: l10n.addModel,
      subtitle: l10n.addModelSubtitle,
      content: ModelEditFieldScope(
        metrics: phone ? ModelEditMetrics.phoneDialog : ModelEditMetrics.desktop,
        child: Builder(builder: (context) {
          final size = _fieldSize(context);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _idField(size, autofocus: true, helper: l10n.addModelIdHelper),
              const SizedBox(height: _ModelEditDialogState._fieldGap),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _nameField(size)),
                  const SizedBox(width: _ModelEditDialogState._fieldGap),
                  Expanded(
                    child: AppLabelledField(
                      label: l10n.type,
                      size: size,
                      child: _kindMenuField(context),
                    ),
                  ),
                ],
              ),
              if (widget.preChannelId == null) ...[
                const SizedBox(height: _ModelEditDialogState._fieldGap),
                _channelField(size),
              ],
              const SizedBox(height: _ModelEditDialogState._sectionGap),
              // Everything else starts on Auto or its default; say so, so the
              // missing controls read as deferred rather than absent.
              ModelEditNotice(tone: ModelEditTone.info, text: l10n.addModelDefaultsNote),
            ],
          );
        }),
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

  /// The ID and the channel it is reached through, as the heading's second
  /// line.
  String get _headingSubtitle {
    final channel = _selectedChannel;
    return [idCtrl.text.trim(), channel?.displayName ?? '']
        .where((s) => s.isNotEmpty)
        .join(' · ');
  }

  /// `1a`: the kind's plate, the title, the mono subtitle, close.
  Widget _editHeading(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final kindColor = modelTagAccent(tag);
    final subtitle = _headingSubtitle;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: AppSize.touch,
          height: AppSize.touch,
          decoration: BoxDecoration(
            color: kindColor.withValues(alpha: AppAlpha.tint),
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          child: Icon(modelKindIcon(tag), size: 24, color: kindColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.l10n.editModel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleLarge,
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
              side: BorderSide(color: scheme.outlineVariant),
            ),
          ),
        ),
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
          child: Builder(builder: (context) {
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
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.editModel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleLarge?.copyWith(color: ink),
                        ),
                        Text(
                          idCtrl.text.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.labelSmall?.mono.copyWith(
                            fontWeight: FontWeight.w400,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Semantics(
                    button: true,
                    enabled: enabled,
                    label: l10n.save,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
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
                ],
              ),
            );
          }),
        ),
      ),
    );
  }

  // --- Layouts ------------------------------------------------------------

  Widget _twoColumns(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _stack([
            _identitySection(context, pairFields: true),
            _capabilitiesSection(context),
            _previewSection(context),
          ]),
        ),
        const SizedBox(width: _ModelEditDialogState._columnGap),
        Expanded(
          child: _stack([
            // The protocol is the cause of what follows it, so it leads the
            // column. Absent entirely (no placeholder height) when there is
            // nothing to choose and nothing to explain.
            if (_showProtocolSection) _protocolSection(context),
            _contextSection(context),
            if (_hasOutputCap) _outputCapSection(context),
            _agentSection(context),
            _reasoningSection(context),
            if (_isAnthropicChannel || _webSearch != ServerWebSearch.unsupported) _providerSection(context),
          ]),
        ),
      ],
    );
  }

  Widget _singleColumn(BuildContext context, {required bool pairFields}) {
    return _stack([
      _identitySection(context, pairFields: pairFields),
      if (_showProtocolSection) _protocolSection(context),
      _capabilitiesSection(context),
      _contextSection(context),
      if (_hasOutputCap) _outputCapSection(context),
      _agentSection(context),
      _reasoningSection(context),
      if (_isAnthropicChannel || _webSearch != ServerWebSearch.unsupported) _providerSection(context),
      _previewSection(context),
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

  Widget _caption(String text, {AppSectionTone tone = AppSectionTone.accent}) =>
      AppSectionLabel(text, padding: EdgeInsets.zero, tone: tone);

  // --- Identity -----------------------------------------------------------
}
