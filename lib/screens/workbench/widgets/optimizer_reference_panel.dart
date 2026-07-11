import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../state/workbench_ui_state.dart';
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
              : Text('${images.length}', style: TextStyle(fontSize: 11, color: colorScheme.outline)),
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
                    style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
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
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Stack(
                        children: [
                          Image(
                            image: image.imageProvider,
                            fit: BoxFit.cover,
                            width: double.infinity,
                          ),
                          // The agent addresses images by this 1-based id.
                          Positioned(
                            top: 6,
                            left: 6,
                            child: _Badge(
                              text: '#${index + 1}',
                              background: colorScheme.surface.withValues(alpha: 0.85),
                              foreground: colorScheme.onSurface,
                            ),
                          ),
                          if (viewed)
                            Positioned(
                              top: 6,
                              right: 6,
                              child: Tooltip(
                                message: l10n.optViewed,
                                child: _Badge(
                                  icon: Icons.visibility_outlined,
                                  background: colorScheme.tertiaryContainer.withValues(alpha: 0.9),
                                  foreground: colorScheme.onTertiaryContainer,
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
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  final String? text;
  final IconData? icon;
  final Color background;
  final Color foreground;

  const _Badge({this.text, this.icon, required this.background, required this.foreground});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: text != null
          ? Text(
              text!,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: foreground),
            )
          : Icon(icon, size: 12, color: foreground),
    );
  }
}
