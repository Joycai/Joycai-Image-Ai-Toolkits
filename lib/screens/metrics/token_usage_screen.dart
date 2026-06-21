import 'package:flutter/material.dart';

import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/pricing_group_manager.dart';
import 'widgets/usage_view_desktop.dart';
import 'widgets/usage_view_mobile.dart';

class TokenUsageScreen extends StatefulWidget {
  const TokenUsageScreen({super.key});

  @override
  State<TokenUsageScreen> createState() => _TokenUsageScreenState();
}

class _TokenUsageScreenState extends State<TokenUsageScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isNarrow = Responsive.isNarrow(context);
    final colorScheme = Theme.of(context).colorScheme;
    final isMobile = Responsive.isMobile(context);

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

    return Column(
      children: [
        // 60px screen header
        Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withAlpha(90))),
          ),
          child: Row(
            children: [
              Icon(Icons.analytics_outlined, size: 24, color: colorScheme.primary),
              const SizedBox(width: 12),
              Text(
                l10n.tokenUsageMetrics,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ],
          ),
        ),
        // Tab bar
        Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withAlpha(60))),
          ),
          child: TabBar(
            controller: _tabController,
            tabs: [Tab(text: l10n.usage), Tab(text: l10n.feeGroups)],
          ),
        ),
        // Tab content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              isNarrow ? const UsageViewMobile() : const UsageViewDesktop(),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: const PricingGroupManager(mode: PricingGroupManagerMode.section),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
