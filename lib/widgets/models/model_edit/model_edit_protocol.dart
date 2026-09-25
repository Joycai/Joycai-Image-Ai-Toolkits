part of '../model_edit_dialog.dart';

/// How the model is *requested*: provider features, and the per-surface
/// protocol pin with its staleness.
extension _ProtocolSections on _ModelEditDialogState {
  /// Whether the provider card shows: extended thinking on the ④ wire, or a
  /// web search some route can send — with routes the grant is the model's,
  /// so the switch stays while any route honours it (`D1f · 4d`).
  bool get _showProviderSection =>
      _isAnthropicChannel ||
      _webSearch != ServerWebSearch.unsupported ||
      (_routeMode && _anyRouteSearches);

  bool get _anyRouteSearches {
    final routes = _routes;
    final id = idCtrl.text.trim();
    if (routes == null || id.isEmpty) return false;
    return routes.kinds.any(
      (k) =>
          LLMDispatcher.serverWebSearch(
            channelType: routes.vendorOf(k) ?? routes.primaryVendorId,
            modelId: id,
            tag: tag,
            wireProtocol: k.face.id,
          ) !=
          ServerWebSearch.unsupported,
    );
  }

  /// `1d`'s provider card: extended thinking (Anthropic-format channels) and
  /// host web search (wherever the resolved chat face can switch it on).
  ///
  /// Extended thinking is a view of [reasoningEffort], not a column of its
  /// own: on this wire Off and Default both send nothing, so "on" is any
  /// effort rung, and turning it on picks Medium.
  Widget _providerSection(BuildContext context) {
    final l10n = widget.l10n;
    final supported = _reasoningSupported;
    final thinkingOn = reasoningEffort != null && reasoningEffort != 'off';
    final search = _webSearch;
    final showThinking = _isAnthropicChannel;
    final showSearch = search != ServerWebSearch.unsupported || (_routeMode && _anyRouteSearches);

    return ModelEditCard(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10, vertical: AppSpace.s4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showThinking)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.s6),
              child: ModelEditToggleRow(
                title: l10n.enableThinking,
                description: l10n.enableThinkingDesc,
                value: thinkingOn,
                dimmed: !supported,
                onChanged: !supported
                    ? null
                    : (v) => _rebuild(
                        () =>
                            reasoningEffort = v ? (thinkingOn ? reasoningEffort : 'medium') : null,
                      ),
              ),
            ),
          if (showThinking && showSearch) const Divider(height: 1),
          if (showSearch)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.s6),
              child: ModelEditToggleRow(
                title: l10n.enableWebSearch,
                // A traceless switch says so where it is turned on: the reply
                // carries no sources, and nothing shows whether it searched.
                description: search == ServerWebSearch.traceless
                    ? '${l10n.enableWebSearchDesc} ${l10n.enableWebSearchTracelessHint}'
                    : l10n.enableWebSearchDesc,
                value: enableWebSearch,
                onChanged: (v) => _rebuild(() => enableWebSearch = v),
              ),
            ),
          if (showSearch && _routeMode)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.s6),
              child: _webSearchMatrix(context),
            ),
        ],
      ),
    );
  }

  /// What host web search does for the current channel, id, kind and
  /// protocol selection: the dispatcher's answer, never a family check here.
  ServerWebSearch get _webSearch {
    final routed = _routed;
    final id = idCtrl.text.trim();
    if (routed == null || id.isEmpty) return ServerWebSearch.unsupported;
    return LLMDispatcher.serverWebSearch(
      channelType: routed.channelType,
      modelId: id,
      tag: tag,
      wireProtocol: _dispatchPin,
    );
  }

  // --- Wire protocol --------------------------------------------------------

  /// The protocol menu for the current channel, model id and kind, or null
  /// when channel or id is missing. The kind is read because it decides the
  /// surface: the same id tagged image offers the image menu.
  ProtocolMenu? get _menu {
    final routed = _routed;
    final id = idCtrl.text.trim();
    if (routed == null || id.isEmpty) return null;
    return LLMDispatcher.protocolMenu(routed.channelType, id, tag: tag);
  }

  /// The menu's options, or empty.
  List<WireProtocol> get _protocolMenu => _menu?.options ?? const [];

  /// The stored selection when it is still valid on the current menu; null
  /// for auto *and* for a stale value (which routes as auto).
  WireProtocol? get _activePin {
    final parsed = WireProtocol.tryParse(wireProtocol);
    if (parsed == null) return null;
    return _protocolMenu.contains(parsed) ? parsed : null;
  }

  /// Whether the stored selection exists but no longer applies.
  bool get _pinIsStale => wireProtocol != null && wireProtocol!.isNotEmpty && _activePin == null;

  /// The image route is the async task flow — drives the queue note and the
  /// card's Async task chip.
  bool get _asyncImagePinned => _activePin == WireProtocol.dashscopeImagesAsync;

  /// Which shape the protocol section takes — see [protocolSectionForm].
  ProtocolSectionForm get _protocolForm => protocolSectionForm(_menu, pinIsStale: _pinIsStale);

  /// Whether the protocol section renders at all.
  ///
  /// A chat model's protocol is its route (`D1f · 4e` ①): the route strip
  /// replaces this section for it. Image and video keep the dropdown — a
  /// dedicated endpoint is not a route.
  bool get _showProtocolSection => !_usesRoutes && _protocolForm != ProtocolSectionForm.none;

  /// The pinned protocol when its route has no streaming form, else null.
  /// Asked of the dispatcher with the form as it stands, so the editor cannot
  /// disagree with the router about which protocols stream. Auto never dims
  /// the toggle: it is only ignored because of something the user chose.
  WireProtocol? get _streamIgnoredBy {
    final pin = _activePin;
    final channel = _selectedChannel;
    final routed = _routed;
    if (pin == null || channel == null || routed == null) return null;
    final singleShot = LLMDispatcher().streamIsSingleShot(
      LLMModelConfig(
        modelId: idCtrl.text.trim(),
        channelType: routed.channelType,
        endpoint: routed.endpoint,
        apiKey: channel.apiKey,
        tag: tag,
        wireProtocol: pin.id,
        faceBases: routed.faceBases,
      ),
    );
    return singleShot ? pin : null;
  }

  Widget _protocolSection(BuildContext context) {
    final l10n = widget.l10n;
    final menu = _menu;
    final family = _channelFamily;
    final routed = _routed;
    if (menu == null || family == null || routed == null) {
      return const SizedBox.shrink();
    }
    final id = idCtrl.text.trim();
    final name = nameCtrl.text.trim();

    return ModelProtocolSection(
      header: _caption('${l10n.requestMethod} · ${l10n.interfaceProtocol}'),
      menu: menu,
      form: _protocolForm,
      channelFamily: family,
      kind: tag,
      modelName: name.isEmpty ? id : name,
      stored: wireProtocol,
      activePin: _activePin,
      pinIsStale: _pinIsStale,
      // As the model will be served once saved: with the choice on screen,
      // not the one in the database.
      paramsCapabilities: LLMDispatcher.descriptorFor(
        channelType: routed.channelType,
        modelId: id,
        tag: tag,
        wireProtocol: _activePin?.id,
      ).capabilities,
      onChanged: (v) => _rebuild(() => wireProtocol = v),
    );
  }

  // --- Channel lookups ------------------------------------------------------
}
