import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';

/// A tree row's disclosure chevron: points right when closed and turns a
/// quarter to point down when open (M2).
///
/// It used to be two glyphs swapped — `chevron_right` for `expand_more` —
/// which reads as a flicker rather than as the row opening. One glyph turning
/// says the same thing and says where the content went.
class AppDisclosureChevron extends StatelessWidget {
  const AppDisclosureChevron({super.key, required this.open, required this.size, this.color});

  final bool open;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return AnimatedRotation(
      turns: open ? 0.25 : 0,
      duration: AppMotion.durationOf(context, AppMotion.state),
      curve: AppMotion.enter,
      child: Icon(Icons.chevron_right, size: size, color: color),
    );
  }
}
