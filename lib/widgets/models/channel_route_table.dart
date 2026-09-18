import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/design_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../services/llm/channel_probe_service.dart';
import '../../services/llm/channel_routes.dart';
import '../../services/llm/llm_dispatcher.dart';
import '../../services/llm/vendors/platforms.dart';
import '../ui/app_button.dart';
import '../ui/app_icon_button.dart';
import 'app_route_badge.dart';
import 'channel_form_sections.dart';
import 'channel_probe_result_card.dart';
import 'route_labels.dart';

/// The channel editor's route table (`D1f · 4c`, `4g`): one row per route the
/// channel has — its path in one of four states, the address a request is
/// actually sent to, and test / make primary / turn off — then one dashed
/// row per route the platform offers that this channel has not enabled.
///
/// Holds only the path fields' text; the routes themselves are the caller's,
/// changed through [onChanged].
class ChannelRouteTable extends StatefulWidget {
  const ChannelRouteTable({
    super.key,
    required this.routes,
    required this.onChanged,
    required this.modelsOnRoute,
    required this.onProbe,
    this.probing,
    this.probes = const {},
    this.stacked = false,
  });

  final ChannelRoutes routes;
  final ValueChanged<ChannelRoutes> onChanged;

  /// How many of the channel's models ride each route: a route in use
  /// cannot be turned off.
  final int Function(RouteKind kind) modelsOnRoute;

  final ValueChanged<RouteKind> onProbe;

  /// The route being tested, if any.
  final RouteKind? probing;
  final Map<RouteKind, ChannelProbeResult> probes;

  /// The phone form: one card per route, the path under its name.
  final bool stacked;

  @override
  State<ChannelRouteTable> createState() => _ChannelRouteTableState();
}

class _ChannelRouteTableState extends State<ChannelRouteTable> {
  final Map<RouteKind, TextEditingController> _paths = {};

  TextEditingController _pathOf(RouteKind kind) => _paths.putIfAbsent(
    kind,
    () => TextEditingController(text: widget.routes.entry(kind)?.path ?? ''),
  );

  @override
  void didUpdateWidget(ChannelRouteTable old) {
    super.didUpdateWidget(old);
    // Follow a path changed from outside the field (restore default, a new
    // preset) without fighting the one being typed: a field that already
    // reads as the stored path — including one spelling out the default,
    // which is stored as "no path" — is left alone.
    for (final e in widget.routes.entries) {
      final ctrl = _pathOf(e.kind);
      final typed = ctrl.text.trim();
      final means =
          typed.isEmpty || typed == widget.routes.defaultPathOf(e.kind) ? null : typed;
      if (means != e.path) ctrl.text = e.path ?? '';
    }
  }

