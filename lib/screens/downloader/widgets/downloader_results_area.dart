import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/file_utils.dart';
import '../../../l10n/app_localizations.dart';
import '../../../state/app_state.dart';

class DownloaderResultsArea extends StatelessWidget {
  final VoidCallback onAddToQueue;

  const DownloaderResultsArea({super.key, required this.onAddToQueue});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final appState = Provider.of<AppState>(context);
    final state = appState.downloaderState;
    final colorScheme = Theme.of(context).colorScheme;
    final selectedCount = state.discoveredImages.where((i) => i.isSelected).length;

    return Column(
      children: [
        if (state.discoveredImages case [_, ...]) Container(
            padding: const EdgeInsets.all(16),
            color: colorScheme.surface,
            child: Row(
              children: [
                Text(
                  l10n.selectImagesToDownload,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Text('(${l10n.imagesSelected(selectedCount)})', style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    for (var img in state.discoveredImages) {
                      img.isSelected = true;
                    }
                    state.notify();
                  },
                  child: Text(l10n.selectAll),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: selectedCount > 0 ? onAddToQueue : null,
                  icon: const Icon(Icons.download_for_offline),
                  label: Text(l10n.addToQueue),
                ),
              ],
            ),
          ),
        Expanded(
          child: state.discoveredImages.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(l10n.noImagesDiscovered, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 32),
                    Wrap(
                      spacing: 40,
                      runSpacing: 24,
                      alignment: WrapAlignment.center,
                      children: [
                        _GuideStep(
                          icon: Icons.link,
                          title: l10n.guideStep1Title,
                          description: l10n.guideStep1Desc,
                        ),
                        _GuideStep(
                          icon: Icons.chat_bubble_outline,
                          title: l10n.guideStep2Title,
                          description: l10n.guideStep2Desc,
                        ),
                        _GuideStep(
                          icon: Icons.download_for_offline_outlined,
                          title: l10n.guideStep3Title,
                          description: l10n.guideStep3Desc,
                        ),
                      ],
                    ),
                  ],
                ),
              )
            : GridView.builder(
                padding: const EdgeInsets.all(20),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 220,
                  mainAxisSpacing: 20,
                  crossAxisSpacing: 20,
                  childAspectRatio: 0.85,
                ),
                itemCount: state.discoveredImages.length,
                itemBuilder: (context, index) {
                  final img = state.discoveredImages[index];
                  return _ImageDiscoveryCard(
                    image: img,
                    onToggle: () {
                      img.isSelected = !img.isSelected;
                      state.notify();
                    },
                  );
                },
              ),
        ),
      ],
    );
  }
}

/// One column of the empty-state onboarding guide (icon + step title + hint).
class _GuideStep extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _GuideStep({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 170,
      child: Column(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withAlpha(90),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: colorScheme.primary),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 3),
          Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, color: colorScheme.outline),
          ),
        ],
      ),
    );
  }
}

class _ImageDiscoveryCard extends StatelessWidget {
  final dynamic image;
  final VoidCallback onToggle;

  const _ImageDiscoveryCard({required this.image, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: image.isSelected ? 4 : 1,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: image.isSelected ? colorScheme.primary : colorScheme.outlineVariant,
          width: image.isSelected ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: onToggle,
        onSecondaryTapDown: (details) => _showContextMenu(context, details.globalPosition),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Container(
                    color: colorScheme.surfaceContainerHighest,
                    child: image.localCachePath != null
                      ? Image.file(File(image.localCachePath!), fit: BoxFit.cover)
                      : const Center(child: Icon(Icons.image, color: Colors.grey)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    image.url,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (image.isSelected)
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: colorScheme.primary, shape: BoxShape.circle),
                  child: const Icon(Icons.check, size: 16, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showContextMenu(BuildContext context, Offset position) {
    final l10n = AppLocalizations.of(context)!;
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: [
        PopupMenuItem(
          child: ListTile(
            leading: const Icon(Icons.open_in_browser, size: 18),
            title: Text(l10n.openRawImage),
            dense: true,
          ),
          onTap: () async {
            await FileUtils.openUri(Uri.parse(image.url));
          },
        ),
      ],
    );
  }
}
