import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/design_tokens.dart';
import '../../models/llm_channel.dart';

/// A channel's identity as a plate: its tag's first letter on its own colour.
///
/// `D1a`: a channel's tag colour is an identity, carried by this plate — a
/// rounded square (r6 at 28 and up) with the initial in white — wherever a
/// channel is *named*: the channel rows, the detail header, the model
/// editor's summary. It is the square counterpart to [ModelTagChip], which is
/// what a channel wears inside a picker row, where the full tag has to stay
/// readable beside a name.
///
/// Untagged channels keep the plate and swap the letter for a cloud glyph on
/// the default tag colour: a column of rows reads as one column only if every
/// row has the same plate, and an empty plate says less than a glyph that at
/// least says "endpoint".
class ChannelAvatar extends StatelessWidget {
  const ChannelAvatar(this.channel, {super.key, this.size = 24});

  final LLMChannel channel;

  /// Side length. The models screen uses 24/28/32 depending on the row; the
  /// editor's summary card uses 24.
  final double size;

  @override
  Widget build(BuildContext context) {
    final String? tag = channel.tag;
    if (tag == null || tag.isEmpty) {
      return _Plate(
        color: const Color(AppConstants.defaultTagColor),
        size: size,
        child: Icon(Icons.cloud_queue, size: size * 0.55, color: Colors.white),
      );
    }
    return TagAvatar(tag, color: Color(channel.tagColor ?? AppConstants.defaultTagColor), size: size);
  }
}

/// The plate itself, from a bare tag string and colour.
///
/// Split out of [ChannelAvatar] for callers that hold a `PickerOption` rather
/// than an [LLMChannel] — the searchable picker's field slot — and so cannot
/// hand over a record they no longer have. No untagged fallback here: a
/// caller with only a tag string has, by construction, a tag.
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

    return _Plate(
      color: color ?? const Color(AppConstants.defaultTagColor),
      size: size,
      child: Text(
        tag.isEmpty ? '' : tag.characters.first.toUpperCase(),
        maxLines: 1,
        style: style,
      ),
    );
  }
}

class _Plate extends StatelessWidget {
  const _Plate({required this.color, required this.size, required this.child});

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
