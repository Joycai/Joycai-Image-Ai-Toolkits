import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design_tokens.dart';
import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../state/app_state.dart';
import '../../widgets/glass/app_glass.dart';
import '../../widgets/glass/glass_controls.dart';
import '../../widgets/pricing_group_manager.dart';
import 'widgets/usage_chrome.dart';
import 'widgets/usage_controller.dart';
import 'widgets/usage_view_desktop.dart';
import 'widgets/usage_view_mobile.dart';

/// Token-usage metrics (`D2`).
///
/// On a phone: a glass header with the title, refresh, Clear All and the two
/// tabs, over a scroll of cards. On tablet and desktop: underlined tabs on the
/// canvas above a scrolling flow of opaque cards.
class TokenUsageScreen extends StatefulWidget {
  const TokenUsageScreen({super.key});

  @override
  State<TokenUsageScreen> createState() => _TokenUsageScreenState();
}

class _TokenUsageScreenState extends State<TokenUsageScreen> {
  int _viewIndex = 0;

  /// The phone header and the phone usage tab act on the same data. Created
  /// on first phone layout; the view loads it when it mounts.
  UsageController? _phoneController;

  static const double _desktopTabRowHeight = 52;
  static const double _tabletTabRowHeight = 48;
  static const double _phoneTitleHeight = 52;
  static const double _phoneTabBarHeight = AppSize.touch;

  @override
  void dispose() {
    _phoneController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (Responsive.isMobile(context)) return _buildPhone(context);

    final desktop = Responsive.isDesktop(context);
    final inset = desktop ? AppSpace.s28 : AppSpace.s16;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: inset),
            child: _ViewTabs(
              height: desktop ? _desktopTabRowHeight : _tabletTabRowHeight,
              index: _viewIndex,
              onSelect: (index) => setState(() => _viewIndex = index),
            ),
          ),
          Expanded(
            child: _viewIndex == 0
                ? const UsageViewDesktop()
                : _buildFeeGroups(context, inset: inset, top: 12, cardPadding: desktop ? AppSpace.s22 : AppSpace.s16),
          ),
        ],
      ),
    );
  }

  /// The fee-group editor, embedded in a card — the same component the fee
  /// management dialog hosts.
  Widget _buildFeeGroups(
    BuildContext context, {
    required double inset,
    required double top,
    required double cardPadding,
  }) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(inset, top, inset, MediaQuery.paddingOf(context).bottom + inset),
      child: UsagePanel(
        padding: EdgeInsets.all(cardPadding),
        child: const PricingGroupManager(mode: PricingGroupManagerMode.section),
      ),
    );
  }

  Widget _buildPhone(BuildContext context) {
    final controller = _phoneController ??= UsageController(
      models: () => Provider.of<AppState>(context, listen: false).allModels,
      pageSize: 50,
    );
    final top = MediaQuery.paddingOf(context).top;
    final headerHeight = top + _phoneTitleHeight + _phoneTabBarHeight;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Positioned.fill(
              child: TabBarView(
                children: [
                  UsageViewMobile(controller: controller, topInset: headerHeight),
                  _buildFeeGroups(
                    context,
                    inset: AppSpace.s16,
                    top: headerHeight + 12,
                    cardPadding: AppSpace.s16,
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              right: 0,
              child: _PhoneHeader(controller: controller, topPadding: top),
            ),
          ],
        ),
      ),
    );
  }
}

/// The tabs naming the view, floating on the canvas above everything the view
/// owns.
///
/// They sit outside the cards on purpose. Inside a card header they moved: the
/// usage view stacks a hero above its cards and the fee-group view does not,
/// so switching slid the tabs down the screen. Navigation cannot move under
/// the pointer that is aiming at it, so it cannot live inside content that
/// changes around it. The underline also keeps them from reading as a second
/// copy of the range filter, which is a segmented track.
class _ViewTabs extends StatelessWidget {
  const _ViewTabs({required this.height, required this.index, required this.onSelect});

  final double height;
  final int index;
  final ValueChanged<int> onSelect;

  /// Between the two tabs, as drawn.
  static const double _gap = 20;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final labels = [l10n.usage, l10n.feeGroups];

    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final (i, label) in labels.indexed) ...[
            if (i > 0) const SizedBox(width: _gap),
            _ViewTab(label: label, selected: i == index, onTap: () => onSelect(i)),
          ],
        ],
      ),
    );
  }
}

class _ViewTab extends StatelessWidget {
  const _ViewTab({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  static const double _height = 40;
  static const double _underline = 2;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final base = Theme.of(context).textTheme.titleMedium!;
    final selectedStyle = base.copyWith(fontWeight: FontWeight.w600, color: colorScheme.onAccentTint);
    final style = selected
        ? selectedStyle
        : base.copyWith(fontWeight: FontWeight.w500, color: colorScheme.onSurfaceVariant);

    // Every tab is at least as wide as its label in the selected weight, so
    // selecting one never nudges the tab beside it.
    final minWidth = measureGlassText(context, label, selectedStyle).ceilToDouble();

    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: selected ? null : onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: SizedBox(
          height: _height,
          child: IntrinsicWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minWidth: minWidth),
                      child: Text(label, style: style, maxLines: 1),
                    ),
                  ),
                ),
                ColoredBox(
                  color: selected ? colorScheme.primary : Colors.transparent,
                  child: const SizedBox(height: _underline),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The phone's one full-width glass layer: title, refresh and Clear All over
/// the two tabs.
class _PhoneHeader extends StatelessWidget {
  const _PhoneHeader({required this.controller, required this.topPadding});

  final UsageController controller;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AppGlass(
      grade: GlassGrade.bar,
      edges: GlassEdges.bottom,
      shadow: false,
      child: Padding(
        padding: EdgeInsets.only(top: topPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: _TokenUsageScreenState._phoneTitleHeight,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(start: AppSpace.s16, end: AppSpace.s6),
                child: Row(
                  children: [
                    Expanded(
                      child: Builder(
                        builder: (context) => Text(
                          l10n.tokenUsageMetrics,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                color: GlassInk.maybeOf(context)?.ink,
                              ),
                        ),
                      ),
                    ),
                    ListenableBuilder(
                      listenable: controller,
                      builder: (context, _) => Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GlassIconButton(
                            icon: Icons.refresh,
                            tooltip: l10n.refresh,
                            onPressed: controller.isLoading ? null : () => controller.load(reset: true),
                          ),
                          GlassIconButton(
                            icon: Icons.delete_sweep_outlined,
                            tooltip: l10n.clearAll,
                            danger: true,
                            onPressed: () => showClearAllUsageDialog(context, controller),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              height: _TokenUsageScreenState._phoneTabBarHeight,
              child: TabBar(
                padding: const EdgeInsets.fromLTRB(AppSpace.s16, 0, AppSpace.s16, AppSpace.s6),
                tabs: [
                  Tab(height: _TokenUsageScreenState._phoneTabBarHeight - AppSpace.s6, text: l10n.usage),
                  Tab(height: _TokenUsageScreenState._phoneTabBarHeight - AppSpace.s6, text: l10n.feeGroups),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
