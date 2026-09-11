import 'package:flutter/material.dart';

import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/app_breathing_dot.dart';
import '../../../widgets/glass/app_glass.dart';
import '../../../widgets/glass/glass_controls.dart';

/// The prompt assistant's controls in the workbench's floating glass toolbar
/// (`A3a · 1a`, `A3b · 1a`): what this is, which brain is answering, whether
/// it is running, the session actions, and the one thing the screen builds
/// towards.
///
/// It fills the slot the toolbar gives it after the back button and the tool
/// switch, and degrades inside that slot by measurement, in this order: the
/// session actions lose their labels, the mode badge goes, the primary action
/// takes its short label, the session actions fold into a menu, the running
/// pill keeps only its dot, the title goes.
class PromptOptimizerToolbar extends StatelessWidget {
  final VoidCallback onNewSession;
  final VoidCallback onHistory;
  final VoidCallback onApply;
  final bool isRefining;
  final bool canApply;

  /// Localised name of the session's mode, shown in the badge beside the title.
  /// Null hides the badge.
  final String? modeLabel;

  /// Kept for callers; the badge is text on glass and carries no glyph now.
  final IconData modeIcon;

  /// Tool steps the running turn has taken so far. Null while nothing is
  /// running; zero while the agent is thinking but has called nothing yet.
  final int? runningSteps;

  /// Knowledge edits staged and waiting on the user. While there are any they
  /// take the primary slot (`A3b · 1a`): in library-edit mode the session's
  /// product is the changes, and applying a prompt would not resolve them.
  final int pendingKbEdits;
  final VoidCallback? onWriteAllKbEdits;
  final VoidCallback? onDiscardAllKbEdits;

  const PromptOptimizerToolbar({
    super.key,
    required this.onNewSession,
    required this.onHistory,
    required this.onApply,
    required this.isRefining,
    required this.canApply,
    this.modeLabel,
    this.modeIcon = Icons.smart_toy_outlined,
    this.runningSteps,
    this.pendingKbEdits = 0,
    this.onWriteAllKbEdits,
    this.onDiscardAllKbEdits,
  });

  static const double _gap = 4;
  static const double _leading = 6;

  static TextStyle _titleStyle(BuildContext context) =>
      Theme.of(context).textTheme.titleMedium!.metricsOnly.copyWith(fontWeight: FontWeight.w600);

  static TextStyle _chipStyle(BuildContext context) =>
      Theme.of(context).textTheme.labelSmall!.metricsOnly.copyWith(fontWeight: FontWeight.w500);

  static double _tintedWidth(BuildContext context, String label) =>
      12 + AppSize.iconMd + 6 + measureGlassText(context, label, _TintedAction.labelStyle(context)) + 12;

  static double _chipWidth(BuildContext context, String label, {bool dot = false}) =>
      8 + (dot ? 6 + 4 : 0) + measureGlassText(context, label, _chipStyle(context)) + 8;

