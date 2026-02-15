import 'package:flutter/material.dart';

import '../../../core/responsive.dart';
import '../../../l10n/app_localizations.dart';

class MaskEditorToolbar extends StatelessWidget {
  final VoidCallback onUndo;
  final VoidCallback onClear;
  final VoidCallback onSave;
  final Function(Color) onColorChanged;
  final Function(double) onBrushSizeChanged;
  final VoidCallback onToggleBinary;
  final VoidCallback onToggleAI;
  final Color selectedColor;
  final double brushSize;
  final bool isBinaryMode;
  final bool showAIPanel;
  final bool hasPaths;

  const MaskEditorToolbar({
    super.key,
    required this.onUndo,
    required this.onClear,
    required this.onSave,
    required this.onColorChanged,
    required this.onBrushSizeChanged,
    required this.onToggleBinary,
    required this.onToggleAI,
    required this.selectedColor,
    required this.brushSize,
    required this.isBinaryMode,
    required this.showAIPanel,
    required this.hasPaths,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final isMobile = Responsive.isMobile(context);

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: colorScheme.surface,
      child: Row(
        children: [
          // Primary High-Frequency Actions
          if (!isMobile) ...[
            IconButton(
              icon: Icon(Icons.auto_awesome, color: showAIPanel ? colorScheme.primary : null),
              onPressed: onToggleAI,
              tooltip: "AI Smart Mask",
              visualDensity: VisualDensity.compact,
            ),
            const VerticalDivider(width: 16, indent: 12, endIndent: 12),
          ],
          
          _buildColorCircle(context, Colors.white, l10n.white),
          _buildColorCircle(context, Colors.black, l10n.black),
          if (!isBinaryMode) ...[
            _buildColorCircle(context, Colors.red, l10n.red),
            _buildColorCircle(context, Colors.green, l10n.green),
          ],
          
          const SizedBox(width: 8),
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: Slider(
                value: brushSize,
                min: 1,
                max: 100,
                onChanged: onBrushSizeChanged,
              ),
            ),
          ),
          
          IconButton(
            icon: const Icon(Icons.undo),
            onPressed: hasPaths ? onUndo : null,
            tooltip: l10n.undo,
            visualDensity: VisualDensity.compact,
          ),

          if (!isMobile) ...[
            IconButton(
              icon: Icon(isBinaryMode ? Icons.contrast : Icons.image, size: 20),
              onPressed: onToggleBinary,
              tooltip: "Binary Mode",
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: hasPaths ? onClear : null,
              tooltip: l10n.clear,
            ),
          ],

          // Overflow Menu for Mobile
          if (isMobile) 
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz),
              onSelected: (value) {
                if (value == 'ai') onToggleAI();
                if (value == 'binary') onToggleBinary();
                if (value == 'clear') onClear();
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'ai',
                  child: ListTile(
                    leading: Icon(Icons.auto_awesome, color: showAIPanel ? colorScheme.primary : null),
                    title: const Text("AI Smart Mask"),
                    dense: true,
                  ),
                ),
                PopupMenuItem(
                  value: 'binary',
                  child: ListTile(
                    leading: Icon(isBinaryMode ? Icons.contrast : Icons.image),
                    title: const Text("Binary Mode"),
                    dense: true,
                  ),
                ),
                PopupMenuItem(
                  value: 'clear',
                  child: ListTile(
                    leading: const Icon(Icons.delete_outline, color: Colors.red),
                    title: Text(l10n.clear, style: const TextStyle(color: Colors.red)),
                    dense: true,
                  ),
                ),
              ],
            ),

          const VerticalDivider(width: 16, indent: 12, endIndent: 12),
          
          FilledButton(
            onPressed: onSave,
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: Text(isMobile ? l10n.save : l10n.saveAndSelect, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildColorCircle(BuildContext context, Color color, String tooltip) {
    bool isSelected = selectedColor == color;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: GestureDetector(
        onTap: () => onColorChanged(color),
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey,
              width: isSelected ? 2 : 1,
            ),
          ),
        ),
      ),
    );
  }
}
