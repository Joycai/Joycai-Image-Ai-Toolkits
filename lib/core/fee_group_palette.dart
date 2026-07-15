import 'package:flutter/material.dart';

/// Identity colours for fee groups.
///
/// A group's colour is derived from its id, so the same group keeps the same
/// hue everywhere it appears: the accent on its card in the fee-group tab, and
/// the cost bar under its name in the usage tab. That is the colour's whole
/// job — it says "this group", not "this billing mode" or "this much money".
///
/// Hues the app has already spent on meaning elsewhere are left out: orange is
/// cost, and the blue/teal/green trio belongs to input/cache/output token
/// prices. A group tinted amber next to a total tinted amber would claim a
/// relationship that isn't there.
const List<Color> _feeGroupPalette = [
  Color(0xFF8B7BF7), // violet
  Color(0xFF4C8DFF), // azure
  Color(0xFF3FC1C9), // cyan
  Color(0xFF5BC17F), // jade
  Color(0xFFE072B8), // magenta
  Color(0xFF7A8BFF), // periwinkle
  Color(0xFFEB8C5A), // clay
];

/// The palette entry belonging to [groupId].
///
/// Keyed on the id rather than the position in the list: rows shift as groups
/// are added and deleted, and a colour that reshuffles under the user is worse
/// than no colour at all. Groups not yet saved (null id) share the first entry.
Color feeGroupAccent(int? groupId) {
  return _feeGroupPalette[(groupId ?? 0).abs() % _feeGroupPalette.length];
}
