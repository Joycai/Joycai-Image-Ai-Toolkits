import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../state/workbench_ui_state.dart';
import '../../../widgets/app_card.dart';
import 'config_section_header.dart';

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
        ConfigSectionHeader(
          l10n.referenceImages,
          padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
          trailing: images.isEmpty
              ? null
              : Text('${images.length}', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colorScheme.outline)),
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
                padding: const EdgeInsets.symmetric(horizontal: 12),
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
                                  top: 6,
                                  left: 6,
                                  child: _Badge(
                                    text: '${index + 1}',
                                    background: colorScheme.primary,
                                    foreground: colorScheme.onPrimary,
                                  ),
                                ),
                                Positioned(
                                  top: 6,
                                  right: 6,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (viewed) ...[
                                        Tooltip(
                                          message: l10n.optViewed,
                                          child: _Badge(
                                            icon: Icons.visibility_outlined,
                                            background: colorScheme.surface.withValues(alpha: 0.85),
                                            foreground: colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
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
                                            background: colorScheme.surface.withValues(alpha: 0.85),
                                            foreground: colorScheme.onSurfaceVariant,
                                            circular: true,
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
                          // it never covers the thing being referred to.
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                            child: Text(
                              image.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    fontFamily: 'monospace',
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
                    color: colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
            ),
          ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  final String? text;
  final IconData? icon;
  final Color background;
  final Color foreground;

  /// A round plate rather than the default rounded square — for the ✕, whose
  /// job is to read as a small dismiss control rather than as another chip in
  /// the row of labels.
  final bool circular;

  const _Badge({
    this.text,
    this.icon,
    required this.background,
    required this.foreground,
    this.circular = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: circular
          ? const EdgeInsets.all(4)
          : const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        shape: circular ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circular ? null : BorderRadius.circular(6),
      ),
      child: text != null
          ? Text(
              text!,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold, color: foreground),
            )
          : Icon(icon, size: 12, color: foreground),
    );
  }
}
