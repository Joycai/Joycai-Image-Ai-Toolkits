import 'package:flutter/material.dart';

import '../../../models/browser_file.dart';

class FileCard extends StatelessWidget {
  final BrowserFile file;
  final bool isSelected;
  final double thumbnailSize;
  final VoidCallback onTap;
  final Function(Offset) onSecondaryTap;

  const FileCard({
    super.key,
    required this.file,
    required this.isSelected,
    required this.thumbnailSize,
    required this.onTap,
    required this.onSecondaryTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return GestureDetector(
      onTap: onTap,
      onSecondaryTapDown: (details) => onSecondaryTap(details.globalPosition),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: colorScheme.surfaceContainerHighest.withAlpha(isSelected ? 100 : 50),
            border: Border.all(
              color: isSelected ? colorScheme.primary : colorScheme.outlineVariant,
              width: isSelected ? 2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: file.category == FileCategory.image
                    ? Image(image: file.imageProvider, fit: BoxFit.cover)
                    : Center(child: Icon(file.icon, size: 48, color: file.color.withAlpha(150))),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                color: Colors.black54,
                child: Text(
                  file.name,
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
