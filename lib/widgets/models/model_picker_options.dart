import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../models/llm_channel.dart';
import '../../models/llm_model.dart';
import '../searchable_picker.dart';

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
      badgeColor:
          channel?.tag == null ? null : Color(channel!.tagColor ?? AppConstants.defaultTagColor),
    );
