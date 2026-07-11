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
            children: [
              const UsageViewMobile(),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: const PricingGroupManager(mode: PricingGroupManagerMode.section),
                ),
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
        child: _viewIndex == 0
            ? (isNarrow
                ? _buildNarrowUsageCard(l10n, colorScheme)
                : UsageViewDesktop(viewSwitcher: _buildViewSwitcher(l10n)))
            : _buildFeeGroupsCard(l10n, colorScheme),
      ),
    );
  }

  /// Compact segmented control toggling between the usage and fee-groups
  /// views. Lives in the header row of whichever card is showing.
  Widget _buildViewSwitcher(AppLocalizations l10n) {
    return SegmentedButton<int>(
      segments: [
        ButtonSegment(value: 0, label: Text(l10n.usage)),
        ButtonSegment(value: 1, label: Text(l10n.feeGroups)),
      ],
      selected: {_viewIndex},
      onSelectionChanged: (selection) => setState(() => _viewIndex = selection.first),
      showSelectedIcon: false,
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
      ),
    );
  }

  /// 56px header row living inside the top of a panel card (same pattern as
  /// the file browser): icon + title on the left, switcher on the right.
  Widget _buildCardHeader(
    ColorScheme colorScheme, {
    required IconData icon,
    required String title,
    required AppLocalizations l10n,
  }) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withAlpha(90))),
      ),
      child: Row(
        children: [
          Icon(icon, size: 22, color: colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 16),
          _buildViewSwitcher(l10n),
        ],
      ),
    );
  }

  /// Tablet-width usage view: the compact usage layout hosted in a single
  /// panel card with the shared header on top.
  Widget _buildNarrowUsageCard(AppLocalizations l10n, ColorScheme colorScheme) {
    return PanelCard(
      child: Column(
        children: [
          _buildCardHeader(
            colorScheme,
            icon: Icons.analytics_outlined,
            title: l10n.tokenUsageMetrics,
            l10n: l10n,
          ),
          const Expanded(child: UsageViewMobile()),
        ],
      ),
    );
  }

  Widget _buildFeeGroupsCard(AppLocalizations l10n, ColorScheme colorScheme) {
    return PanelCard(
      child: Column(
        children: [
          _buildCardHeader(
            colorScheme,
            icon: Icons.sell_outlined,
            title: l10n.feeGroups,
            l10n: l10n,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: const PricingGroupManager(mode: PricingGroupManagerMode.section),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
