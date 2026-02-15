import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../state/app_state.dart';

class OptimizerReferencePanel extends StatelessWidget {
  const OptimizerReferencePanel({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final l10n = AppLocalizations.of(context)!;
    final images = appState.selectedImages;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            l10n.images,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.2),
          ),
        ),
        if (images.isEmpty)
          Expanded(
            child: Center(
              child: Text(
                l10n.noImagesSelected,
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
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
