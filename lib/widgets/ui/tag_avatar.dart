import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/design_tokens.dart';

/// A tag's first letter on its own colour, as a rounded plate.
///
/// `D1a`: an identity colour is carried by this plate — a rounded square (r6
/// at 28 and up) with the initial in white — wherever the thing it identifies
/// is *named*. It is the square counterpart to `ModelTagChip`, which is what
/// the same identity wears inside a picker row, where the full tag has to stay
/// readable beside a name.
///
/// Takes a bare string rather than a record, which is why it is here and
/// [ChannelAvatar] is not: the searchable picker holds a `PickerOption` and has
/// no channel to hand over. No untagged fallback — a caller with only a tag
/// string has, by construction, a tag; [ChannelAvatar] is the one that knows
/// what an untagged channel should look like.
class TagAvatar extends StatelessWidget {
  const TagAvatar(this.tag, {super.key, this.color, this.size = 24});

  final String tag;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    // 13/600 on the 28 and 32 plates (`D1a · 1a`); the picker's 20 plate takes
    // the smallest rung rather than a size off the scale.
    final style = (size >= 28 ? textTheme.titleSmall : textTheme.labelSmall)?.copyWith(
      color: Colors.white,
      fontWeight: FontWeight.w600,
      height: 1,
      letterSpacing: 0,
    );

    return TagPlate(
      color: color ?? const Color(AppConstants.defaultTagColor),
      size: size,
      child: Text(tag.isEmpty ? '' : tag.characters.first.toUpperCase(), maxLines: 1, style: style),
    );
  }
}

/// The plate on its own, for a caller that draws something other than a letter
/// on it — [ChannelAvatar] puts a glyph here for a channel with no tag.
class TagPlate extends StatelessWidget {
  const TagPlate({super.key, required this.color, required this.size, required this.child});

  final Color color;
  final double size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size >= 24 ? AppRadius.sm : AppRadius.xs),
      ),
      child: child,
    );
  }
}
