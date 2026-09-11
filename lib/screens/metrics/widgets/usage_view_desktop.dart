import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/design_tokens.dart';
import '../../../core/responsive.dart';
import '../../../l10n/app_localizations.dart';
import '../../../state/app_state.dart';
import 'usage_chrome.dart';
import 'usage_controller.dart';
import 'usage_group_costs.dart';
import 'usage_list.dart';
import 'usage_range.dart';
import 'usage_summary.dart';
import 'usage_toolbar.dart';

/// Tablet and desktop layout for the token-usage view: one scrolling flow of
/// cards on the canvas — the hero, the range toolbar, per-group costs, and the
/// record table (`D2` 1a / 1b).
///
/// The toolbar sits on the canvas between the hero and the groups rather than
/// in a card header, because the range it sets governs every card on the page,
/// hero included. Inside one card's header it would have looked like that
/// card's filter.
class UsageViewDesktop extends StatefulWidget {
  const UsageViewDesktop({super.key});

  @override
  State<UsageViewDesktop> createState() => _UsageViewDesktopState();
}

class _UsageViewDesktopState extends State<UsageViewDesktop> {
  static const int _pageSize = 100;

  /// The gap between cards in the flow, as drawn.
  static const double _gap = 12;

  late final UsageController _controller;

  @override
  void initState() {
    super.initState();
    _controller = UsageController(
      models: () => Provider.of<AppState>(context, listen: false).allModels,
      pageSize: _pageSize,
      createCheckpoints: true,
    );
    _controller.load(reset: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final appState = Provider.of<AppState>(context);
    final narrow = Responsive.isNarrow(context);
    final inset = narrow ? AppSpace.s16 : AppSpace.s28;
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
            inset,
            _gap,
            inset,
            MediaQuery.paddingOf(context).bottom + inset,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              UsageSummary(
                stats: c.stats,
                rangeLabel: usagePresetLabel(l10n, c.preset),
                compact: narrow,
              ),
              const SizedBox(height: _gap),
              UsageToolbar(controller: c),
              const SizedBox(height: _gap),
              if (c.isLoading)
                const UsageLoadingCard()
              else ...[
                UsageGroupCosts(stats: c.stats, groups: appState.allPricingGroups),
                if (c.stats.groupCosts.isNotEmpty) const SizedBox(height: _gap),
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
            ],
          ),
        );
      },
    );
  }
}
