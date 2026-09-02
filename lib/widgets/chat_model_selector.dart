import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/llm_channel.dart';
import '../models/llm_model.dart';
import '../state/app_state.dart';
import 'models/model_picker_options.dart';
import 'searchable_picker.dart';

/// How a [ChatModelSelector] presents itself.
enum ChatModelSelectorStyle {
  /// The bare picker, drawn as every other select-like field in the app —
  /// whatever [ThemeData.inputDecorationTheme] gives it, or the caller's own
  /// [ChatModelSelector.decoration]. It carries no caption of its own: `B4`
  /// heads it with the dialog's section label, `B2` notches one into the
  /// toolbar field, and each caller draws the one it wants.
  ///
  /// This used to float a Material `labelText` inside the box, which made it
  /// the one select in the app wearing a label no other field had, at a
  /// height no other field had either.
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

  /// [ChatModelSelectorStyle.field] only: the box to draw instead of the
  /// theme's. The downloader's toolbar passes its own so this field is the
  /// same object as the two beside it.
  final InputDecoration? decoration;

  /// [ChatModelSelectorStyle.field] only: see [SearchablePickerField.expands].
  final bool expands;

  const ChatModelSelector({
    super.key,
    required this.selectedModelId,
    required this.onChanged,
    this.label,
    this.prefixIcon,
    this.models,
    this.style = ChatModelSelectorStyle.field,
    this.decoration,
    this.expands = false,
  });

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final l10n = AppLocalizations.of(context)!;
    final chatModels = models ?? appState.chatModels;
    final colorScheme = Theme.of(context).colorScheme;
    final isCard = style == ChatModelSelectorStyle.card;

    // One linear scan for the selected model, and one more for its channel.
    // What this replaces built a `DropdownMenuItem` per model on every build
    // and ran a `firstWhere` over every channel inside each one — O(models ×
    // channels) per frame, on three screens, to render a single line of text.
    LLMModel? selectedModel;
    for (final m in chatModels) {
      if (m.id == selectedModelId) {
        selectedModel = m;
        break;
      }
    }
    final selectedChannel = selectedModel == null
        ? null
        : appState.allChannels.cast<LLMChannel?>().firstWhere(
              (c) => c?.id == selectedModel!.channelId,
              orElse: () => null,
            );

    return SearchablePickerField<int>(
      selected: selectedModel == null ? null : modelPickerOption(selectedModel, channel: selectedChannel),
      // Built on open, not on build — and the channels are indexed once for
      // the whole list rather than scanned per model.
      optionsBuilder: () {
        final byId = <int?, LLMChannel>{
          for (final c in appState.allChannels) c.id: c,
        };
        return [
          for (final m in chatModels)
            if (m.id != null) modelPickerOption(m, channel: byId[m.channelId]),
        ];
      },
      onChanged: onChanged,
      hint: l10n.selectAModel,
      searchHint: l10n.searchModels,
      dialogTitle: label ?? l10n.model,
      dialogIcon: prefixIcon ?? Icons.memory_outlined,
      enabled: chatModels.isNotEmpty,
      expands: !isCard && expands,
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
          : decoration ?? const InputDecoration(),
    );
  }
}
