import 'package:flutter/material.dart';

import '../../core/model_kind_palette.dart';
import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../models/llm_channel.dart';
import '../../models/llm_model.dart';
import '../../services/llm/context_budget.dart';
import '../../services/llm/vendors/vendors.dart';
import '../../state/app_state.dart';
import '../app_button.dart';
import '../app_dialog.dart';
import '../app_segmented_control.dart';

class ModelEditDialog extends StatefulWidget {
  final AppLocalizations l10n;
  final AppState appState;
  final LLMModel? model;
  final int? preChannelId;

  const ModelEditDialog({
    super.key,
    required this.l10n,
    required this.appState,
    this.model,
    this.preChannelId,
  });

  @override
  State<ModelEditDialog> createState() => _ModelEditDialogState();
}

class _ModelEditDialogState extends State<ModelEditDialog> {
  late TextEditingController idCtrl;
  late TextEditingController nameCtrl;

  int? channelId;
  late String tag;
  int? feeGroupId;
  late bool supportsStream;
  late bool supportsStandard;
  late bool forceViewAllImages;
  String? reasoningEffort;
  late bool enableWebSearch;

  /// Context-window slider presets (tokens): 4K … 1M.
  static const List<int> _contextSizes = [
    4096, 8192, 16384, 32768, 65536, 131072, 262144, 524288, 1048576,
  ];
  late ContextWindowMode contextMode;
  late double contextSizeIdx;

  /// One kind chip. A method rather than an inline `ChoiceChip` in the
  /// collection-for because the kind's colour has to be looked up once and
  /// then used five times over — inline, that is five `modelTagAccent` calls
  /// per chip per build, or a local the collection-for has nowhere to put.
  Widget _buildTagChoice(
    String value,
    String label,
    TextTheme textTheme,
    ColorScheme colorScheme,
  ) {
    final color = modelTagAccent(value);
    final selected = tag == value;

    return ChoiceChip(
      selected: selected,
      onSelected: (_) => setState(() => tag = value),
      label: Text(label),
      labelStyle: textTheme.bodySmall?.copyWith(
        fontWeight: FontWeight.w600,
        color: selected ? color : colorScheme.onSurfaceVariant,
      ),
      avatar: CircleAvatar(backgroundColor: color, radius: 4),
      selectedColor: color.withAlpha(30),
      side: BorderSide(
        color: selected ? color.withAlpha(150) : colorScheme.outlineVariant,
      ),
      showCheckmark: false,
    );
  }

  /// The selectable model kinds, in the order they are offered. Colours are
  /// not repeated here — [modelTagAccent] is the one place they live, so this
  /// picker cannot drift away from the chips it is choosing between.
  static const List<(String, String)> _tagOptions = [
    ('chat', 'Chat'),
    ('image', 'Image'),
    ('video', 'Video'),
    ('multimodal', 'Multimodal'),
  ];

  @override
  void initState() {
    super.initState();
    final model = widget.model;
    idCtrl = TextEditingController(text: model?.modelId ?? '');
    nameCtrl = TextEditingController(text: model?.modelName ?? '');

    channelId = model?.channelId ?? widget.preChannelId ?? (widget.appState.allChannels.isNotEmpty ? widget.appState.allChannels.first.id : null);
    tag = model?.tag ?? 'chat';
    feeGroupId = model?.feeGroupId;
    supportsStream = model?.supportsStream ?? true;
    supportsStandard = model?.supportsStandard ?? true;
    forceViewAllImages = model?.forceViewAllImages ?? false;
    // Legacy rows carry only the boolean; show its effort equivalent so what
    // the dropdown displays is what the request layer will actually do.
    reasoningEffort = model?.reasoningEffort ??
        ((model?.enableThinking ?? false) ? 'medium' : null);
    enableWebSearch = model?.enableWebSearch ?? false;

    // Context window: null = not set, 0 = unlimited, >0 = token limit. A new
    // model starts unset rather than at a preset — this number now budgets the
    // Prompt Assistant, and a default nobody chose would silently pass for a
    // real answer.
    final cw = model?.contextWindow;
    contextMode = cw == null
        ? ContextWindowMode.unset
        : (cw <= 0 ? ContextWindowMode.unlimited : ContextWindowMode.specified);
    contextSizeIdx = (cw != null && cw > 0 ? _nearestSizeIndex(cw) : 1).toDouble();
  }

