import 'package:flutter/material.dart';

import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/panel_resizer.dart';
import '../../widgets/pricing_group_manager.dart';
import 'widgets/usage_view_desktop.dart';
import 'widgets/usage_view_mobile.dart';

/// Token-usage metrics screen. On mobile it keeps the classic full-bleed
/// AppBar + tabs shell; on tablet/desktop it uses the inset-panel design:
/// cards on a `surfaceContainer` canvas with the header inside the main card
/// and a segmented switcher toggling between usage and fee groups.
class TokenUsageScreen extends StatefulWidget {
  const TokenUsageScreen({super.key});

  @override
  State<TokenUsageScreen> createState() => _TokenUsageScreenState();
}

/// Height of the canvas tab bar above the view's cards.
const double _tabBarHeight = 44;

class _TokenUsageScreenState extends State<TokenUsageScreen> {
  int _viewIndex = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final isMobile = Responsive.isMobile(context);
    final isNarrow = Responsive.isNarrow(context);

    if (isMobile) {
      return DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: Text(l10n.tokenUsageMetrics),
            bottom: TabBar(
              tabs: [Tab(text: l10n.usage), Tab(text: l10n.feeGroups)],
            ),
          ),
          body: TabBarView(
            children: const [
              UsageViewMobile(),
              SingleChildScrollView(
                padding: EdgeInsets.all(16),
                child: PricingGroupManager(mode: PricingGroupManagerMode.section),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainer,
      body: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildViewTabs(l10n, colorScheme),
            const SizedBox(height: 8),
            Expanded(
              child: _viewIndex == 0
                  ? (isNarrow ? _buildNarrowUsageCard() : const UsageViewDesktop())
                  : _buildFeeGroupsCard(),
            ),
          ],
        ),
      ),
    );
  }

  /// Tabs naming the view, floating on the canvas above everything the view
  /// owns — the same transparent-on-canvas treatment as the nav rail.
  ///
  /// They sit outside the cards on purpose. Inside a card header they moved:
  /// the usage view stacks summary cards above its card and the fee-group view
  /// does not, so switching tabs slid the tabs themselves ~150px down the
  /// screen. Navigation cannot move under the pointer that is aiming at it, so
  /// it cannot live inside content that changes around it.
  ///
  /// The underline shape is still doing its other job: the range filter these
  /// used to sit beside is a pill segmented control, and only filters the page
  /// you are already on.
  Widget _buildViewTabs(AppLocalizations l10n, ColorScheme colorScheme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildTab(l10n.usage, Icons.analytics_outlined, 0, colorScheme),
        _buildTab(l10n.feeGroups, Icons.sell_outlined, 1, colorScheme),
      ],
    );
  }

  Widget _buildTab(String label, IconData icon, int index, ColorScheme colorScheme) {
    final selected = _viewIndex == index;
    final color = selected ? colorScheme.primary : colorScheme.onSurfaceVariant;

    return InkWell(
      onTap: selected ? null : () => setState(() => _viewIndex = index),
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: _tabBarHeight,
        child: IntrinsicWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Padding(
                  // Lines the first tab's icon up with the card content below.
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 18, color: color),
                      const SizedBox(width: 8),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                height: 3,
                decoration: BoxDecoration(
                  color: selected ? colorScheme.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Tablet-width usage view: the compact usage layout hosted in a panel card.
  Widget _buildNarrowUsageCard() {
    return const PanelCard(child: UsageViewMobile());
  }

  /// The groups fill the card rather than sitting in a centred column: they
  /// are a grid now, and it is the grid that decides how many fit across.
  Widget _buildFeeGroupsCard() {
    return const PanelCard(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(24),
        child: PricingGroupManager(mode: PricingGroupManagerMode.section),
      ),
    );
  }
}
