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

class _TokenUsageScreenState extends State<TokenUsageScreen> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isNarrow = Responsive.isNarrow(context);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.tokenUsageMetrics),
          bottom: TabBar(
            tabs: [
              Tab(text: l10n.usage),
              Tab(text: l10n.feeGroups),
            ],
          ),
        ),
        body: TabBarView(
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
    );
  }
}
