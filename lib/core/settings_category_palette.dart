import 'package:flutter/material.dart';

import '../screens/settings/settings_screen.dart';

/// Identity colours for the five settings categories.
///
/// These say "this is the appearance section", not "this is healthy" or "look
/// at this". Three of them happen to be the same hues as `AppSemanticColors`'
/// info, success and warning — `D1 12a` picks them deliberately, because a
/// five-way palette wants five hues that already read as distinct, and the
/// spec's semantic trio is where those live. They are copied here rather than
/// read from that class on purpose: the moment success turns a different green
/// for a *meaning* reason, the connectivity plate must not follow it.
///
/// Fixed, like `fee_group_palette`'s, and for the same reason: a category's
/// colour is how the eye finds the row again after a week, so it cannot move
/// when the user changes their theme. That includes 关于, which `D1` draws in
/// the accent — at the blue seed the accent and this blue are the same value,
/// so the frame cannot tell the two intentions apart. Fixed is the reading
/// that keeps the five plates a set.
const Map<SettingsCategory, Color> _settingsCategoryPalette = {
  SettingsCategory.appearance: Color(0xFF1F6FD6), // azure
  SettingsCategory.connectivity: Color(0xFF1A9E57), // jade
  SettingsCategory.application: Color(0xFFE09030), // amber
  SettingsCategory.data: Color(0xFF8B46D6), // violet
  SettingsCategory.about: Color(0xFF4A72E8), // indigo
};

/// The plate colour belonging to [category].
Color settingsCategoryColor(SettingsCategory category) =>
    _settingsCategoryPalette[category]!;
