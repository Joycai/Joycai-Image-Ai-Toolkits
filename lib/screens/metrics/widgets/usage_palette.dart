import 'package:flutter/material.dart';

import '../../../core/app_semantic_colors.dart';
import '../../../core/model_kind_palette.dart';
import '../../../l10n/app_localizations.dart';

/// The three things a token row bills, in the order the usage screen lists
/// them.
enum UsageToken { input, cache, output }

/// Steel blue: input tokens (`D2`: Input = #3F8FBF).
const Color _inputIdentity = Color(0xFF3F8FBF);

/// Purple: cached input (`D2`: Cached = #7A4ECB).
const Color _cacheIdentity = Color(0xFF7A4ECB);

/// Identity colours for the token types on the usage screen.
///
/// These name a *category*, so they never follow the accent: seeded from an
/// orange theme, input and cache would blur into one colour, and telling them
/// apart is the colour's whole job. Output takes the warning amber. That is a
/// borrowed hue, not a warning — `D2` picks it because it sits far from the
/// other two and from every preset accent. None of the three is green, because
/// the cost these add up to is a number, not a success.
extension UsageTokenIdentity on UsageToken {
  Color colorOf(BuildContext context) => switch (this) {
        UsageToken.input => _inputIdentity,
        UsageToken.cache => _cacheIdentity,
        UsageToken.output => context.semantic.warning,
      };

  String labelOf(AppLocalizations l10n) => switch (this) {
        UsageToken.input => l10n.inputTokens,
        UsageToken.cache => l10n.cachedInputTokens,
        UsageToken.output => l10n.outputTokens,
      };
}

/// The identity colour of a record's model kind (`LLMModel.tag`), or null when
/// the model is gone and its kind is unknown.
Color? usageModelKindColor(String? tag) => tag == null ? null : modelTagAccent(tag);

/// The glyph on a record's kind plate.
IconData usageModelKindGlyph(String? tag) => switch (tag?.toLowerCase()) {
      'chat' => Icons.chat_bubble_outline,
      'image' => Icons.image_outlined,
      'video' => Icons.movie_outlined,
      'multimodal' => Icons.auto_awesome_outlined,
      _ => Icons.token_outlined,
    };

/// The kind's name, for the plate's tooltip; null where there is none to give.
String? usageModelKindLabel(AppLocalizations l10n, String? tag) => switch (tag?.toLowerCase()) {
      'chat' => l10n.kindChat,
      'image' => l10n.kindImage,
      'video' => l10n.kindVideo,
      'multimodal' => l10n.kindMultimodal,
      _ => null,
    };
