part of '../model_edit_dialog.dart';

/// What the model *is*: identity, preset matching, channel and billing.
extension _IdentitySection on _ModelEditDialogState {
  Widget _identitySection(BuildContext context, {required bool pairFields}) {
    final l10n = widget.l10n;
    final size = _fieldSize(context);
    final name = _nameField(size);
    final channel = _channelField(size);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _caption(l10n.basicInfo),
        const SizedBox(height: AppSpace.s6),
        _idField(size),
        const SizedBox(height: AppSpace.s6),
        _presetBar(context),
        const SizedBox(height: _ModelEditDialogState._fieldGap),
        if (pairFields)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: name),
              const SizedBox(width: _ModelEditDialogState._fieldGap),
              Expanded(child: channel),
            ],
          )
        else ...[
          name,
          const SizedBox(height: _ModelEditDialogState._fieldGap),
          channel,
        ],
      ],
    );
  }

  Widget _billingSection(BuildContext context) {
    final l10n = widget.l10n;
    final size = _fieldSize(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _caption(l10n.billing),
        const SizedBox(height: AppSpace.s6),
        _feeGroupField(size),
      ],
    );
  }

  /// The ID field. Once typed into and emptied it carries the save-blocking
  /// note; until then, [helper] (the add dialog's) says the same thing
  /// quietly.
  Widget _idField(AppFieldSize size, {bool autofocus = false, String? helper}) {
    final l10n = widget.l10n;
    final missing = _idTouched && idCtrl.text.trim().isEmpty;
    // Shown at once, typed into or not: choosing a channel that already has
    // this ID is as much a reason the dialog cannot save as typing it.
    final taken = !missing && _idTaken;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppLabelledField(
          label: l10n.modelIdLabel,
          size: size,
          child: ModelEditTextField(
            controller: idCtrl,
            icon: Icons.tag,
            // Mono: an identifier the wire sees verbatim.
            mono: true,
            autofocus: autofocus,
            hint: 'e.g. gpt-4, gemini-1.5-pro',
            error: missing || taken,
            onChanged: (_) => _rebuild(() {
              _idTouched = true;
              _appliedPresetId = null;
            }),
          ),
        ),
        if (missing)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.s6),
            child: ModelEditValidationNote(
              title: l10n.modelIdRequiredTitle,
              description: l10n.modelIdRequiredDesc,
            ),
          )
        else if (taken)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.s6),
            child: ModelEditValidationNote(
              title: l10n.modelIdTakenTitle,
              description: l10n.modelIdTakenDesc,
            ),
          )
        else if (helper != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.s4),
            child: ModelEditHelperText(helper),
          ),
      ],
    );
  }

  Widget _nameField(AppFieldSize size) {
    return AppLabelledField(
      label: widget.l10n.displayName,
      size: size,
      child: ModelEditTextField(
        controller: nameCtrl,
        icon: Icons.badge_outlined,
        // Optional: a blank name saves as the ID.
        hint: widget.l10n.modelNameOptionalHint,
        onChanged: (_) => _rebuild(() {}),
      ),
    );
  }

  Widget _channelField(AppFieldSize size) {
    final l10n = widget.l10n;
    final appState = widget.appState;
    final channel = _selectedChannel;

    return AppLabelledField(
      label: l10n.channel,
      size: size,
      // The channel's tag colour as a dot beside its name (`1a`), in the
      // picker every other channel choice in the app uses.
      child: Builder(
        // Its own context: the metrics scope sits below the dialog
        // state's, which would read the desktop height on a phone.
        builder: (context) => SearchablePickerField<int>(
          selected: channel == null ? null : channelPickerOption(channel),
          optionsBuilder: () => appState.allChannels.map(channelPickerOption).toList(),
          onChanged: (v) => _rebuild(() {
            if (v != channelId) {
              // Another channel's routes: the route chosen and the
              // parameters parked here mean nothing there.
              activeRoute = null;
              _parked = const {};
              _switchTarget = null;
            }
            channelId = v;
            if (widget.model == null && !_feeGroupTouched) {
              feeGroupId = widget.appState.defaultFeeGroupFor(v);
            }
          }),
          hint: l10n.selectAChannel,
          searchHint: l10n.searchChannels,
          dialogIcon: Icons.hub_outlined,
          enabled: appState.allChannels.isNotEmpty,
          badgeStyle: PickerBadge.dot,
          size: size,
          // The form's one field height (`1a` 32, `1e` 44). Left to the
          // large size's own height, the phone's selects came out 37
          // beside its 44px text fields.
          height: ModelEditMetrics.of(context).fieldHeight,
        ),
      ),
    );
  }

  Widget _feeGroupField(AppFieldSize size) {
    final l10n = widget.l10n;
    final matched = _matchedPreset;
    final hasDefaultPricing = feeGroupId == null && matched != null;
    final refPrice = hasDefaultPricing
        ? feeGroupSummary(l10n, matched.pricing.toPricingGroup(name: matched.displayName))
        : '';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppLabelledField(
          label: l10n.feeGroup,
          size: size,
          child: Builder(
            // Its own context: the metrics scope sits below the dialog
            // state's, which would read the desktop height on a phone.
            builder: (context) => AppDropdown<int?>(
              value: feeGroupId,
              items: [
                // A real answer — no group — drawn as the absence it is.
                AppDropdownItem(value: null, label: l10n.noFeeGroup, muted: true),
                // `D2b · 21f`: each group's charge in the same shape whatever
                // its mode, so the user reads the price without first reading
                // the mode.
                for (final g in widget.appState.allPricingGroups)
                  AppDropdownItem(value: g.id!, label: g.name, trailing: feeGroupSummary(l10n, g)),
              ],
              onChanged: (v) => _rebuild(() {
                feeGroupId = v;
                _feeGroupTouched = true;
              }),
              prefixIcon: Icons.payments_outlined,
              size: size,
              height: ModelEditMetrics.of(context).fieldHeight,
            ),
          ),
        ),
        if (hasDefaultPricing) ...[
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.s4),
            child: ModelEditHelperText(l10n.modelPresetDefaultPricingNote),
          ),
          if (refPrice.isNotEmpty)
            Builder(
              builder: (context) {
                final theme = Theme.of(context);
                return Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    l10n.modelPresetReferencePrice(refPrice),
                    style: theme.textTheme.labelSmall?.mono.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              },
            ),
        ],
      ],
    );
  }

  // --- Built-in model preset ------------------------------------------------

  BuiltinModelSpec? get _matchedPreset => BuiltinModelSpecs.match(idCtrl.text)?.spec;

  void _applyModelPreset(BuiltinModelSpec spec) {
    final id = idCtrl.text.trim();
    final from = LLMDispatcher.surfaceForModel(id, tag: tag);
    final to = LLMDispatcher.surfaceForModel(id, tag: spec.tag);
    _rebuild(() {
      if (from != to) {
        _pinBySurface[from] = wireProtocol;
        wireProtocol = _pinBySurface[to];
      }
      tag = spec.tag;
      if (spec.tag == 'chat' || spec.tag == 'multimodal') {
        _rememberedMultimodal = spec.tag == 'multimodal';
      }
      if (spec.contextWindow != null) {
        contextMode = ContextWindowMode.specified;
        contextCtrl.text = '${spec.contextWindow}';
      }
      if (spec.maxOutputTokens != null && spec.tag != 'image' && spec.tag != 'video') {
        outputCapSpecified = true;
        outputCapCtrl.text = '${spec.maxOutputTokens}';
      }
      if (spec.supportsThinking) {
        if (spec.defaultReasoningEffort != null) {
          reasoningEffort = spec.defaultReasoningEffort;
        }
      } else {
        reasoningEffort = null;
      }
      if (spec.generationProfile != null &&
          _generationProfileChoices.contains(spec.generationProfile)) {
        generationProfile = spec.generationProfile;
      }
      _appliedPresetId = spec.id;
    });
  }

  Future<void> _pickModelPreset(BuildContext context) async {
    final l10n = widget.l10n;
    final current = BuiltinModelSpecs.byId(_appliedPresetId) ?? _matchedPreset;
    final result = await showSearchablePicker<BuiltinModelSpec>(
      context: context,
      title: l10n.modelPresetPickerTitle,
      searchHint: l10n.modelPresetSearchHint,
      icon: Icons.auto_awesome_outlined,
      selected: current,
      options: [for (final spec in BuiltinModelSpecs.all) builtinModelPresetOption(l10n, spec)],
    );
    if (result != null && mounted) {
      _applyModelPreset(result.value);
    }
  }

  Widget _presetBar(BuildContext context) {
    final l10n = widget.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final applied = BuiltinModelSpecs.byId(_appliedPresetId);
    final matched = _matchedPreset;
    final display = applied ?? matched;

    final bool calmApplied = applied != null && (matched == null || applied.id == matched.id);
    if (calmApplied) {
      return ModelEditCard(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10, vertical: AppSpace.s6),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline, size: AppSize.iconSm, color: scheme.primary),
            const SizedBox(width: AppSpace.s6),
            Expanded(
              child: Text(
                l10n.modelPresetApplied(applied.displayName),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: AppSpace.s6),
            AppButton(
              label: l10n.modelPresetChoose,
              variant: AppButtonVariant.text,
              size: AppButtonSize.compact,
              onPressed: () => _pickModelPreset(context),
            ),
          ],
        ),
      );
    }

    final String headline = applied != null
        ? l10n.modelPresetApplied(applied.displayName)
        : matched != null
        ? l10n.modelPresetMatched(matched.displayName)
        : l10n.modelPresetNone;

    // Keep pricing out of the preset-apply bar so users don't expect "Apply"
    // to overwrite their fee group selection; billing reference lives below.
    final brief = display == null
        ? ''
        : formatBuiltinSpecBrief(l10n, display, includePricing: false);

    return ModelEditCard(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10, vertical: AppSpace.s6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            Icons.auto_awesome_outlined,
            size: AppSize.iconSm,
            color: display != null ? scheme.primary : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpace.s6),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headline,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: display != null ? scheme.onSurface : scheme.onSurfaceVariant,
                    fontWeight: display != null ? FontWeight.w500 : FontWeight.w400,
                  ),
                ),
                if (brief.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    brief,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.mono.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpace.s6),
          if (matched != null && applied?.id != matched.id) ...[
            AppButton(
              label: l10n.modelPresetApply,
              variant: AppButtonVariant.tonal,
              size: AppButtonSize.compact,
              onPressed: () => _applyModelPreset(matched),
            ),
            const SizedBox(width: AppSpace.s4),
          ],
          AppButton(
            label: l10n.modelPresetChoose,
            variant: AppButtonVariant.text,
            size: AppButtonSize.compact,
            onPressed: () => _pickModelPreset(context),
          ),
        ],
      ),
    );
  }

  // --- Kind selection -------------------------------------------------------

  void _selectPrimaryKind(String primary) {
    final targetTag = primary == 'chat' ? (_rememberedMultimodal ? 'multimodal' : 'chat') : primary;
    _selectKind(targetTag);
  }

  void _setMultimodal(bool enabled) {
    _rememberedMultimodal = enabled;
    _selectKind(enabled ? 'multimodal' : 'chat');
  }

  /// Moves the kind.
  ///
  /// A kind on another surface swaps the protocol menu, so the selection made
  /// for the old surface is set aside and the new surface's comes back — auto
  /// if it never had one. Remembered per *surface*, not per kind: chat and
  /// multimodal share one menu, and swapping between them must not throw
  /// away a choice that is still valid. Lives only as long as this dialog;
  /// saving writes the current surface's choice.
  void _selectKind(String value) {
    if (value == tag) return;
    final id = idCtrl.text.trim();
    final from = LLMDispatcher.surfaceForModel(id, tag: tag);
    final to = LLMDispatcher.surfaceForModel(id, tag: value);
    _rebuild(() {
      if (from != to) {
        _pinBySurface[from] = wireProtocol;
        wireProtocol = _pinBySurface[to];
      }
      tag = value;
      if (value == 'chat' || value == 'multimodal') {
        _rememberedMultimodal = value == 'multimodal';
      }
    });
  }
}
