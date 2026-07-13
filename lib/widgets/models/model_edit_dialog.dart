import 'package:flutter/material.dart';

import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../models/llm_model.dart';
import '../../services/llm/channel_dialect.dart';
import '../../state/app_state.dart';

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

  /// Context-window slider presets (tokens): 4K … 1M.
  static const List<int> _contextSizes = [
    4096, 8192, 16384, 32768, 65536, 131072, 262144, 524288, 1048576,
  ];
  late bool unlimitedContext;
  late double contextSizeIdx;

  /// Tag palette mirrors the chips on the models screen.
  static const List<(String, String, Color)> _tagOptions = [
    ('chat', 'Chat', Colors.green),
    ('image', 'Image', Colors.purple),
    ('video', 'Video', Colors.red),
    ('multimodal', 'Multimodal', Colors.orange),
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

    // Context window: null = not configured, 0 = unlimited, >0 = token limit.
    final cw = model?.contextWindow;
    unlimitedContext = cw != null && cw <= 0;
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

    return Dialog(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 40, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 760),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(colorScheme),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                child: _buildForm(colorScheme, twoColumn: !isMobile),
              ),
            ),
            _buildFooter(colorScheme),
          ],
        ),
      ),
    );
  }

  // --- Header -------------------------------------------------------------

  Widget _buildHeader(ColorScheme colorScheme) {
    final l10n = widget.l10n;
    final isEdit = widget.model != null;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 10, 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withAlpha(90))),
      ),
      child: Row(
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
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
                if (isEdit)
                  Text(
                    widget.model!.modelId,
                    style: TextStyle(
                      fontSize: 11,
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
      ),
    );
  }

  // --- Form ---------------------------------------------------------------

  Widget _buildForm(ColorScheme colorScheme, {required bool twoColumn}) {
    final l10n = widget.l10n;
    final appState = widget.appState;

    final nameField = TextField(
      controller: nameCtrl,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: l10n.displayName,
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.badge_outlined),
        hintText: 'e.g. GPT-4o, Gemini Pro',
      ),
    );
    final idField = TextField(
      controller: idCtrl,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: l10n.modelIdLabel,
        border: const OutlineInputBorder(),
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
            border: const OutlineInputBorder(),
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
            for (final (value, label, color) in _tagOptions)
              ChoiceChip(
                selected: tag == value,
                onSelected: (_) => setState(() => tag = value),
                label: Text(label),
                labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: tag == value ? color : colorScheme.onSurfaceVariant,
                ),
                avatar: CircleAvatar(backgroundColor: color, radius: 4),
                selectedColor: color.withAlpha(30),
                side: BorderSide(
                  color: tag == value ? color.withAlpha(150) : colorScheme.outlineVariant,
                ),
                showCheckmark: false,
              ),
          ],
        ),

        const SizedBox(height: 24),
        _sectionHeader(l10n.contextWindow),
        const SizedBox(height: 4),
        SwitchListTile(
          title: Text(l10n.contextUnlimited, style: const TextStyle(fontSize: 13)),
          subtitle: Text(l10n.contextUnlimitedDesc, style: const TextStyle(fontSize: 11)),
          value: unlimitedContext,
          onChanged: (v) => setState(() => unlimitedContext = v),
          secondary: const Icon(Icons.all_inclusive),
          contentPadding: EdgeInsets.zero,
        ),
        if (!unlimitedContext) ...[
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Icon(Icons.memory_outlined, size: 18, color: colorScheme.outline),
                const SizedBox(width: 8),
                Text(l10n.contextMax, style: const TextStyle(fontSize: 13)),
                const Spacer(),
                Text(
                  l10n.contextTokens(_formatTokens(_contextSizes[contextSizeIdx.round()])),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: colorScheme.primary),
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
          Text(
            l10n.contextWindowHint,
            style: TextStyle(color: colorScheme.outline, fontSize: 11),
          ),
        ],

        const SizedBox(height: 24),
        _sectionHeader(l10n.capabilities),
        const SizedBox(height: 4),
        SwitchListTile(
          title: Text(l10n.supportsStreaming, style: const TextStyle(fontSize: 13)),
          subtitle: Text(l10n.supportsStreamingDesc, style: const TextStyle(fontSize: 11)),
          value: supportsStream,
          onChanged: (v) => setState(() => supportsStream = v),
          secondary: const Icon(Icons.stream),
          contentPadding: EdgeInsets.zero,
        ),
        SwitchListTile(
          title: Text(l10n.supportsStandardRequest, style: const TextStyle(fontSize: 13)),
          subtitle: Text(l10n.supportsStandardRequestDesc, style: const TextStyle(fontSize: 11)),
          value: supportsStandard,
          onChanged: (v) => setState(() => supportsStandard = v),
          secondary: const Icon(Icons.http),
          contentPadding: EdgeInsets.zero,
        ),

        const SizedBox(height: 24),
        _sectionHeader(l10n.agentBehavior),
        const SizedBox(height: 4),
        SwitchListTile(
          title: Text(l10n.forceViewAllImages, style: const TextStyle(fontSize: 13)),
          subtitle: Text(l10n.forceViewAllImagesDesc, style: const TextStyle(fontSize: 11)),
          value: forceViewAllImages,
          onChanged: (v) => setState(() => forceViewAllImages = v),
          secondary: const Icon(Icons.visibility_outlined),
          contentPadding: EdgeInsets.zero,
        ),

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
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.payments_outlined),
          ),
        ),
      ],
    );
  }

  // --- Footer -------------------------------------------------------------

  Widget _buildFooter(ColorScheme colorScheme) {
    final l10n = widget.l10n;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colorScheme.outlineVariant.withAlpha(90))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _canSave ? _save : null,
            icon: const Icon(Icons.save, size: 18),
            label: Text(widget.model == null ? l10n.add : l10n.save),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final channel = widget.appState.allChannels.firstWhere((c) => c.id == channelId);
    final data = {
      'model_id': idCtrl.text.trim(),
      'model_name': nameCtrl.text.trim(),
      'type': ChannelDialect.providerType(channel.type),
      'tag': tag,
      'is_paid': 1,
      'supports_stream': supportsStream ? 1 : 0,
      'supports_standard': supportsStandard ? 1 : 0,
      'force_view_all_images': forceViewAllImages ? 1 : 0,
      'fee_group_id': feeGroupId,
      'channel_id': channelId,
      'context_window': unlimitedContext ? 0 : _contextSizes[contextSizeIdx.round()],
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
          style: TextStyle(
            fontSize: 11,
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
