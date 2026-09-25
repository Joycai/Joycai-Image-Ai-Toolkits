part of '../model_edit_dialog.dart';

/// The model's route (`D1f · 4d`, `4e`): the channel as the model sees it,
/// the route strip, switching, and the scope captions.
///
/// Every protocol question the editor asks — the reasoning ladder, the
/// output cap's dialect, web search, streaming — is asked through
/// [_routed]: the vendor and address of the route the model rides, never the
/// channel's flat primary columns.
extension _RouteSections on _ModelEditDialogState {
  /// The selected channel's routes, or null when no channel is picked.
  ChannelRoutes? get _routes {
    final channel = _selectedChannel;
    return channel == null ? null : RoutedChannel.routesOf(channel);
  }

  /// Whether the model as it stands rides a route: chat-surface kinds do,
  /// image and video pick a dedicated endpoint instead.
  bool get _usesRoutes =>
      LLMDispatcher.surfaceForModel(idCtrl.text.trim(), tag: tag) == Surface.chat;

  /// Whether the route strip shows: a chat model on a channel with a route
  /// to choose. A single-route channel looks exactly as before (`4e` ④).
  bool get _routeMode {
    final routes = _routes;
    return routes != null && _usesRoutes && routes.entries.length > 1;
  }

  /// The channel as the draft model sees it, or null without a channel.
  RoutedChannel? get _routed {
    final channel = _selectedChannel;
    return channel == null ? null : RoutedChannel.forModel(channel, _draftModel);
  }

  /// The protocol selection to hand the dispatcher: the route's face for a
  /// chat model, the stored media selection for image and video.
  String? get _dispatchPin => _usesRoutes ? _routed?.wireProtocol : wireProtocol;

  /// The route the model rides now, as shown.
  RouteKind? get _currentRoute {
    final routes = _routes;
    return routes == null ? null : ModelRoutes.displayRoute(_draftModel, routes);
  }

  /// A caption's scope (`4d` 作用域): 「模型」 for what stays with the model
  /// across routes, 「本线路 · X」 for what each route keeps its own of. Only
  /// where there is a route to choose — a single-route channel has no scope
  /// to tell apart.
  InlineSpan? _scope({bool route = false}) {
    if (!_routeMode) return null;
    final l10n = widget.l10n;
    final theme = Theme.of(context);
    final current = _currentRoute;
    final text = route && current != null
        ? l10n.routeScopeThisRoute(routeLabel(l10n, current))
        : l10n.routeScopeModel;
    // Right after the caption (`4d`: 标题后灰字), and what an ellipsis cuts.
    return TextSpan(
      text: text,
      style: theme.textTheme.labelSmall?.mono.copyWith(
        color: route ? theme.colorScheme.onAccentTint : theme.colorScheme.outline,
        // The design's `.scope`: regular weight, untracked, whatever the
        // caption it follows.
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
      ),
    );
  }

  /// Moves the form to [to]: the current parameters parked, [to]'s loaded —
  /// empty when it was never set up — every per-route field overwritten.
  /// Nothing is stored until Save.
  void _switchRoute(RouteKind to) {
    final routes = _routes;
    if (routes == null) return;
    final moved = RouteSwitching.switchRoute(_draftModel, routes, to);
    _rebuild(() {
      activeRoute = moved.activeRoute;
      wireProtocol = moved.wireProtocol;
      _parked = ModelRoutes.parked(moved);
      reasoningEffort = moved.reasoningEffort;
      final cap = moved.maxOutputTokens;
      outputCapSpecified = cap != null && cap > 0;
      outputCapCtrl.text = outputCapSpecified ? '$cap' : '';
      _outputCapTouched = false;
      _switchTarget = null;
    });
  }

  /// A tap on a route in the strip. Back to a route that was set up switches
  /// at once — its values come back as they were; to one never set up opens
  /// the preview of what changes first (`4d` ②).
  void _onRouteTapped(RouteKind kind) {
    if (kind == _currentRoute) {
      _rebuild(() => _switchTarget = null);
    } else if (_parked.containsKey(kind)) {
      _switchRoute(kind);
    } else {
      _rebuild(() => _switchTarget = kind);
    }
  }

