part of '../model_edit_dialog.dart';

/// How the model is *requested*: provider features, and the per-surface
/// protocol pin with its staleness.
extension _ProtocolSections on _ModelEditDialogState {
  List<String> get _generationProfileChoices {
    final routed = _routed;
    if (routed == null || idCtrl.text.trim().isEmpty) return const [];
    final schema = LLMDispatcher.generationSchemaFor(
      channelType: routed.channelType,
      modelId: idCtrl.text.trim(),
      tag: tag,
      wireProtocol: _dispatchPin,
    );
    return GenerationProfiles.compatible(schema.protocol);
  }

  bool get _showGenerationProfile =>
      generationProfile != null ||
      (_menu?.recognized == false && _generationProfileChoices.isNotEmpty);

  Widget _generationProfileSection(BuildContext context) {
    final l10n = widget.l10n;
    final choices = _generationProfileChoices;
    return AppLabelledField(
      label: l10n.generationProfile,
      child: AppDropdown<String>(
        size: _fieldSize(context),
        value: choices.contains(generationProfile) ? generationProfile! : '',
        items: [
          AppDropdownItem(value: '', label: l10n.generationProfileAuto),
          for (final profile in choices) AppDropdownItem(value: profile, label: profile),
        ],
        onChanged: (value) => _rebuild(() => generationProfile = value == '' ? null : value),
      ),
    );
  }

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
      paramsCapabilities: LLMDispatcher.generationSchemaFor(
        channelType: routed.channelType,
        modelId: id,
        tag: tag,
        wireProtocol: _activePin?.id,
        profile: generationProfile,
      ).capabilities,
      onChanged: (v) => _rebuild(() => wireProtocol = v),
    );
  }

  // --- Channel lookups ------------------------------------------------------
}
