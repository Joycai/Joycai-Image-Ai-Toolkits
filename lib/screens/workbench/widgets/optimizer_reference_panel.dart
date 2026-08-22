import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../state/workbench_ui_state.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/app_section_label.dart';
import '../../../core/design_tokens.dart';

class OptimizerReferencePanel extends StatelessWidget {
  const OptimizerReferencePanel({super.key});

  @override
  Widget build(BuildContext context) {
    final workbenchUIState = Provider.of<WorkbenchUIState>(context);
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final images = workbenchUIState.optimizerReferenceImages;
    final session = workbenchUIState.optimizerSession;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSectionLabel(
          l10n.referenceImages,
          padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
          trailing: images.isEmpty
              ? null
              : Text(
                  '${images.length}',
                  style: Theme.of(context).textTheme.labelMedium?.mono.copyWith(
                        color: colorScheme.outline,
                      ),
                ),
        ),
        if (images.isEmpty)
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
          )
        else
          Expanded(
            child: ListenableBuilder(
              listenable: session,
              builder: (context, _) => ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                itemCount: images.length,
                itemBuilder: (context, index) {
                  final image = images[index];
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
                          // A fixed 4:3 window rather than the image's own
                          // height: unconstrained, one tall portrait shot
                          // filled the panel and pushed the rest out of sight,
                          // so the numbering the prompt refers to was no
                          // longer scannable.
                          AspectRatio(
                            aspectRatio: 4 / 3,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                ColoredBox(
                                  color: colorScheme.surfaceContainerHighest,
                                  child: Image(image: image.imageProvider, fit: BoxFit.cover),
                                ),
                                // The agent addresses images by this 1-based
                                // id, and the optimized prompt cites the same
                                // number.
                                Positioned(
                                  top: 7,
                                  left: 7,
                                  child: _Badge(
                                    text: '${index + 1}',
                                    background: colorScheme.primary,
                                    foreground: colorScheme.onPrimary,
                                  ),
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
                                        // Neutral, not the error colour it
                                        // used to wear. Taking a picture off
                                        // the list is undone by selecting it
                                        // again — nothing is destroyed — and a
                                        // red ✕ on every card made the panel
                                        // read as a column of warnings.
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
                          // The name the prompt will cite, off the picture so
                          // it never covers the thing being referred to. Its
                          // own footer band under a hairline, rather than text
                          // floating below the image: the card is a thumbnail
                          // *and* a filename, and the rule is what says the two
                          // belong to each other rather than to the next card.
                          Container(
                            decoration: BoxDecoration(
                              border: Border(
                                top: BorderSide(color: colorScheme.outlineVariant),
                              ),
                            ),
                            padding: const EdgeInsets.fromLTRB(9, 6, 9, 6),
                            child: Text(
                              image.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall?.mono.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        // Why the numbers matter, said once at the bottom rather than as a
        // tooltip on each card: the ordering is what the prompt cites, and
        // that is not guessable from a numbered badge alone.
        if (images.isNotEmpty)
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
