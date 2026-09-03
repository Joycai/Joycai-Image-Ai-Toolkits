import 'package:flutter/material.dart';

import '../core/design_tokens.dart';

/// The two sizes the spec gives a select-like field, and the caption over it.
///
/// `10a` 「下拉 SELECT · 唯一几何 · 两档」: one geometry, two sizes, and a
/// rule for choosing — a field takes the size of the inputs on its row. The
/// workbench sidebar and a dialog's compact form are [regular]; a settings or
/// editor form and a page-level toolbar are [large]. One screen never mixes
/// them.
///
/// [large] is the theme's own input height (the 12/10 insets around a 13px
/// line come to 40), so a large field needs nothing pinned and sits beside an
/// `AppTextField` as the same thing. [regular] is pinned to 32.
enum AppFieldSize {
  /// 32 high · inset 10 · value 12/500 · chevron 14 · caption 11.5/600, 4 below.
  regular,

  /// 40 high (the theme's) · inset 12 · value 13/500 · chevron 16 · caption
  /// 12/500, 6 below.
  large;

  /// The box's height, or null to take the theme's.
  double? get height => this == regular ? 32 : null;

  /// Horizontal inset of the value and the chevron.
  double get inset => this == regular ? 10 : 12;

  /// The trailing chevron's size, and the gap it keeps from the value.
  double get chevron => this == regular ? 14 : AppSize.iconSm;
  double get chevronGap => this == regular ? 7 : 9;

  /// Space between the caption and the box.
  double get captionGap => this == regular ? 4 : 6;

  /// The value's type: 500 weight at both sizes, one step apart. `labelLarge`
  /// *is* the spec's 13/500; the regular size has no slot at 12.5 and takes
  /// `bodySmall` at the same weight.
  TextStyle? valueStyle(TextTheme textTheme) => this == regular
      ? textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500)
      : textTheme.labelLarge;

  /// The caption's type. `labelMedium` (11.5) at 600 for the regular size;
  /// 12 at 500 for the large, which is `bodySmall`'s size at the label weight.
  TextStyle? captionStyle(TextTheme textTheme) => this == regular
      ? textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600)
      : textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500);
}
