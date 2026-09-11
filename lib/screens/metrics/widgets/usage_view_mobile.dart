import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../state/app_state.dart';
import '../../../widgets/app_segmented_control.dart';
import 'usage_chrome.dart';
import 'usage_controller.dart';
import 'usage_list.dart';
import 'usage_range.dart';
import 'usage_summary.dart';

/// Phone layout for the token-usage tab (`D2` 1c): the hero, the range presets
/// split evenly across the width, and the records, in one scroll.
///
/// Refresh and Clear All live in the screen's glass header, which shares
/// [controller] with this body. Mounted without one, the view owns its data
/// and puts both actions beside the presets instead, so they are never lost.
class UsageViewMobile extends StatefulWidget {
  const UsageViewMobile({super.key, this.controller, this.topInset = 0});

  /// The data this view shows, when the screen around it needs to act on it.
  final UsageController? controller;

  /// Space to keep clear at the top for a header floating over the scroll.
  final double topInset;

  @override
  State<UsageViewMobile> createState() => _UsageViewMobileState();
}

class _UsageViewMobileState extends State<UsageViewMobile> {
  static const int _pageSize = 50;

  UsageController? _own;

  UsageController get _controller => widget.controller ?? _own!;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) _own = _createController();
    _controller.load(reset: true);
  }

  @override
  void didUpdateWidget(UsageViewMobile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;

    if (widget.controller == null) {
      _own = _createController();
    } else {
      _own?.dispose();
      _own = null;
    }
    _controller.load(reset: true);
  }

  UsageController _createController() => UsageController(
        models: () => Provider.of<AppState>(context, listen: false).allModels,
        pageSize: _pageSize,
      );

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final appState = Provider.of<AppState>(context);
    final modelTags = {
      for (final m in appState.allModels)
        if (m.id != null) m.id!: m.tag,
    };

    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final c = _controller;

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            AppSpace.s16,
            widget.topInset + 12,
            AppSpace.s16,
            MediaQuery.paddingOf(context).bottom + AppSpace.s16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              UsageSummary(
                stats: c.stats,
                rangeLabel: usagePresetLabel(l10n, c.preset),
                compact: true,
              ),
              const SizedBox(height: 12),
              _buildRangeRow(context, l10n, c),
              const SizedBox(height: 12),
              if (c.isLoading)
                const UsageLoadingCard()
              else
                UsagePanel(
                  child: UsageList(
                    usageData: c.rows,
                    onRefresh: () => c.load(reset: true),
                    hasMore: c.hasMore,
                    isLoadingMore: c.isLoadingMore,
                    onLoadMore: () => c.load(),
                    modelTags: modelTags,
                    totalCount: c.totalRecords,
                    pageSize: c.pageSize,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// The presets pick which stretch of time to look at, not a setting — so the
  /// chosen one is lifted out of the track rather than tinted.
  Widget _buildRangeRow(BuildContext context, AppLocalizations l10n, UsageController c) {
    final segments = AppSegmentedControl<String>(
      segments: [
        for (final preset in usagePresets)
          AppSegment(
            value: preset,
            label: usagePresetLabel(l10n, preset),
            enabled: !c.isLoading,
          ),
      ],
      value: c.preset,
      onChanged: c.selectPreset,
      expand: true,
      compact: true,
      style: AppSegmentStyle.raised,
    );

    if (widget.controller != null) return segments;

    return Row(
      children: [
        Expanded(child: segments),
        const SizedBox(width: AppSpace.s6),
        UsageToolIconButton(
          icon: Icons.refresh,
          tooltip: l10n.refresh,
          onPressed: c.isLoading ? null : () => c.load(reset: true),
        ),
        const SizedBox(width: AppSpace.s6),
        UsageToolIconButton(
          icon: Icons.delete_sweep_outlined,
          tooltip: l10n.clearAll,
          danger: true,
          onPressed: () => showClearAllUsageDialog(context, c),
        ),
      ],
    );
  }
}