  Widget _routeSection(BuildContext context) {
    final l10n = widget.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final routes = _routes!;
    final current = _currentRoute!;
    final phone = ModelEditMetrics.of(context).phone;
    final size = phone ? RouteBadgeSize.touch : RouteBadgeSize.strip;
    final enabled = ModelRoutes.enabledRoutes(_draftModel, routes).toSet();

    // `4g`: current first, then the ones set up, then the rest (dashed +).
    final order = [
      current,
      for (final k in routes.kinds)
        if (k != current && enabled.contains(k)) k,
      for (final k in routes.kinds)
        if (!enabled.contains(k)) k,
    ];
    final address = routes.addressOf(current);
    Widget stripBadge(RouteKind k) => AppRouteBadge(
      label: routeLabel(l10n, k),
      size: size,
      state: k == current
          ? RouteBadgeState.current
          : k == _switchTarget || enabled.contains(k)
          ? RouteBadgeState.configured
          : RouteBadgeState.off,
      trailingIcon: enabled.contains(k) || k == _switchTarget ? null : Icons.add,
      onTap: () => _onRouteTapped(k),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _caption(l10n.routeSectionTitle),
        const SizedBox(height: AppSpace.s6),
        // `4g`: on a phone the strip scrolls sideways, current first, rather
        // than wrapping; wider layouts have room and wrap.
        if (phone)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (i, k) in order.indexed) ...[
                  if (i > 0) const SizedBox(width: AppSpace.s6),
                  stripBadge(k),
                ],
              ],
            ),
          )
        else
          Wrap(
            spacing: AppSpace.s6,
            runSpacing: AppSpace.s6,
            children: [for (final k in order) stripBadge(k)],
          ),
        if (address != null) ...[
          const SizedBox(height: AppSpace.s6),
          Text(
            'POST ${LLMDispatcher.chatRequestUrl(current.face, address, modelId: idCtrl.text.trim().isEmpty ? '{id}' : idCtrl.text.trim())}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.mono.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
        AnimatedSize(
          duration: AppMotion.durationOf(context, AppMotion.reveal),
          curve: AppMotion.enter,
          alignment: Alignment.topCenter,
          child: _switchTarget == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: AppSpace.s10),
                  child: _switchPreview(context, routes, current, _switchTarget!),
                ),
        ),
      ],
    );
  }

  /// `4d` ②: what switching to [to] changes, each row old → new; a value the
  /// new route never had reads 「未设置 · 不发」 on a dashed chip.
  Widget _switchPreview(BuildContext context, ChannelRoutes routes, RouteKind from, RouteKind to) {
    final l10n = widget.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final changes = RouteSwitching.preview(_draftModel, routes, to);
    // Each side named on its own route's scale: "On" where that wire only
    // tells on from off.
    bool onOffOn(RouteKind k) =>
        !RouteSwitching.ladderFor(_draftModel, routes, k).contains(ReasoningEffort.low);
    final fromOnOff = onOffOn(from);
    final toOnOff = onOffOn(to);

    String fieldName(RouteParamField f) => switch (f) {
      RouteParamField.reasoningEffort => l10n.reasoningEffort,
      RouteParamField.thinking => l10n.enableThinking,
      RouteParamField.maxOutputTokens => l10n.outputCap,
    };
    String? valueText(RouteParamField f, Object? v, {required bool onOff}) {
      if (v == null || v == false) return null;
      return switch (f) {
        RouteParamField.reasoningEffort => _rungLabel(
          ReasoningEffort.tryParse(v as String),
          short: false,
          onOff: onOff,
        ),
        RouteParamField.thinking => l10n.reasoningEffortOn,
        RouteParamField.maxOutputTokens => formatGroupedTokens(v as int),
      };
    }

    Widget chip(String? text) {
      final style = theme.textTheme.labelSmall?.mono;
      if (text != null) {
        return Text(text, style: style?.copyWith(color: scheme.onSurface));
      }
      return AppRouteBadge(label: l10n.routeSwitchUnset, state: RouteBadgeState.off);
    }

    return Container(
      padding: const EdgeInsets.all(AppSpace.s10),
      decoration: BoxDecoration(
        color: scheme.accentTint,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: scheme.primary),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.routeSwitchTitle(routeLabel(l10n, to)),
            style: theme.textTheme.labelLarge?.copyWith(
              color: scheme.onAccentTint,
              fontWeight: FontWeight.w600,
            ),
          ),
          for (final c in changes)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.s6),
              child: Row(
                children: [
                  SizedBox(
                    width: 96,
                    child: Text(
                      fieldName(c.field),
                      style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                  Flexible(child: chip(valueText(c.field, c.from, onOff: fromOnOff))),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.s6),
                    child: Icon(Icons.arrow_forward, size: AppSize.iconSm, color: scheme.outline),
                  ),
                  Flexible(child: chip(valueText(c.field, c.to, onOff: toOnOff))),
                ],
              ),
            ),
          const SizedBox(height: AppSpace.s6),
          Text(
            l10n.routeSwitchNote(routeLabel(l10n, from)),
            style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpace.s6),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AppButton(
                label: l10n.cancel,
                variant: AppButtonVariant.text,
                size: AppButtonSize.compact,
                onPressed: () => _rebuild(() => _switchTarget = null),
              ),
              const SizedBox(width: AppSpace.s6),
              AppButton(
                label: l10n.routeSwitchConfirm,
                size: AppButtonSize.compact,
                onPressed: () => _switchRoute(to),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// `4e` ②: the sections that change with the route, framed by one 2px
  /// accent rule — the guide-line grammar of D1c's parameter summary.
  Widget _routeScoped(BuildContext context, List<Widget> sections) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsetsDirectional.only(start: 12),
      decoration: BoxDecoration(
        border: BorderDirectional(start: BorderSide(color: scheme.primary, width: 2)),
      ),
      child: _stack(sections),
    );
  }

  /// `4d` 联网搜索各线路: whether each of the channel's routes can send the
  /// model's web search — the grant stays on the model; each route either
  /// honours it or does not.
  Widget _webSearchMatrix(BuildContext context) {
    final l10n = widget.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final routes = _routes!;
    final id = idCtrl.text.trim();
    final current = _currentRoute;
    bool sends(RouteKind k) =>
        LLMDispatcher.serverWebSearch(
          channelType: routes.vendorOf(k) ?? routes.primaryVendorId,
          modelId: id,
          tag: tag,
          wireProtocol: k.face.id,
        ) !=
        ServerWebSearch.unsupported;
    bool untested(RouteKind k) => routes.platform.untestedWebSearch.contains(k);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              l10n.routeWebSearchPerRoute,
              style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(width: AppSpace.s10),
            Expanded(
              child: Wrap(
                spacing: AppSpace.s4,
                runSpacing: AppSpace.s4,
                children: [
                  // Three answers (`4d`): sent (check), cannot be sent
                  // (block), sent but never seen to work here (help).
                  for (final k in routes.kinds)
                    AppRouteBadge(
                      label: routeLabel(l10n, k, short: true),
                      state: !sends(k)
                          ? RouteBadgeState.quiet
                          : untested(k)
                          ? RouteBadgeState.off
                          : RouteBadgeState.configured,
                      trailingIcon: !sends(k)
                          ? Icons.block
                          : untested(k)
                          ? Icons.help_outline
                          : Icons.check,
                      tooltip: !sends(k)
                          ? l10n.routeWebSearchCannot
                          : untested(k)
                          ? l10n.routeWebSearchUntested
                          : l10n.routeWebSearchSends,
                    ),
                ],
              ),
            ),
          ],
        ),
        if (enableWebSearch && current != null && !sends(current)) ...[
          const SizedBox(height: AppSpace.s6),
          ModelEditNotice(tone: ModelEditTone.warning, text: l10n.routeWebSearchNotSent),
        ] else if (enableWebSearch && current != null && untested(current)) ...[
          const SizedBox(height: AppSpace.s6),
          ModelEditNotice(tone: ModelEditTone.info, text: l10n.routeWebSearchUntestedNote),
        ],
      ],
    );
  }
}
