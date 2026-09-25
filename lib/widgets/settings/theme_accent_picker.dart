import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_semantic_colors.dart';
import '../../core/app_theme.dart';
import '../../core/constants.dart';
import '../../core/custom_accent.dart';
import '../../core/design_tokens.dart';
import '../../core/responsive.dart';
import '../../core/theme_accent.dart';
import '../../l10n/app_localizations.dart';
import '../ui/app_button.dart';
import '../ui/app_dialog.dart';
import '../ui/app_field_size.dart';
import '../ui/app_section_label.dart';
import '../ui/app_switch.dart';
import 'dual_tone_swatch.dart';

part 'theme_accent/accent_cards.dart';
part 'theme_accent/accent_dots.dart';
part 'theme_accent/custom_accent_dialog.dart';
part 'theme_accent/custom_accent_pair.dart';
part 'theme_accent/hue_ring.dart';

/// The theme-colour chooser on the appearance page — design `E1 · 1a / 1b / 1e`.
///
/// Two forms of the same control, picked by width:
///
/// - **Desktop and tablet: preview cards** (`1a`). Each card is a miniature of
///   both modes side by side — a filled button, a switch and a selected row,
///   drawn in the exact shade each mode will use, with that shade's value — so
///   the dark half of a pair can be judged *before* it is chosen.
/// - **Mobile: dual-tone dots** (`1e`). Four per row, two rows; the pair's
///   values are on the long-press tooltip instead of in the picture.
///
/// Both end in **Custom…**, which opens [showCustomAccentDialog] — but only
/// when the caller passes [onCustomSeed]; without it the tile is not drawn.
///
/// Stateless on purpose: it reports the chosen preset's *key* (or the custom
/// seed) and lets the caller persist it, so it can be photographed by the
/// gallery and tested without an [AppState].
class ThemeAccentPicker extends StatelessWidget {
  const ThemeAccentPicker({
    super.key,
    required this.selected,
    required this.onSelect,
    this.customSeed,
    this.onCustomSeed,
  });

  /// The pair currently in use — compared by value against each preset.
  final ThemeAccent selected;

  /// Called with the [AppConstants.presetThemes] key the user picked.
  final ValueChanged<String> onSelect;

  /// The seed of the custom colour in use, if [selected] is one. Seeds the
  /// dialog; null opens it on the current accent.
  final Color? customSeed;

  /// Called with the seed the custom-colour dialog was applied with.
  final ValueChanged<Color>? onCustomSeed;

  bool get _customActive => !AppConstants.presetThemes.values.contains(selected);

  Future<void> _openCustom(BuildContext context) async {
    final Color? seed = await showCustomAccentDialog(
      context,
      initialSeed: customSeed ?? selected.light,
    );
    if (seed != null) onCustomSeed?.call(seed);
  }

  @override
  Widget build(BuildContext context) {
    return Responsive.isMobile(context) ? _DotGrid(picker: this) : _CardGrid(picker: this);
  }
}

/// The rendered value, not the seed — the same rule the swatch follows, so
/// every number shown is a colour the app actually paints.
String _hex(Color c) => CustomAccent.hex(c);

class _Hint extends StatelessWidget {
  const _Hint(this.text, {required this.maxWidth});

  final String text;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          height: AppType.proseHeight,
        ),
      ),
    );
  }
}

/// The ring's own colours — `CustomAccent.seedForHue` every 15°, closing back
/// on 0° — solved once, on first use. The ring, the desktop tile (unrolled
/// left to right) and the phone dot all paint from this one list, so the
/// colour under the ring's handle is the colour the tile promised.
final List<Color> _hueStops = [
  for (int h = 0; h <= 360; h += 15) CustomAccent.seedForHue(h.toDouble()),
];
