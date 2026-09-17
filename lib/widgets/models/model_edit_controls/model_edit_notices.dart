import 'package:flutter/material.dart';

import '../../../core/app_semantic_colors.dart';
import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import 'model_edit_metrics.dart';

/// How loud a [ModelEditNotice] is. None of these is the accent.
enum ModelEditTone {
  /// A fact worth knowing: unrecognised id, streaming not used.
  info,

  /// Likely to go wrong, still allowed: images through a chat format.
  warning,

  /// Nothing will run: the channel has no interface for the kind.
  error,
}

/// A notice strip under a section (`1b` ③ ④, `1d`): opaque status container,
/// r6, a 14px glyph and 11px copy in the container's ink.
class ModelEditNotice extends StatelessWidget {
  const ModelEditNotice({super.key, required this.tone, required this.text, this.icon});

  final ModelEditTone tone;
  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantic = context.semantic;
    final (Color bg, Color ink, IconData glyph) = switch (tone) {
      ModelEditTone.info => (semantic.infoContainer, semantic.onInfoContainer, Icons.info_outline),
      ModelEditTone.warning => (
          semantic.warningContainer,
          semantic.onWarningContainer,
          Icons.warning_amber_rounded
        ),
      ModelEditTone.error => (scheme.errorContainer, scheme.onErrorContainer, Icons.error_outline),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10, vertical: 7),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.sm)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon ?? glyph, size: AppSize.iconSm, color: ink),
          ),
          const SizedBox(width: AppSpace.s6),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w400, color: ink),
            ),
          ),
        ],
      ),
    );
  }
}

/// A helper sentence: 11px, `onSurfaceVariant` — never `outline`, which makes
/// an explanation read as disabled (`D1c` 颜色角色).
class ModelEditHelperText extends StatelessWidget {
  const ModelEditHelperText(this.text, {super.key, this.muted = false});

  final String text;

  /// The muted ink, only for copy belonging to a greyed-out section.
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.labelSmall?.copyWith(
        fontWeight: FontWeight.w400,
        color: muted ? theme.colorScheme.outline : theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// The indented parameter summary under the request method: a 2px guide,
/// 12px in, 「Parameters」 and a wrap of r4 mono chips.
///
/// The guide rests in the hairline colour and, while [governed] — a protocol
/// is pinned — takes the accent's rule tone (`D2a`: 引导线主色 35%), tweened
/// over M2, so the parameters read as following that choice.
class ModelEditParamBlock extends StatelessWidget {
  const ModelEditParamBlock({super.key, required this.items, this.governed = false});

  static const double railWidth = 2;

  final bool governed;

  /// In the surface's fixed order. Empty prints the "no specific parameters"
  /// sentence instead.
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final chipStyle = theme.textTheme.labelSmall?.mono.copyWith(
      fontWeight: FontWeight.w400,
      color: scheme.onSurface,
    );

    return Padding(
      padding: const EdgeInsetsDirectional.only(start: AppSpace.s6),
      child: TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: governed ? scheme.accentRule : scheme.outlineVariant),
        duration: AppMotion.durationOf(context, AppMotion.state),
        curve: AppMotion.enter,
        builder: (context, rail, child) => Container(
          width: double.infinity,
          padding: const EdgeInsetsDirectional.only(start: 12, top: 2, bottom: 2),
          decoration: BoxDecoration(
            border: BorderDirectional(start: BorderSide(color: rail!, width: railWidth)),
          ),
          child: child,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ModelEditHelperText(l10n.protocolParamsLabel),
            const SizedBox(height: AppSpace.s4),
            if (items.isEmpty)
              ModelEditHelperText(l10n.protocolParamsNone)
            else
              Wrap(
                spacing: AppSpace.s4,
                runSpacing: AppSpace.s4,
                children: [
                  for (final item in items)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s6, vertical: 1),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                      ),
                      child: Text(item, style: chipStyle),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// 「改回自动」: right-aligned, compact, deep ink, directly under the pinned
/// field (`1b` ②).
class ModelEditBackToAuto extends StatelessWidget {
  const ModelEditBackToAuto({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final metrics = ModelEditMetrics.of(context);
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: TextButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.undo, size: AppSize.iconSm),
        label: Text(AppLocalizations.of(context)!.protocolBackToAuto),
        style: TextButton.styleFrom(
          minimumSize: Size(0, metrics.inlineActionHeight),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.s6),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}

/// A save-blocking problem under the field it belongs to (`1d` 「保存校验」):
/// r10, the error stroke, a glyph, a 600 title in the error ink and an
/// optional 11px explanation.
class ModelEditValidationNote extends StatelessWidget {
  const ModelEditValidationNote({super.key, required this.title, this.description});

  final String title;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.s10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: scheme.error),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.error_outline, size: AppSize.iconSm, color: scheme.error),
          ),
          const SizedBox(width: AppSpace.s6),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: scheme.onErrorContainer,
                  ),
                ),
                if (description != null) ...[
                  const SizedBox(height: 2),
                  ModelEditHelperText(description!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The request-method field when the channel has no interface for the kind
/// (`1b` ④): the error stroke, `block` and 「不可用」, nothing to open.
class ModelEditUnavailableField extends StatelessWidget {
  const ModelEditUnavailableField({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final metrics = ModelEditMetrics.of(context);

    return Container(
      height: metrics.fieldHeight,
      padding: EdgeInsets.symmetric(horizontal: metrics.phone ? 12 : AppSpace.s10),
      decoration: BoxDecoration(
        color: metrics.fill(scheme),
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: scheme.error),
      ),
      child: Row(
        children: [
          Icon(Icons.block, size: AppSize.iconMd, color: scheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              AppLocalizations.of(context)!.protocolUnavailable,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
                color: scheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
