import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_semantic_colors.dart';
import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../core/thumbnail_fit.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/app_image.dart';
import '../../../services/prompt_optimizer_agent.dart';
import '../../../state/app_state.dart';
import '../../../state/workbench_ui_state.dart';
import '../../../widgets/thumbnail_fit_toggle.dart';
import 'optimizer_context_card.dart';

/// The Prompt Assistant's left column outside library-edit mode (`A3a 1a` /
/// `1b`): the reference images the agent can view, then the result images the
/// user has fed back on.
class OptimizerReferencePanel extends StatelessWidget {
  const OptimizerReferencePanel({super.key});

  /// A reference card's picture. A fixed height rather than the image's own:
  /// unconstrained, one tall portrait filled the column and pushed the rest out
  /// of sight, so the numbering the prompt refers to stopped being scannable.
  static const double _imageHeight = 110;

  /// A result row's thumbnail.
  static const double _resultThumb = 44;

  /// A card's inset from the column edge, and the gap under it (`margin:0 8 6`).
  static const EdgeInsets _cardMargin = EdgeInsets.fromLTRB(8, 0, 8, AppSpace.s6);

  @override
  Widget build(BuildContext context) {
    final workbenchUIState = Provider.of<WorkbenchUIState>(context);
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final images = workbenchUIState.optimizerReferenceImages;
    final session = workbenchUIState.optimizerSession;
    // Shared with the gallery and the file browser — see [ThumbnailFit].
    // Read here and passed down: the cards are built inside a ListView
    // builder, whose element is the wrong place to hang the dependency.
    final thumbFit = context.select<AppState, ThumbnailFit>((s) => s.thumbnailFit);
    final countStyle = textTheme.labelSmall?.mono.copyWith(
      fontWeight: FontWeight.w400,
      color: colorScheme.onSurfaceVariant,
    );

    if (images.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, AppSpace.s10, 12, AppSpace.s6),
            child: OptimizerPanelCaption(l10n.referenceImages),
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.s16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.photo_library_outlined, size: 28, color: colorScheme.outline),
                    const SizedBox(height: OptimizerPanelCard.gap),
                    Text(
                      l10n.noImagesSelected,
                      textAlign: TextAlign.center,
                      style: textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: AppSpace.s4),
                    Text(
                      l10n.optEmptyImagesHint,
                      textAlign: TextAlign.center,
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: AppType.proseHeight,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    // The whole panel listens to the session, not just the list: which group a
    // card belongs to is derived from the history (a feedback turn moves an
    // image into the results group), and the "viewed" markers move mid-turn.
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              // Tighter than the empty state's caption: the fit control is a
              // 28px target, and the row takes its height.
              padding: const EdgeInsets.fromLTRB(12, AppSpace.s4, AppSpace.s6, 2),
              child: OptimizerPanelCaption(
                l10n.referenceImages,
                // The fit control belongs here rather than in the workbench
                // toolbar: that bar names the assistant, this one names the
                // strip whose cards the setting redraws.
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (refs.isNotEmpty) Text('${refs.length}', style: countStyle),
                    const ThumbnailFitToggle(iconSize: AppSize.iconMd, size: AppSize.compact),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(top: 2, bottom: AppSpace.s6),
                itemCount: rowCount,
                itemBuilder: (context, row) {
                  if (row < refs.length) {
                    final index = refs[row];
                    return _referenceCard(context, l10n, colorScheme, textTheme, workbenchUIState,
                        session, images[index], index, thumbFit);
                  }
                  if (row == refs.length) {
                    // The results group header, under the hairline that
                    // separates the two groups.
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (refs.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: AppSpace.s4),
                            child: Divider(height: 1, color: colorScheme.outlineVariant),
                          ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, AppSpace.s10, 12, AppSpace.s6),
                          child: OptimizerPanelCaption(
                            l10n.optResultImages,
                            trailing: Text('${results.length}', style: countStyle),
                          ),
                        ),
                      ],
                    );
                  }
                  final image = images[results[row - refs.length - 1]];
                  return _resultCard(context, l10n, colorScheme, textTheme, workbenchUIState,
                      session, image, thumbFit, resultInfo[image.name]!);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, AppSpace.s4, 12, AppSpace.s10),
              child: Text(
                l10n.optRefNumberingHint,
                style: textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w400,
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

  /// A reference: the picture with its number and a remove control on it, and
  /// under it the filename the prompt will cite and whether the agent has
  /// looked at it yet.
  Widget _referenceCard(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme colorScheme,
    TextTheme textTheme,
    WorkbenchUIState workbenchUIState,
    PromptOptimizerSession session,
    AppImage image,
    int index,
    ThumbnailFit thumbFit,
  ) {
    final viewed = session.viewedImagePaths.contains(image.path);
    final viewedColor = viewed ? context.semantic.success : colorScheme.outline;

    return Padding(
      padding: _cardMargin,
      child: _CardShell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: _imageHeight,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: colorScheme.surfaceContainerHighest,
                    child: Image(image: image.imageProvider, fit: thumbFit.boxFit),
                  ),
                  Positioned(
                    top: AppSpace.s6,
                    left: AppSpace.s6,
                    // The agent addresses images by this 1-based id, and the
                    // optimized prompt cites the same number.
                    child: _Plate(
                      child: Text(
                        '${index + 1}',
                        style: textTheme.labelSmall?.mono.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppOverlay.onImagePlate,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: AppSpace.s6,
                    right: AppSpace.s6,
                    // Neutral, not the error colour: taking a picture off the
                    // list is undone by selecting it again — nothing is
                    // destroyed.
                    child: _Plate(
                      tooltip: l10n.optRemoveImage,
                      onTap: () => workbenchUIState.removeAssistantImage(image),
                      child: const Icon(Icons.close, size: AppSize.iconSm, color: AppOverlay.onImagePlate),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: AppSpace.s6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    image.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelSmall?.mono.copyWith(
                      fontWeight: FontWeight.w400,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        viewed ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        size: AppSize.iconSm,
                        color: viewedColor,
                      ),
                      const SizedBox(width: AppSpace.s4),
                        Flexible(
                          child: Text(
                            viewed ? l10n.optViewed : l10n.optNotViewed,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w400,
                              color: viewedColor,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A result: a small thumbnail beside the prompt version it came from, its
  /// filename and the user's feedback on it — that digest is what tells the
  /// rows apart once every thumbnail shows the same character.
  Widget _resultCard(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme colorScheme,
    TextTheme textTheme,
    WorkbenchUIState workbenchUIState,
    PromptOptimizerSession session,
    AppImage image,
    ThumbnailFit thumbFit,
    ({int? promptVersion, String feedback}) meta,
  ) {
    final semantic = context.semantic;
    final viewed = session.viewedImagePaths.contains(image.path);
    final hasFeedback = meta.feedback.isNotEmpty;
    final feedback = hasFeedback ? meta.feedback : l10n.optResultNoFeedback;
    final monoStyle = textTheme.labelSmall?.mono.copyWith(fontWeight: FontWeight.w400);

    return Padding(
      padding: _cardMargin,
      child: _CardShell(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: SizedBox.square(
                  dimension: _resultThumb,
                  child: ColoredBox(
                    color: colorScheme.surfaceContainerHighest,
                    child: Image(image: image.imageProvider, fit: thumbFit.boxFit),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        if (meta.promptVersion != null) ...[
                          Text(
                            'v${meta.promptVersion}',
                            style: monoStyle?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onAccentTint,
                            ),
                          ),
                          const SizedBox(width: AppSpace.s4),
                        ],
                        Expanded(
                          child: Text(
                            image.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: monoStyle?.copyWith(color: colorScheme.onSurface),
                          ),
                        ),
                        if (viewed)
                          Tooltip(
                            message: l10n.optViewed,
                            child: Icon(Icons.visibility_outlined, size: AppSize.iconSm, color: semantic.success),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Tooltip(
                      message: feedback,
                      child: Text(
                        feedback,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w400,
                          color: hasFeedback ? colorScheme.onSurfaceVariant : colorScheme.outline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.s4),
              Tooltip(
                message: l10n.optRemoveImage,
                child: InkWell(
                  onTap: () => workbenchUIState.removeAssistantImage(image),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: SizedBox.square(
                    dimension: 20,
                    child: Icon(Icons.close, size: AppSize.iconSm, color: colorScheme.outline),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A card in this column: the panel ground, a hairline, r10, its content
/// clipped to the corners.
class _CardShell extends StatelessWidget {
  const _CardShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Material, so the remove control's ink lands on the card; the shape's
    // side is painted above the child, so the picture never covers the edge.
    return Material(
      color: colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: child,
    );
  }
}

/// A 20px square on the fixed image plate over a thumbnail — the reference
/// number, and the remove control opposite it.
///
/// One size and one shape for both: they sit in the same 6px inset on
/// opposite corners of the same picture, and read as one set of marks.
class _Plate extends StatelessWidget {
  const _Plate({required this.child, this.onTap, this.tooltip});

  final Widget child;
  final VoidCallback? onTap;
  final String? tooltip;

  static const double _size = 20;

  @override
  Widget build(BuildContext context) {
    final plate = Material(
      color: AppOverlay.imagePlate,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox.square(dimension: _size, child: Center(child: child)),
      ),
    );
    return tooltip == null ? plate : Tooltip(message: tooltip!, child: plate);
  }
}