  @override
  void dispose() {
    for (final c in _paths.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Whether [kind] sits on the platform's own official host at its default
  /// path — an address nobody should retype (`4c` 官方线路).
  bool _locked(RouteKind kind) {
    final routes = widget.routes;
    final official = routes.platform.officialHost;
    if (official == null || routes.platform.hostFromUser) return false;
    if (routes.entry(kind)?.path != null) return false;
    return routes.host.toLowerCase() == official.toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final routes = widget.routes;
    final offered = [
      for (final r in routes.platform.routes)
        if (!routes.has(r.kind)) r.kind,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChannelFieldLabel(l10n.routeSectionTitle),
        Text(
          l10n.routeTableCaption,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
        const SizedBox(height: AppSpace.s6),
        for (final (i, e) in routes.entries.indexed) ...[
          if (i > 0) SizedBox(height: widget.stacked ? AppSpace.s10 : 0),
          _routeRow(context, l10n, e, first: i == 0),
        ],
        for (final kind in offered) _offeredRow(context, l10n, kind),
      ],
    );
  }

  Widget _routeRow(
    BuildContext context,
    AppLocalizations l10n,
    RouteEntry e, {
    required bool first,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final routes = widget.routes;
    final kind = e.kind;
    final primary = kind == routes.primary.kind;
    final inUse = widget.modelsOnRoute(kind);
    final defaultPath = routes.defaultPathOf(kind);
    final locked = _locked(kind);
    final path = e.path;

    final badge = AppRouteBadge(
      label: primary
          ? '${routeLabel(l10n, kind)} · ${l10n.routePrimarySuffix}'
          : routeLabel(l10n, kind),
      state: primary ? RouteBadgeState.current : RouteBadgeState.configured,
    );

    final String? removeBlock = routes.entries.length <= 1
        ? l10n.routeOnlyOne
        : inUse > 0
        ? l10n.routeInUse(inUse)
        : primary
        ? l10n.routePrimaryCantRemove
        : null;

    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIconButton(
          icon: Icons.wifi_tethering,
          tooltip: l10n.routeTest,
          color: scheme.onSurfaceVariant,
          onPressed: widget.probing == null ? () => widget.onProbe(kind) : null,
        ),
        AppIconButton(
          icon: primary ? Icons.star : Icons.star_outline,
          tooltip: primary ? l10n.routeIsPrimary : l10n.routeMakePrimary,
          color: primary ? scheme.primary : scheme.onSurfaceVariant,
          onPressed: primary
              ? null
              : () => widget.onChanged(routes.withPrimary(kind)),
        ),
        AppIconButton(
          icon: Icons.remove_circle_outline,
          tooltip: removeBlock ?? l10n.routeRemove,
          color: scheme.onSurfaceVariant,
          onPressed: removeBlock != null
              ? null
              : () => widget.onChanged(routes.withoutRoute(kind)),
        ),
      ],
    );

    final pathField = locked
        ? Container(
            height: AppSize.control,
            alignment: AlignmentDirectional.centerStart,
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10),
            child: Row(
              children: [
                Icon(Icons.lock_outline, size: AppSize.iconSm, color: scheme.outline),
                const SizedBox(width: AppSpace.s6),
                Text(
                  l10n.routeOfficialLocked,
                  style: textTheme.labelSmall?.copyWith(color: scheme.outline),
                ),
              ],
            ),
          )
        : ChannelField(
            controller: _pathOf(kind),
            mono: true,
            hint: defaultPath,
            onChanged: (v) {
              final t = v.trim();
              widget.onChanged(routes.withPath(kind, t.isEmpty ? null : t));
            },
          );

    // The path's state: default (follows the platform), edited, or a whole
    // address on a host of its own.
    final Widget? stateTag = locked
        ? null
        : path == null
        ? (defaultPath == null
              ? null
              : AppRouteBadge(
                  label: l10n.routePathDefault(defaultPath.isEmpty ? '/' : defaultPath),
                  state: RouteBadgeState.off,
                ))
        : AppRouteBadge(
            label: ChannelRoutes.isAbsolute(path)
                ? l10n.routePathOwnHost
                : l10n.routePathEdited(
                    (defaultPath == null || defaultPath.isEmpty) ? '/' : defaultPath,
                  ),
            state: RouteBadgeState.configured,
          );

    final address = routes.addressOf(kind);
    final url = address == null
        ? null
        : 'POST ${LLMDispatcher.chatRequestUrl(kind.face, address)}';

    final detail = Wrap(
      spacing: AppSpace.s6,
      runSpacing: AppSpace.s4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ?stateTag,
        if (path != null && defaultPath != null && !locked)
          AppButton(
            label: l10n.routeRestoreDefault,
            variant: AppButtonVariant.text,
            size: AppButtonSize.compact,
            onPressed: () {
              _pathOf(kind).text = '';
              widget.onChanged(routes.withPath(kind, null));
            },
          ),
        if (url != null)
          Text(
            url,
            style: textTheme.labelSmall?.mono.copyWith(color: scheme.onSurfaceVariant),
          ),
      ],
    );

    final probe = widget.probes[kind];
    final Widget? probeCard = widget.probing == kind
        ? const Padding(
            padding: EdgeInsets.only(top: AppSpace.s6),
            child: LinearProgressIndicator(minHeight: 2),
          )
        : probe == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: AppSpace.s6),
            child: ChannelProbeResultCard(
              l10n: l10n,
              result: probe,
              onRetry: () => widget.onProbe(kind),
            ),
          );

    if (widget.stacked) {
      return Container(
        padding: const EdgeInsets.all(AppSpace.s10),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Wraps rather than overflows: the actions drop under the name
            // on a phone too narrow for both.
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: AppSpace.s4,
              children: [badge, actions],
            ),
            const SizedBox(height: AppSpace.s6),
            pathField,
            const SizedBox(height: AppSpace.s6),
            detail,
            ?probeCard,
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.s10),
      decoration: BoxDecoration(
        border: first
            ? null
            : Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 128,
                child: Align(alignment: AlignmentDirectional.centerStart, child: badge),
              ),
              const SizedBox(width: AppSpace.s10),
              Expanded(child: pathField),
              const SizedBox(width: AppSpace.s6),
              actions,
            ],
          ),
          const SizedBox(height: AppSpace.s6),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 138),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [detail, ?probeCard],
            ),
          ),
        ],
      ),
    );
  }

  Widget _offeredRow(BuildContext context, AppLocalizations l10n, RouteKind kind) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.s6),
      decoration: BoxDecoration(
        border: widget.stacked
            ? null
            : Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: AppSpace.s4,
        children: [
          AppRouteBadge(
            label: routeLabel(l10n, kind),
            state: RouteBadgeState.off,
          ),
          AppButton(
            label: widget.stacked
                ? l10n.routeEnable(routeLabel(l10n, kind))
                : l10n.routeEnableShort,
            icon: Icons.add_circle_outline,
            variant: AppButtonVariant.text,
            size: AppButtonSize.compact,
            onPressed: () => widget.onChanged(widget.routes.withRoute(kind)),
          ),
        ],
      ),
    );
  }
}
