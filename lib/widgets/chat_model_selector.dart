import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/llm_channel.dart';
import '../state/app_state.dart';

class ChatModelSelector extends StatelessWidget {
  final int? selectedModelId;
  final ValueChanged<int?> onChanged;
  final String? label;
  final IconData? prefixIcon;

  const ChatModelSelector({
    super.key,
    required this.selectedModelId,
    required this.onChanged,
    this.label,
    this.prefixIcon,
  });

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final l10n = AppLocalizations.of(context)!;
    final chatModels = appState.chatModels;

    return DropdownButtonFormField<int>(
      initialValue: selectedModelId,
      decoration: InputDecoration(
        labelText: label ?? l10n.model,
        border: const OutlineInputBorder(),
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
                    style: TextStyle(
                      fontSize: 9, 
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
