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
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: images.length,
              itemBuilder: (context, index) {
                final image = images[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image(
                      image: image.imageProvider,
                      fit: BoxFit.cover,
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
