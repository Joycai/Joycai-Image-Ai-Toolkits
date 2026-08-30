import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/app_image.dart';
import '../../../services/prompt_optimizer_agent.dart';
import '../../../state/workbench_ui_state.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/app_section_label.dart';

class OptimizerReferencePanel extends StatelessWidget {
  const OptimizerReferencePanel({super.key});

  /// The scrim behind a result card's version chip — the same flat dark ink
  /// the gallery card's meta badge wears (`20c` draws rgba(20,26,52,.62)).
  /// Deliberately not seed-derived: it sits on a photograph, not on a surface.
  static const Color _versionScrim = Color(0x9E141A34);
  static const Color _versionInk = Color(0xF2FFFFFF);

  @override
  Widget build(BuildContext context) {
    final workbenchUIState = Provider.of<WorkbenchUIState>(context);
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final images = workbenchUIState.optimizerReferenceImages;
    final session = workbenchUIState.optimizerSession;

    if (images.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionLabel(
            l10n.referenceImages,
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
          ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.collections_outlined, size: 40, color: colorScheme.outlineVariant),
                  const SizedBox(height: 12),
                  Text(
                    l10n.noImagesSelected,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      l10n.optEmptyImagesHint,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colorScheme.outline),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // The whole panel listens to the session, not just the list: which group a
    // card belongs to is derived from the history (a feedback turn moves an
    // image into the results group), and the "viewed" badges move mid-turn.
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        // References vs results is a projection of the feedback messages in
        // history — nothing is tagged on the images themselves, so a restored
        // session groups identically to the live one. Model-facing ids stay
        // the *list* positions: grouping is display-only, and the number a
        // reference badge shows must be the id the prompt cites.
        final resultInfo = PromptOptimizerAgent.resultImageInfoByName(session.history);
        final refs = <int>[];
        final results = <int>[];
        for (var i = 0; i < images.length; i++) {
          (resultInfo.containsKey(images[i].name) ? results : refs).add(i);
        }
        // Newest version first — the card the user is about to act on.
        results.sort((a, b) => (resultInfo[images[b].name]?.promptVersion ?? -1)
            .compareTo(resultInfo[images[a].name]?.promptVersion ?? -1));

        final rowCount = refs.length + (results.isEmpty ? 0 : results.length + 1);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppSectionLabel(
              l10n.referenceImages,
              padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
              trailing: refs.isEmpty
                  ? null
                  : Text(
                      '${refs.length}',
                      style: Theme.of(context).textTheme.labelMedium?.mono.copyWith(
                            color: colorScheme.outline,
                          ),
                    ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                itemCount: rowCount,
                itemBuilder: (context, row) {
                  if (row < refs.length) {
                    final index = refs[row];
                    return _imageCard(context, l10n, colorScheme, workbenchUIState,
                        session, images[index], index,
                        meta: null);
                  }
                  if (row == refs.length) {
                    // The results group header, with the hairline that
                    // separates the two groups (`20c`).
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (refs.isNotEmpty)
                          Divider(height: 1, color: colorScheme.outlineVariant),
                        AppSectionLabel(
                          l10n.optResultImages,
                          padding: const EdgeInsets.fromLTRB(4, 10, 0, 8),
                          trailing: Text(
                            '${results.length}',
                            style: Theme.of(context).textTheme.labelMedium?.mono.copyWith(
                                  color: colorScheme.outline,
                                ),
                          ),
                        ),
                      ],
                    );
                  }
                  final index = results[row - refs.length - 1];
                  final image = images[index];
                  return _imageCard(context, l10n, colorScheme, workbenchUIState,
                      session, image, index,
                      meta: resultInfo[image.name]);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Text(
                l10n.optRefNumberingHint,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colorScheme.outline,
                      height: AppType.looseHeight,
                    ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// One card of either group. [meta] null = reference (numbered badge, plain
  /// filename footer); non-null = result (version chip on the picture, the
  /// user's feedback digest in the footer).
  Widget _imageCard(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme colorScheme,
    WorkbenchUIState workbenchUIState,
    PromptOptimizerSession session,
    AppImage image,
    int index, {
    required ({int? promptVersion, String feedback})? meta,
  }) {
    final viewed = session.viewedImagePaths.contains(image.path);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: AppCard(
        outlined: true,
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // A fixed 4:3 window rather than the image's own height:
            // unconstrained, one tall portrait shot filled the panel and
            // pushed the rest out of sight, so the numbering the prompt
            // refers to was no longer scannable.
            AspectRatio(
              aspectRatio: 4 / 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: colorScheme.surfaceContainerHighest,
                    child: Image(image: image.imageProvider, fit: BoxFit.cover),
                  ),
                  Positioned(
                    top: 7,
                    left: 7,
                    child: meta == null
                        // The agent addresses images by this 1-based id, and
                        // the optimized prompt cites the same number.
                        ? _Badge(
                            text: '${index + 1}',
                            background: colorScheme.primary,
                            foreground: colorScheme.onPrimary,
                          )
                        : (meta.promptVersion == null
                            ? const SizedBox.shrink()
                            : Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _versionScrim,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'v${meta.promptVersion}',
                                  style: Theme.of(context).textTheme.labelSmall?.mono.copyWith(
                                        color: _versionInk,
                                        fontWeight: FontWeight.w600,
                                        height: AppType.tightHeight,
                                      ),
                                ),
                              )),
                  ),
                  Positioned(
                    top: 7,
                    right: 7,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (viewed) ...[
                          Tooltip(
                            message: l10n.optViewed,
                            child: _Badge(
                              icon: Icons.visibility_outlined,
                              background: colorScheme.surface.withValues(alpha: 0.9),
                              foreground: colorScheme.onSurfaceVariant,
                              border: colorScheme.outlineVariant,
                            ),
                          ),
                          const SizedBox(width: 5),
                        ],
                        Tooltip(
                          message: l10n.optRemoveImage,
                          // Neutral, not the error colour it used to wear.
                          // Taking a picture off the list is undone by
                          // selecting it again — nothing is destroyed — and a
                          // red ✕ on every card made the panel read as a
                          // column of warnings.
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => workbenchUIState.removeAssistantImage(image),
                            child: _Badge(
                              icon: Icons.close,
                              background: colorScheme.surface.withValues(alpha: 0.9),
                              foreground: colorScheme.onSurfaceVariant,
                              border: colorScheme.outlineVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // The name the prompt will cite, off the picture so it never
            // covers the thing being referred to. A result card leads with the
            // user's own words about it instead — that digest is what tells
            // the cards apart once every thumbnail is the same character.
            Container(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: colorScheme.outlineVariant),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(9, 6, 9, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (meta != null) ...[
                    Tooltip(
                      message: meta.feedback.isEmpty ? l10n.optResultNoFeedback : meta.feedback,
                      child: Text(
                        meta.feedback.isEmpty ? l10n.optResultNoFeedback : meta.feedback,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: meta.feedback.isEmpty
                                  ? colorScheme.outline
                                  : colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ),
                    const SizedBox(height: 2),
                  ],
                  Text(
                    image.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.mono.copyWith(
                          color: meta == null ? colorScheme.onSurfaceVariant : colorScheme.outline,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A fixed 20px round plate over a thumbnail — the reference number, and the
/// two neutral controls beside it.
///
/// One size and one shape for all three. They sit in the same 7px inset on
/// opposite corners of the same picture, and the earlier mix of rounded squares
/// (the number, the eye) with a circle (the ✕) read as three unrelated marks
/// rather than as one set of affordances on one card.
class _Badge extends StatelessWidget {
  final String? text;
  final IconData? icon;
  final Color background;
  final Color foreground;

  /// A hairline for the translucent plates, which otherwise vanish over a pale
  /// patch of the image underneath.
  final Color? border;

  static const double _diameter = 20;

  const _Badge({
    this.text,
    this.icon,
    required this.background,
    required this.foreground,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _diameter,
      height: _diameter,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        shape: BoxShape.circle,
        border: border == null ? null : Border.all(color: border!),
      ),
      child: text != null
          ? Text(
              text!,
              style: Theme.of(context).textTheme.labelSmall?.mono.copyWith(
                    fontWeight: FontWeight.w600,
                    color: foreground,
                  ),
            )
          : Icon(icon, size: 12, color: foreground),
    );
  }
}
