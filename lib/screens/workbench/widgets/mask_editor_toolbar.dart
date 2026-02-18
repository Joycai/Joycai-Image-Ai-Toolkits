import 'package:flutter/material.dart';

import '../../../core/responsive.dart';
import '../../../l10n/app_localizations.dart';

class MaskEditorToolbar extends StatelessWidget {
  final VoidCallback onUndo;
  final VoidCallback onClear;
  final VoidCallback onSave;
  final VoidCallback onSaveMask;
  final Function(Color) onColorChanged;
  final Function(double) onBrushSizeChanged;
  final Function(double) onOpacityChanged;
  final VoidCallback onToggleBinary;
  final VoidCallback onToggleAI;
  final Color selectedColor;
  final double brushSize;
  final double opacity;
  final bool isBinaryMode;
  final bool showAIPanel;
  final bool hasPaths;

  const MaskEditorToolbar({
    super.key,
    required this.onUndo,
    required this.onClear,
    required this.onSave,
    required this.onSaveMask,
    required this.onColorChanged,
    required this.onBrushSizeChanged,
    required this.onOpacityChanged,
    required this.onToggleBinary,
    required this.onToggleAI,
    required this.selectedColor,
    required this.brushSize,
    required this.opacity,
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
              tooltip: l10n.aiSmartMask,
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
            child: Row(
              children: [
                const Icon(Icons.line_weight, size: 16, color: Colors.grey),
                Expanded(
                  flex: 2,
                  child: Slider(
                    value: brushSize,
                    min: 1,
                    max: 100,
                    onChanged: onBrushSizeChanged,
                    label: l10n.brushSize,
                  ),
                ),
                if (!isMobile) ...[
                  const SizedBox(width: 16),
                  const Icon(Icons.opacity, size: 16, color: Colors.grey),
                  Expanded(
                    flex: 1,
                    child: Slider(
                      value: opacity,
                      min: 0.1,
                      max: 1.0,
                      onChanged: onOpacityChanged,
                      label: l10n.maskOpacity,
                    ),
                  ),
                ],
              ],
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
              tooltip: l10n.binaryMode,
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
                if (value == 'save_temp') onSave();
                if (value == 'save_mask') onSaveMask();
                if (value == 'opacity') {
                  // Show opacity dialog on mobile
                  _showOpacityDialog(context);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'ai',
                  child: ListTile(
                    leading: Icon(Icons.auto_awesome, color: showAIPanel ? colorScheme.primary : null),
                    title: Text(l10n.aiSmartMask),
                    dense: true,
                  ),
                ),
                PopupMenuItem(
                  value: 'opacity',
                  child: ListTile(
                    leading: const Icon(Icons.opacity),
                    title: Text(l10n.maskOpacity),
                    dense: true,
                  ),
                ),
                PopupMenuItem(
                  value: 'binary',
                  child: ListTile(
                    leading: Icon(isBinaryMode ? Icons.contrast : Icons.image),
                    title: Text(l10n.binaryMode),
                    dense: true,
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'save_temp',
                  child: ListTile(
                    leading: const Icon(Icons.save_outlined),
                    title: Text(l10n.saveToTemp),
                    dense: true,
                  ),
                ),
                PopupMenuItem(
                  value: 'save_mask',
                  child: ListTile(
                    leading: const Icon(Icons.layers_outlined),
                    title: Text(l10n.saveMaskToTemp),
                    dense: true,
                  ),
                ),
                const PopupMenuDivider(),
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
          
          if (!isMobile) ...[
            OutlinedButton(
              onPressed: onSave,
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: Text(l10n.saveToTemp, style: const TextStyle(fontSize: 12)),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: onSaveMask,
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: Text(l10n.saveMaskToTemp, style: const TextStyle(fontSize: 12)),
            ),
          ] else
            FilledButton(
              onPressed: onSaveMask,
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: Text(l10n.saveMaskToTemp, style: const TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }

  void _showOpacityDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.maskOpacity),
        content: StatefulBuilder(
          builder: (context, setState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Slider(
                value: opacity,
                min: 0.1,
                max: 1.0,
                onChanged: (val) {
                  onOpacityChanged(val);
                  setState(() {});
                },
              ),
              Text("${(opacity * 100).toInt()}%"),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK")),
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