  int _nearestSizeIndex(int tokens) {
    int best = 0;
    int bestDiff = (tokens - _contextSizes[0]).abs();
    for (int i = 1; i < _contextSizes.length; i++) {
      final diff = (tokens - _contextSizes[i]).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = i;
      }
    }
    return best;
  }

  String _formatTokens(int tokens) {
    if (tokens >= 1048576) return '${tokens ~/ 1048576}M';
    if (tokens >= 1024) return '${tokens ~/ 1024}K';
    return '$tokens';
  }

  @override
  void dispose() {
    idCtrl.dispose();
    nameCtrl.dispose();
    super.dispose();
  }

  bool get _canSave =>
      channelId != null && idCtrl.text.trim().isNotEmpty && nameCtrl.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isMobile = Responsive.isMobile(context);

    return AppDialog(
      clipBehavior: Clip.antiAlias,
      maxWidth: 620,
      maxHeight: 760,
      // titleWidget rather than icon/title/subtitle: this heading keeps its
      // tinted icon tile and its own close button, neither of which the
      // shell's leading-icon layout has a place for.
      titleWidget: _buildHeader(context, colorScheme),
      scrollable: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      content: _buildForm(colorScheme, twoColumn: !isMobile),
      actions: [
        AppButton(
          label: widget.l10n.cancel,
          variant: AppButtonVariant.text,
          onPressed: () => Navigator.pop(context),
        ),
        AppButton(
          label: widget.model == null ? widget.l10n.add : widget.l10n.save,
          icon: Icons.save,
          onPressed: _canSave ? _save : null,
        ),
      ],
    );
  }

  // --- Header -------------------------------------------------------------

  /// The heading: tinted icon tile, name, model id, close.
  ///
  /// No bottom rule any more — the app's panels gave up hard divider lines
  /// for spacing, and [AppDialog]'s own gap already separates this from the
  /// form. Type comes from the scale so it matches every other dialog title.
  Widget _buildHeader(BuildContext context, ColorScheme colorScheme) {
    final l10n = widget.l10n;
    final isEdit = widget.model != null;
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            isEdit ? Icons.edit_outlined : Icons.add_box_outlined,
            size: 22,
            color: colorScheme.onPrimaryContainer,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isEdit ? l10n.editLlmModel : l10n.addLlmModel,
                style: textTheme.titleLarge,
                overflow: TextOverflow.ellipsis,
              ),
              if (isEdit)
                Text(
                  widget.model!.modelId,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontFamily: 'monospace',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  // --- Form ---------------------------------------------------------------

  Widget _buildForm(ColorScheme colorScheme, {required bool twoColumn}) {
    final l10n = widget.l10n;
    final appState = widget.appState;
    final textTheme = Theme.of(context).textTheme;

    final nameField = TextField(
      controller: nameCtrl,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: l10n.displayName,
        prefixIcon: const Icon(Icons.badge_outlined),
        hintText: 'e.g. GPT-4o, Gemini Pro',
      ),
    );
    final idField = TextField(
      controller: idCtrl,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: l10n.modelIdLabel,
        prefixIcon: const Icon(Icons.fingerprint),
        hintText: 'e.g. gpt-4, gemini-1.5-pro',
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(l10n.basicInfo),
        const SizedBox(height: 14),
        DropdownButtonFormField<int>(
          initialValue: channelId,
          isExpanded: true,
          items: appState.allChannels
              .map((c) => DropdownMenuItem(value: c.id!, child: Text(c.displayName)))
              .toList(),
          onChanged: (v) => setState(() => channelId = v),
          decoration: InputDecoration(
            labelText: l10n.channel,
            prefixIcon: const Icon(Icons.hub_outlined),
          ),
        ),
        const SizedBox(height: 14),
        if (twoColumn)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: nameField),
              const SizedBox(width: 12),
              Expanded(child: idField),
            ],
          )
        else ...[
          nameField,
          const SizedBox(height: 14),
          idField,
        ],
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (value, label) in _tagOptions)
              _buildTagChoice(value, label, textTheme, colorScheme),
          ],
        ),

        const SizedBox(height: 24),
        _sectionHeader(l10n.contextWindow),
        const SizedBox(height: 8),
        AppSegmentedControl<ContextWindowMode>(
          expand: true,
          value: contextMode,
          onChanged: (v) => setState(() => contextMode = v),
          segments: [
            AppSegment(
              value: ContextWindowMode.unset,
              label: l10n.contextUnset,
              icon: Icons.help_outline,
            ),
            AppSegment(
              value: ContextWindowMode.specified,
              label: l10n.contextSpecify,
              icon: Icons.memory_outlined,
            ),
            AppSegment(
              value: ContextWindowMode.unlimited,
              label: l10n.contextUnlimited,
              icon: Icons.all_inclusive,
            ),
          ],
        ),
        if (contextMode == ContextWindowMode.specified) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Icon(Icons.memory_outlined, size: 18, color: colorScheme.outline),
                const SizedBox(width: 8),
                Text(l10n.contextMax, style: textTheme.bodyMedium),
                const Spacer(),
                Text(
                  l10n.contextTokens(_formatTokens(_contextSizes[contextSizeIdx.round()])),
                  style: textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold, color: colorScheme.primary),
                ),
              ],
            ),
          ),
          Slider(
            value: contextSizeIdx,
            min: 0,
            max: (_contextSizes.length - 1).toDouble(),
            divisions: _contextSizes.length - 1,
            label: _formatTokens(_contextSizes[contextSizeIdx.round()]),
            onChanged: (v) => setState(() => contextSizeIdx = v),
          ),
        ],
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            switch (contextMode) {
              ContextWindowMode.unset => l10n.contextUnsetDesc,
              ContextWindowMode.specified => l10n.contextWindowHint,
              ContextWindowMode.unlimited => l10n.contextUnlimitedDesc,
            },
            style: textTheme.labelMedium?.copyWith(color: colorScheme.outline),
          ),
        ),

        const SizedBox(height: 24),
        _sectionHeader(l10n.capabilities),
        const SizedBox(height: 4),
        SwitchListTile(
          title: Text(l10n.supportsStreaming, style: textTheme.bodyMedium),
          // The muted tone is spelled out because it used to be inherited from
          // ListTile's own subtitle style, which a scale slot overrides.
          subtitle: Text(l10n.supportsStreamingDesc,
              style: textTheme.labelMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
          value: supportsStream,
          onChanged: (v) => setState(() => supportsStream = v),
          secondary: const Icon(Icons.stream),
          contentPadding: EdgeInsets.zero,
        ),
        SwitchListTile(
          title: Text(l10n.supportsStandardRequest, style: textTheme.bodyMedium),
          subtitle: Text(l10n.supportsStandardRequestDesc,
              style: textTheme.labelMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
          value: supportsStandard,
          onChanged: (v) => setState(() => supportsStandard = v),
          secondary: const Icon(Icons.http),
          contentPadding: EdgeInsets.zero,
        ),

        const SizedBox(height: 24),
        _sectionHeader(l10n.agentBehavior),
        const SizedBox(height: 4),
        SwitchListTile(
          title: Text(l10n.forceViewAllImages, style: textTheme.bodyMedium),
          subtitle: Text(l10n.forceViewAllImagesDesc,
              style: textTheme.labelMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
          value: forceViewAllImages,
          onChanged: (v) => setState(() => forceViewAllImages = v),
          secondary: const Icon(Icons.visibility_outlined),
          contentPadding: EdgeInsets.zero,
        ),
        // Reasoning intensity exists on the ① and ④ families (wire spellings
        // differ; the vocabulary is the app's own). ③/midjourney channels
        // don't see the control — a knob whose only effect is nothing is
        // worse than no knob.
        if (_channelFamily(appState) == ProtocolFamily.openai ||
            _channelFamily(appState) == ProtocolFamily.anthropic)
          DropdownButtonFormField<String>(
            // '' stands in for null: a nullable-valued form field cannot
            // distinguish "user picked default" from "no selection".
            initialValue: reasoningEffort ?? '',
            isExpanded: true,
            items: [
              DropdownMenuItem(value: '', child: Text(l10n.reasoningEffortDefault)),
              DropdownMenuItem(value: 'off', child: Text(l10n.reasoningEffortOff)),
              DropdownMenuItem(value: 'low', child: Text(l10n.reasoningEffortLow)),
              DropdownMenuItem(value: 'medium', child: Text(l10n.reasoningEffortMedium)),
              DropdownMenuItem(value: 'high', child: Text(l10n.reasoningEffortHigh)),
              DropdownMenuItem(value: 'max', child: Text(l10n.reasoningEffortMax)),
            ],
            onChanged: (v) =>
                setState(() => reasoningEffort = (v == null || v.isEmpty) ? null : v),
            decoration: InputDecoration(
              labelText: l10n.reasoningEffort,
              helperText: l10n.reasoningEffortDesc,
              helperMaxLines: 3,
              prefixIcon: const Icon(Icons.psychology_outlined),
            ),
          ),
        // Host-run web search only exists on ④.
        if (_isAnthropicChannel(appState)) ...[
          SwitchListTile(
            title: Text(l10n.enableWebSearch, style: textTheme.bodyMedium),
            subtitle: Text(l10n.enableWebSearchDesc,
                style: textTheme.labelMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
            value: enableWebSearch,
            onChanged: (v) => setState(() => enableWebSearch = v),
            secondary: const Icon(Icons.travel_explore_outlined),
            contentPadding: EdgeInsets.zero,
          ),
        ],

        const SizedBox(height: 24),
        _sectionHeader(l10n.billing),
        const SizedBox(height: 14),
        DropdownButtonFormField<int>(
          initialValue: feeGroupId,
          isExpanded: true,
          items: [
            DropdownMenuItem(
              value: null,
              child: Text(l10n.noFeeGroup, style: TextStyle(color: colorScheme.outline)),
            ),
            ...appState.allPricingGroups.map((g) => DropdownMenuItem(value: g.id!, child: Text(g.name))),
          ],
          onChanged: (v) => setState(() => feeGroupId = v),
          decoration: InputDecoration(
            labelText: l10n.feeGroup,
            prefixIcon: const Icon(Icons.payments_outlined),
          ),
        ),
      ],
    );
  }


  /// The selected channel's protocol family, or null when no channel is
  /// picked. Read-only Layer 2 consumption, like app_state's video check.
  ProtocolFamily? _channelFamily(AppState appState) {
    final channel = appState.allChannels
        .cast<LLMChannel?>()
        .firstWhere((c) => c?.id == channelId, orElse: () => null);
    return channel == null ? null : Vendors.byId(channel.type).family;
  }

  /// Whether the selected channel speaks Anthropic Messages — the only
  /// family with a host-run web search.
  bool _isAnthropicChannel(AppState appState) =>
      _channelFamily(appState) == ProtocolFamily.anthropic;

  Future<void> _save() async {
    final data = {
      'model_id': idCtrl.text.trim(),
      'model_name': nameCtrl.text.trim(),
      'tag': tag,
      'is_paid': 1,
      'supports_stream': supportsStream ? 1 : 0,
      'supports_standard': supportsStandard ? 1 : 0,
      'force_view_all_images': forceViewAllImages ? 1 : 0,
      // The legacy flag is kept in sync so a backup restored into an older
      // build (which only reads the boolean) preserves thinking behavior.
      'enable_thinking':
          (reasoningEffort != null && reasoningEffort != 'off') ? 1 : 0,
      'reasoning_effort': reasoningEffort,
      'enable_web_search': enableWebSearch ? 1 : 0,
      'fee_group_id': feeGroupId,
      'channel_id': channelId,
      'context_window': ContextBudget.store(contextMode, _contextSizes[contextSizeIdx.round()]),
    };

    if (widget.model == null) {
      await widget.appState.addModel(data);
    } else {
      await widget.appState.updateModel(widget.model!.id!, data);
    }

    if (mounted) Navigator.pop(context);
  }

  Widget _sectionHeader(String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
                letterSpacing: 1.2,
              ),
        ),
        const SizedBox(height: 4),
        const Divider(height: 1),
      ],
    );
  }
}
