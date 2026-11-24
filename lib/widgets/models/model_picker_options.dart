import 'package:material_ui/material_ui.dart';

import '../../core/constants.dart';
import '../../core/model_kind_palette.dart';
import '../../l10n/app_localizations.dart';
import '../../models/llm_channel.dart';
import '../../models/llm_model.dart';
import '../../services/catalogue/builtin_model_specs.dart';
import '../../services/catalogue/context_window_scale.dart';
import '../ui/searchable_picker.dart';
import 'fee_group_summary.dart';

/// Turns the app's two pickable records into [PickerOption]s.
///
/// Four screens choose a model or a channel — the workbench's image and video
/// panels, the shared chat selector behind three dialogs, and the settings
/// screen's sub-agent binding. Each had built its own row, which is how the
/// same channel tag came to be drawn at three paddings and how the fallback
/// tag colour ended up written out in seven places. The rows are the same
/// rows; they belong in one place.

/// A channel, badged with its tag.
PickerOption<int> channelPickerOption(LLMChannel c) => PickerOption<int>(
  value: c.id!,
  label: c.displayName,
  badge: c.tag,
  badgeColor: c.tag == null ? null : Color(c.tagColor ?? AppConstants.defaultTagColor),
);

/// A model, with its id as the second line and its channel's tag as a badge.
///
/// The id is carried rather than dropped so that two entries a relay names
/// identically stay tellable apart, and so searching for `gpt-image` finds a
/// model someone renamed to "Fast". [channel] is optional because the two
/// workbench panels already filter to one channel, and repeating its tag on
/// every row there would say nothing.
PickerOption<int> modelPickerOption(LLMModel m, {LLMChannel? channel}) => PickerOption<int>(
  value: m.id!,
  label: m.modelName,
  secondary: m.modelId == m.modelName ? null : m.modelId,
  badge: channel?.tag,
  badgeColor: channel?.tag == null
      ? null
      : Color(channel!.tagColor ?? AppConstants.defaultTagColor),
);

/// Formats a concise one-line spec summary (context / output / thinking / price)
/// for a built-in model preset.
String formatBuiltinSpecBrief(
  AppLocalizations l10n,
  BuiltinModelSpec spec, {
  bool includePricing = true,
}) {
  final parts = <String>[];
  if (spec.contextWindow != null) {
    parts.add('${ContextWindowScale.label(spec.contextWindow!)} ctx');
  }
  if (spec.maxOutputTokens != null) {
    parts.add('${ContextWindowScale.label(spec.maxOutputTokens!)} out');
  }
  if (spec.supportsThinking) {
    parts.add(l10n.modelPresetThinkingTag);
  }
  if (includePricing) {
    final price = feeGroupSummary(l10n, spec.pricing.toPricingGroup(name: spec.displayName));
    if (price.isNotEmpty) parts.add(price);
  }
  return parts.join(' · ');
}

/// A built-in model preset row for [showSearchablePicker].
PickerOption<BuiltinModelSpec> builtinModelPresetOption(
  AppLocalizations l10n,
  BuiltinModelSpec spec, {
  bool pricingFocused = false,
}) {
  final summary = pricingFocused
      ? feeGroupSummary(l10n, spec.pricing.toPricingGroup(name: spec.displayName))
      : formatBuiltinSpecBrief(l10n, spec);
  return PickerOption<BuiltinModelSpec>(
    value: spec,
    label: spec.displayName,
    secondary: [spec.canonicalId, if (summary.isNotEmpty) summary].join(' · '),
    badge: spec.provider,
    badgeColor: modelTagAccent(spec.tag),
    marker: spec.supportsThinking ? l10n.modelPresetThinkingTag : null,
    markerIcon: spec.supportsThinking ? Icons.psychology_outlined : null,
  );
}
