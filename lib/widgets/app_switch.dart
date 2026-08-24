import 'package:flutter/material.dart';

/// The switch at the size the design draws it.
///
/// `A1 16a` — and every other frame that carries one — draws a 36×21 pill.
/// Material 3's [Switch] is 52×32, and that geometry is not themeable: the
/// track size, the thumb radii and the 16→24px thumb growth on selection are
/// constants inside `RenderToggleable`, not [SwitchThemeData] fields. There is
/// no size parameter to set and no theme entry to override, so the only way to
/// hit the spec's figure is to scale the whole widget.
///
/// Which is what this does. The colours still come from the theme — this is
/// Material's switch, at the design's size, not a hand-drawn replacement whose
/// states (hover, focus, disabled, the drag) would all have to be rebuilt and
/// would drift from the real one at the first framework revision.
///
/// The [OverflowBox] is what makes the scale a *layout* change rather than a
/// paint-only one: the switch is laid out at its natural 52×32 inside a box
/// that only reserves the scaled size, so the row beside it closes up instead
/// of leaving 16px of dead space where the unscaled track used to be.
class AppSwitch extends StatelessWidget {
  const AppSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  /// What Material lays a [Switch] out at, and what the scale is applied to.
  static const Size _materialSize = Size(52, 32);

  /// The spec's width over Material's own.
  static const double _scale = 36 / 52;

  /// The room this reserves — the design's 36×22.
  static const Size size = Size(52 * _scale, 32 * _scale);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size.width,
      height: size.height,
      child: OverflowBox(
        maxWidth: _materialSize.width,
        maxHeight: _materialSize.height,
        child: Transform.scale(
          scale: _scale,
          child: Switch(value: value, onChanged: onChanged),
        ),
      ),
    );
  }
}
