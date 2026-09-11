import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_segmented_control.dart';
import '../../../widgets/glass/glass_controls.dart';
import 'usage_chrome.dart';
import 'usage_controller.dart';
import 'usage_range.dart';

/// The range toolbar on the canvas (`D2` ②): the dates the active preset
/// resolved to on the left — the presets say "last week", only the dates say
/// which week — and on the right the presets, Refresh and Clear All.
///
/// It degrades by measuring its own labels against the width it gets, never
/// by a breakpoint: first the dates drop their years, then Clear All drops its
/// label for its glyph, and last the dates go.
class UsageToolbar extends StatelessWidget {
  const UsageToolbar({super.key, required this.controller});

  final UsageController controller;

  /// The segmented control's geometry in its compact form: 10px either side
  /// of a label plus the 1px edge every chip carries, inside a 3px track.
  static const double _chipChrome = 10 * 2 + 2;
  static const double _trackChrome = 3 * 2;

  /// An outlined button's horizontal padding on either side of its content,
  /// and the gap between its glyph and label.
  static const double _buttonPadding = 14;
  static const double _buttonIconGap = 8;

  static const double _dateGap = AppSpace.s16;
  static const double _clusterGap = AppSpace.s10;
  static const double _buttonGap = AppSpace.s6;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final range = controller.range;
    final loading = controller.isLoading;

    final dateStyle = textTheme.labelSmall!.mono.copyWith(color: colorScheme.onSurfaceVariant);
    String dates(String pattern) {
      final fmt = DateFormat(pattern);
      return '${fmt.format(range.start)} → ${fmt.format(range.end)}';
    }

    final longDates = dates('yyyy-MM-dd');
    final shortDates = dates('MM-dd');

    return LayoutBuilder(
      builder: (context, constraints) {
        double measure(String text, TextStyle style) => measureGlassText(context, text, style);

        // The heavier weight for every chip: the selection moves, and the
        // track must not change width when it does.
        final chipStyle = textTheme.labelMedium!.copyWith(fontWeight: FontWeight.w600);
        final segmentWidth = _trackChrome +
            usagePresets.fold<double>(
              0,
              (sum, preset) => sum + measure(usagePresetLabel(l10n, preset), chipStyle) + _chipChrome,
            );
        final labelledClearWidth = _buttonPadding * 2 +
            AppSize.iconMd +
            _buttonIconGap +
            measure(l10n.clearAll, textTheme.labelLarge!);

        var dateText = longDates;
        var clearLabelled = true;
        var showDates = true;

        double needed() =>
            (showDates ? measure(dateText, dateStyle) + _dateGap : 0) +
            segmentWidth +
            _clusterGap +
            AppSize.iconButton +
            _buttonGap +
            (clearLabelled ? labelledClearWidth : AppSize.iconButton);

        final width = constraints.maxWidth;
        if (needed() > width) dateText = shortDates;
        if (needed() > width) clearLabelled = false;
        if (needed() > width) showDates = false;

        final cluster = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppSegmentedControl<String>(
              segments: [
                for (final preset in usagePresets)
                  AppSegment(
                    value: preset,
                    label: usagePresetLabel(l10n, preset),
                    enabled: !loading,
                  ),
              ],
              value: controller.preset,
              onChanged: controller.selectPreset,
              compact: true,
              style: AppSegmentStyle.raised,
            ),
            const SizedBox(width: _clusterGap),
            UsageToolIconButton(
              icon: Icons.refresh,
              tooltip: l10n.refresh,
              onPressed: loading ? null : () => controller.load(reset: true),
            ),
            const SizedBox(width: _buttonGap),
            if (clearLabelled)
              AppButton(
                label: l10n.clearAll,
                icon: Icons.delete_sweep_outlined,
                variant: AppButtonVariant.destructiveOutline,
                onPressed: () => showClearAllUsageDialog(context, controller),
              )
            else
              UsageToolIconButton(
                icon: Icons.delete_sweep_outlined,
                tooltip: l10n.clearAll,
                danger: true,
                onPressed: () => showClearAllUsageDialog(context, controller),
              ),
          ],
        );

        if (!showDates) {
          // Nothing left to give up: a mismeasured fit scrolls rather than
          // overflowing.
          return Align(
            alignment: AlignmentDirectional.centerEnd,
            child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: cluster),
          );
        }

        return Row(
          children: [
            Expanded(
              child: Text(dateText, style: dateStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: _dateGap),
            cluster,
          ],
        );
      },
    );
  }
}
