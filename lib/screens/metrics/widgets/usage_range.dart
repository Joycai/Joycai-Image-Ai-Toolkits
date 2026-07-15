import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

/// The range presets the usage views offer, in the order they are shown.
const List<String> usagePresets = ['today', 'week', 'month', 'year'];

/// The dates [preset] means, resolved against now.
DateTimeRange usageRangeForPreset(String preset) {
  final now = DateTime.now();

  final start = switch (preset) {
    'today' => DateTime(now.year, now.month, now.day),
    'month' => DateTime(now.year, now.month - 1, now.day),
    'year' => DateTime(now.year - 1, now.month, now.day),
    _ => now.subtract(const Duration(days: 7)),
  };

  return DateTimeRange(start: start, end: now);
}

/// [preset]'s name in the user's language — the label on its button, and the
/// period the summary totals say they cover.
String usagePresetLabel(AppLocalizations l10n, String preset) {
  return switch (preset) {
    'today' => l10n.today,
    'month' => l10n.lastMonth,
    'year' => l10n.thisYear,
    _ => l10n.lastWeek,
  };
}