  /// The width these controls take with everything labelled — what the
  /// toolbar weighs its tool switch against.
  static double preferredWidth(
    BuildContext context, {
    String? modeLabel,
    int pendingKbEdits = 0,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final title = measureGlassText(context, l10n.promptOptimizer, _titleStyle(context));
    final badge = modeLabel == null ? 0.0 : 8 + _chipWidth(context, l10n.optModeBadgeAgent(modeLabel));
    final session = GlassIconButton.widthFor(context, label: l10n.optHistory) +
        _gap +
        GlassIconButton.widthFor(context, label: l10n.optNewSession);
    final primary = pendingKbEdits > 0
        ? GlassIconButton.widthFor(context, label: l10n.kbEditDiscardAll, hasIcon: false) +
            _gap +
            _tintedWidth(context, l10n.kbEditConfirmAll(pendingKbEdits))
        : _tintedWidth(context, l10n.applyToWorkbench);
    return (_leading + title + badge + AppSpace.s16 + session + _gap + primary).ceilToDouble();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) => _build(context, constraints.maxWidth));
  }

  Widget _build(BuildContext context, double width) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final glass = GlassInk.maybeOf(context);
    final ink = glass?.ink ?? scheme.onSurface;
    final running = isRefining || runningSteps != null;
    final steps = runningSteps ?? 0;
    final runningText = steps == 0 ? l10n.optRunning : l10n.optRunningStep(steps);
    final hasPending = pendingKbEdits > 0;

    bool showTitle = true;
    bool showBadge = modeLabel != null;
    bool sessionLabels = true;
    bool sessionInMenu = false;
    bool shortPrimary = false;
    bool runningLabel = true;

    String primaryLabel() => hasPending
        ? (shortPrimary ? l10n.kbEditApply : l10n.kbEditConfirmAll(pendingKbEdits))
        : (shortPrimary ? l10n.apply : l10n.applyToWorkbench);

    double measure() {
      double w = _leading;
      if (showTitle) w += measureGlassText(context, l10n.promptOptimizer, _titleStyle(context));
      if (showBadge) w += 8 + _chipWidth(context, l10n.optModeBadgeAgent(modeLabel!));
      if (running) w += 8 + (runningLabel ? _chipWidth(context, runningText, dot: true) : 22);
      w += AppSpace.s16;
      if (sessionInMenu) {
        w += AppSize.control;
      } else {
        w += GlassIconButton.widthFor(context, label: sessionLabels ? l10n.optHistory : null) +
            _gap +
            GlassIconButton.widthFor(context, label: sessionLabels ? l10n.optNewSession : null);
      }
      w += _gap;
      if (hasPending && !shortPrimary) {
        w += GlassIconButton.widthFor(context, label: l10n.kbEditDiscardAll, hasIcon: false) + _gap;
      }
      w += _tintedWidth(context, primaryLabel());
      return w;
    }

    if (measure() > width) sessionLabels = false;
    if (measure() > width) showBadge = false;
    if (measure() > width) shortPrimary = true;
    if (measure() > width) sessionInMenu = true;
    if (measure() > width) runningLabel = false;
    if (measure() > width) showTitle = false;

    final children = <Widget>[
      const SizedBox(width: _leading),
      if (showTitle)
        Flexible(
          child: Text(
            l10n.promptOptimizer,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            style: _titleStyle(context),
          ),
        ),
      // Which brain is answering: a fact about the session, not a state, so
      // it is mono on a faint wash of the glass ink rather than the accent.
      if (showBadge) ...[
        const SizedBox(width: 8),
        Flexible(
          child: _Chip(
            label: l10n.optModeBadgeAgent(modeLabel!),
            background: ink.withValues(alpha: 0.10),
            foreground: ink,
            mono: true,
          ),
        ),
      ],
      if (running) ...[
        const SizedBox(width: 8),
        Flexible(
          child: _Chip(
            label: runningLabel ? runningText : null,
            tooltip: runningText,
            background: scheme.accentTint,
            foreground: scheme.onAccentTint,
            dot: scheme.primary,
          ),
        ),
      ],
      const Expanded(child: SizedBox()),
      if (sessionInMenu)
        MenuAnchor(
          menuChildren: [
            MenuItemButton(
              leadingIcon: const Icon(Icons.history, size: AppSize.iconLg),
              // Off during a turn: restoring another conversation mid-run
              // swaps the session out from under the agent.
              onPressed: isRefining ? null : onHistory,
              child: Text(l10n.optHistory),
            ),
            MenuItemButton(
              leadingIcon: const Icon(Icons.add_comment_outlined, size: AppSize.iconLg),
              onPressed: isRefining ? null : onNewSession,
              child: Text(l10n.optNewSession),
            ),
          ],
          builder: (context, controller, _) => GlassIconButton(
            icon: Icons.more_vert,
            tooltip: l10n.more,
            active: controller.isOpen,
            onPressed: () => controller.isOpen ? controller.close() : controller.open(),
          ),
        )
      else ...[
        GlassIconButton(
          icon: Icons.history,
          label: sessionLabels ? l10n.optHistory : null,
          tooltip: sessionLabels ? null : l10n.optHistory,
          onPressed: isRefining ? null : onHistory,
        ),
        const SizedBox(width: _gap),
        GlassIconButton(
          icon: Icons.add_comment_outlined,
          label: sessionLabels ? l10n.optNewSession : null,
          tooltip: sessionLabels ? null : l10n.optNewSession,
          onPressed: isRefining ? null : onNewSession,
        ),
      ],
      const SizedBox(width: _gap),
      if (hasPending) ...[
        if (!shortPrimary) ...[
          GlassIconButton(
            label: l10n.kbEditDiscardAll,
            danger: true,
            onPressed: onDiscardAllKbEdits,
          ),
          const SizedBox(width: _gap),
        ],
        _TintedAction(
          icon: Icons.save_outlined,
          label: primaryLabel(),
          tooltip: shortPrimary ? l10n.kbEditConfirmAll(pendingKbEdits) : null,
          onPressed: onWriteAllKbEdits,
        ),
      ] else
        // The one solid accent on the screen, as tinted glass because it
        // stands on a glass bar. Disabled until there is a prompt to apply.
        _TintedAction(
          icon: Icons.login,
          label: primaryLabel(),
          tooltip: shortPrimary ? l10n.applyToWorkbench : null,
          onPressed: canApply ? onApply : null,
        ),
    ];

    return Row(children: children);
  }
}

/// A small r4 chip on the bar: the mode badge and the running pill.
class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.background,
    required this.foreground,
    this.tooltip,
    this.dot,
    this.mono = false,
  });

  final String? label;
  final String? tooltip;
  final Color background;
  final Color foreground;
  final Color? dot;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final base = PromptOptimizerToolbar._chipStyle(context);
    final style = (mono ? base.mono.copyWith(fontWeight: FontWeight.w400) : base).copyWith(color: foreground);
    Widget chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot != null) AppBreathingDot(color: dot!, size: 6),
          if (dot != null && label != null) const SizedBox(width: 4),
          if (label != null)
            Flexible(
              child: Text(
                label!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: style,
              ),
            ),
        ],
      ),
    );
    if (tooltip != null && label == null) chip = Tooltip(message: tooltip!, child: chip);
    return chip;
  }
}

/// The accent's solid form on glass: a 32px tinted-glass button.
class _TintedAction extends StatelessWidget {
  const _TintedAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final String label;
  final String? tooltip;
  final VoidCallback? onPressed;

  static TextStyle labelStyle(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall!.metricsOnly.copyWith(fontWeight: FontWeight.w600);

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    Widget button = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: onPressed,
        child: AppTintedGlass(
          enabled: enabled,
          child: SizedBox(
            height: AppSize.control,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: AppSize.iconMd),
                  const SizedBox(width: 6),
                  Text(label, maxLines: 1, style: labelStyle(context)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (tooltip != null) button = Tooltip(message: tooltip!, child: button);
    return Semantics(button: true, enabled: enabled, label: tooltip ?? label, child: button);
  }
}
