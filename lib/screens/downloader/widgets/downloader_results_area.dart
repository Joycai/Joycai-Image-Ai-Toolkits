import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_theme.dart';
import '../../../core/file_utils.dart';
import '../../../l10n/app_localizations.dart';
import '../../../state/downloader_state.dart';
import '../../../widgets/app_button.dart';

class DownloaderResultsArea extends StatelessWidget {
  final VoidCallback onAddToQueue;

  const DownloaderResultsArea({super.key, required this.onAddToQueue});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = context.watch<DownloaderState>();
    final colorScheme = Theme.of(context).colorScheme;
    final selectedCount = state.discoveredImages.where((i) => i.isSelected).length;

    return Column(
      children: [
        // Selection bar sits directly on the column's surface — no fill.
        if (state.discoveredImages case [_, ...]) Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(
              children: [
                Text(
                  l10n.selectImagesToDownload,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 10),
                Text(
                  '(${l10n.imagesSelected(selectedCount)})',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                AppButton(
                  label: l10n.selectAll,
                  variant: AppButtonVariant.text,
                  onPressed: selectedCount == state.discoveredImages.length
                      ? null
                      : () {
                          for (var img in state.discoveredImages) {
                            img.isSelected = true;
                          }
                          state.notify();
                        },
                ),
                const SizedBox(width: 8),
                AppButton(
                  label: l10n.addToQueue,
                  icon: Icons.download_for_offline,
                  onPressed: selectedCount > 0 ? onAddToQueue : null,
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
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 3),
          Text(
            description,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colorScheme.outline),
          ),
        ],
      ),
    );
  }
}

/// The tick box on a discovery card. Hand-drawn rather than a [Checkbox]: it
/// sits on a photograph, so it needs a filled body of its own to stay legible
/// against whatever is behind it.
class _SelectionBox extends StatelessWidget {
  final bool selected;
  final ColorScheme colorScheme;

  const _SelectionBox({required this.selected, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: selected ? colorScheme.primary : Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: selected ? colorScheme.primary : Colors.white.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      child: selected
          ? Icon(Icons.check, size: 15, color: colorScheme.onPrimary)
          : null,
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
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: image.isSelected ? colorScheme.primary : Colors.transparent,
          width: 2,
        ),
        borderRadius: BorderRadius.circular(12),
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
                      ? Image.file(
                          File(image.localCachePath!),
                          fit: BoxFit.cover,
                          // A scraped page can hand back a grid of full-size
                          // artwork; decoding each one at native resolution for
                          // a 220px cell filled the image cache several times
                          // over and re-decoded the lot on every scroll. The
                          // ceiling is the grid delegate's maxCrossAxisExtent.
                          cacheWidth: (220 * MediaQuery.devicePixelRatioOf(context)).round(),
                        )
                      : const Center(child: Icon(Icons.image, color: Colors.grey)),
                  ),
                ),
                Container(
                  color: Colors.black.withValues(alpha: 0.55),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Text(
                    image.url,
                    style: Theme.of(context).textTheme.labelSmall?.mono.copyWith(
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            // The box is drawn whether or not it is ticked. This grid exists to
            // be selected from, and a checkmark that only appears once you have
            // already guessed to click does not tell you that.
            Positioned(
              top: 8,
              left: 8,
              child: _SelectionBox(selected: image.isSelected, colorScheme: colorScheme),
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
