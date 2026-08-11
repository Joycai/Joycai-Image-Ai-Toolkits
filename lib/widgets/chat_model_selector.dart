import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../models/llm_channel.dart';
import '../models/llm_model.dart';
import '../state/app_state.dart';

/// How a [ChatModelSelector] presents itself.
enum ChatModelSelectorStyle {
  /// A bordered form field, for a selector standing among other inputs in a
  /// dialog or toolbar.
  field,

  /// A card with the label above the value, for a selector that is a section
  /// of a panel rather than one field of a form. Matches the [AppCard] blocks
  /// it sits between, which a boxed input in the same column does not.
  card,
}

class ChatModelSelector extends StatelessWidget {
  final int? selectedModelId;
  final ValueChanged<int?> onChanged;
  final String? label;
  final IconData? prefixIcon;
  final List<LLMModel>? models;
  final ChatModelSelectorStyle style;

  const ChatModelSelector({
    super.key,
    required this.selectedModelId,
    required this.onChanged,
    this.label,
    this.prefixIcon,
    this.models,
    this.style = ChatModelSelectorStyle.field,
  });

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final l10n = AppLocalizations.of(context)!;
    final chatModels = models ?? appState.chatModels;
    final colorScheme = Theme.of(context).colorScheme;
    final isCard = style == ChatModelSelectorStyle.card;

    return DropdownButtonFormField<int>(
      initialValue: selectedModelId,
      decoration: isCard
          ? InputDecoration(
              labelText: label ?? l10n.model,
              labelStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
              floatingLabelBehavior: FloatingLabelBehavior.always,
              filled: true,
              fillColor: colorScheme.surface,
              prefixIcon: prefixIcon != null ? Icon(prefixIcon, size: 18) : null,
              // An outline, not a fill step: this sits inside a panel whose
              // other blocks are outlined AppCards, and a second fill tone
              // here would make it read as a different kind of thing.
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colorScheme.outlineVariant),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colorScheme.outlineVariant),
              ),
              contentPadding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
            )
          : InputDecoration(
              labelText: label ?? l10n.model,
              // The selector's corner matches the buttons it sits beside, rather
              // than Material's default 4 — a toolbar of mixed radii reads as
              // mixed parts.
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(appButtonRadius)),
              prefixIcon: prefixIcon != null ? Icon(prefixIcon) : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
      items: chatModels.map((m) {
        final channel = appState.allChannels.cast<LLMChannel?>().firstWhere(
          (c) => c?.id == m.channelId, 
          orElse: () => null,
        );
        
        return DropdownMenuItem(
          value: m.id,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (channel != null && channel.tag != null)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Color(channel.tagColor ?? 0xFF607D8B).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    channel.tag!,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Color(channel.tagColor ?? 0xFF607D8B),
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
              Flexible(child: Text(m.modelName, overflow: TextOverflow.ellipsis)),
            ],
          ),
        );
      }).toList(),
      onChanged: onChanged,
      isExpanded: true,
    );
  }
}
