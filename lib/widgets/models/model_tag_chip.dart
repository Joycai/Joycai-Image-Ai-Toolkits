import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/design_tokens.dart';
import '../../core/model_kind_palette.dart';
import '../../l10n/app_localizations.dart';

/// A small badge naming what a model is — CHAT, IMAGE, VIDEO, MULTIMODAL —
/// or, with [color] supplied, what channel a row belongs to.
///
/// `D1a`: an identity badge is a 12% wash of its own colour at r4 with the
/// colour as ink, and no ring — the identity hue says "which one", and a ring
/// around it would read as a selection. The channel tag in the searchable
/// pickers and the channel rows is the same badge with the user's own colour
/// and text ([color], [uppercase]).
class ModelTagChip extends StatelessWidget {
  const ModelTagChip(
    this.tag, {
    super.key,
    this.color,
    this.uppercase = true,
    this.mono = false,
  });

  /// A [ModelTag] string value. Unrecognised tags take the palette's fallback
  /// rather than being hidden — a model with an odd tag should still say so.
  final String tag;

  /// Overrides [modelTagAccent], for a tag whose colour is an identity the
  /// user chose rather than a kind the app knows.
  final Color? color;

  /// Whether to shout the tag. True for the app's own kind names, false for
  /// free text someone typed.
  final bool uppercase;

  /// Sets the tag in the mono role, as the channel rows draw it (`D1a · 1a`).
  ///
  /// Off by default: the searchable picker measures its row extent from
  /// `labelSmall` plus [chromeHeight], and a caller that changes the face has
  /// to measure the face it changed to.
  final bool mono;

  /// Vertical space the chip adds around its single line of type: the
  /// symmetric vertical padding, top and bottom.
  ///
  /// Public because a fixed-extent list has to know how tall its tallest row
  /// can be *before* laying one out, and a row carrying one of these is taller
  /// than the name beside it. See `SearchablePickerField`.
  static const double chromeHeight = 2 * _vPad;

  static const double _vPad = 1;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? modelTagAccent(tag);
    final base = Theme.of(context).textTheme.labelSmall;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s6, vertical: _vPad),
      decoration: BoxDecoration(
        // The accent ladder, even though this is an identity colour rather
        // than the theme accent: "a tint to sit on" is the same relationship,
        // and a second set of alphas for the same job is how the first set
        // stopped being followed.
        color: color.withValues(alpha: AppAlpha.tint),
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        uppercase ? tag.toUpperCase() : tag,
        // Free text has no length limit, so the chip gives way rather than
        // pushing its row over; callers cap the width.
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: (mono ? base?.mono : base)?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// The glyph a model kind is drawn with (`D1a · 1a`): chat `forum`, image
/// `image`, video `movie`, multimodal `apps`; anything else a chip.
IconData modelKindIcon(String tag) {
  switch (tag.toLowerCase()) {
    case 'chat':
      return Icons.forum_outlined;
    case 'image':
      return Icons.image_outlined;
    case 'video':
      return Icons.movie_outlined;
    case 'multimodal':
      return Icons.apps;
    default:
      return Icons.memory;
  }
}

/// The localized name of a model kind, or the raw tag shouted for a kind the
/// app has no name for.
String modelKindLabel(AppLocalizations l10n, String tag) {
  switch (tag.toLowerCase()) {
    case 'chat':
      return l10n.kindChat;
    case 'image':
      return l10n.kindImage;
    case 'video':
      return l10n.kindVideo;
    case 'multimodal':
      return l10n.kindMultimodal;
    default:
      return tag.toUpperCase();
  }
}

/// A model's kind as the model card and the discovery list badge it
/// (`D1a` 「类型徽标 r4 1/8 11/500」): the localized kind name on its identity
/// colour's wash.
class ModelKindBadge extends StatelessWidget {
  const ModelKindBadge(this.tag, {super.key});

  final String tag;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final color = modelTagAccent(tag);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: AppAlpha.tint),
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        modelKindLabel(l10n, tag),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// The square plate carrying a model kind's glyph at the head of a model card
/// (`D1a` 「32 r6 类型图标底板」).
class ModelKindPlate extends StatelessWidget {
  const ModelKindPlate(this.tag, {super.key, this.size = 32});

  final String tag;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = modelTagAccent(tag);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: AppAlpha.tint),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Icon(
        modelKindIcon(tag),
        size: size >= 32 ? AppSize.iconMd + 2 : AppSize.iconMd,
        color: color,
      ),
    );
  }
}
