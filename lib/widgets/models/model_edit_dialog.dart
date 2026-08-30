import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/model_kind_palette.dart';
import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../models/llm_channel.dart';
import '../../models/llm_model.dart';
import '../../models/pricing_group.dart';
import '../../services/llm/context_budget.dart';
import '../../services/llm/llm_dispatcher.dart';
import '../../services/llm/vendors/vendors.dart';
import '../../state/app_state.dart';
import '../app_button.dart';
import '../app_card.dart';
import '../app_dialog.dart';
import '../app_labelled_field.dart';
import '../app_segmented_control.dart';
import '../app_setting_row.dart';
import '../app_text_field.dart';
import '../searchable_picker.dart';
import 'channel_avatar.dart';
import 'model_picker_options.dart';
import 'model_tag_chip.dart';
import 'wire_protocol_labels.dart';
import '../../core/design_tokens.dart';

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

  /// Stored wire-protocol selection (`WireProtocol.id` string), null = auto.
  /// Kept verbatim while editing — a stale value is *shown* as stale but not
  /// touched until the user saves, at which point it is silently cleared
  /// (18a state ④: never mutate what the user hasn't opened).
  String? wireProtocol;

  /// Viewport width at which the form splits into two panes.
  ///
  /// Above the desktop breakpoint rather than at it: at 1000 the dialog would
  /// be as wide as the window and each pane narrower than the single-column
  /// form it replaces, which is a worse form, not a wider one. 1100 is the
  /// first width where two 460-ish panes and the dialog's own inset all fit.
  static const double _twoPaneMinWidth = 1100;

  /// Dialog width in each layout. The single-column figure is the one the
  /// form was drawn for; the two-pane one is deliberately below
  /// [_twoPaneMinWidth] so the dialog still floats rather than filling the
  /// window at the moment it splits.
  static const double _twoPaneWidth = 1000;
  static const double _singlePaneWidth = 620;

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
      // A stadium, not Material's default rounded rectangle: the spec draws
      // the kind picker as pills, one full step rounder than the input boxes
      // around it.
      shape: const StadiumBorder(),
      visualDensity: VisualDensity.compact,
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

  /// The reasoning-effort ladder, in the order it is offered. `null` is the
  /// default rung — "send no field at all" — and is spelled `''` in the form
  /// because a nullable-valued dropdown cannot tell "picked default" from
  /// "nothing picked". Listed once so the dropdown and the summary card can
  /// never disagree about what a stored value is called.
  List<(String, String)> get _effortOptions => [
        ('', widget.l10n.reasoningEffortDefault),
        ('off', widget.l10n.reasoningEffortOff),
        ('low', widget.l10n.reasoningEffortLow),
        ('medium', widget.l10n.reasoningEffortMedium),
        ('high', widget.l10n.reasoningEffortHigh),
        ('max', widget.l10n.reasoningEffortMax),
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
    wireProtocol = model?.wireProtocol;

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
    final twoPane = MediaQuery.sizeOf(context).width >= _twoPaneMinWidth;

    return AppDialog(
      clipBehavior: Clip.antiAlias,
      maxWidth: twoPane ? _twoPaneWidth : _singlePaneWidth,
      // Taller when split, because the point of splitting is that the form
      // fits without scrolling and the single-column cap is a hair short of
      // the taller pane. Both figures are still ceilings — the dialog is
      // clamped to the window and the body scrolls if it has to.
      maxHeight: twoPane ? 860 : 760,
      // titleWidget rather than icon/title/subtitle: this heading keeps its
      // tinted icon tile and its own close button, neither of which the
      // shell's leading-icon layout has a place for.
      titleWidget: _buildHeader(context, colorScheme, showChannelBadge: twoPane),
      scrollable: true,
      // The narrow layout separates heading from form by spacing alone, as
      // the spec draws it; the wide one keeps the rule. The footer is ruled
      // in both.
      dividedHeading: twoPane,
      // Horizontal inset matches the shell's own (20), so the section labels
      // sit on the same left edge as the heading and the footer. It was 24,
      // and the 4px stagger read as sloppiness rather than intent.
      contentPadding: EdgeInsets.fromLTRB(20, twoPane ? 12 : 4, 20, 16),
      // Fields at the spec's 40px. The app theme's dense inputs land at ~44;
      // with a caption now above every field the extra 4px × five fields is
      // what stood between the wide layout and the spec's no-scroll promise.
      //
      // FilledFieldScope goes *inside*, not outside: it reads the ambient
      // decoration theme from its own context and adds the fill to it. Wrapped
      // the other way round, this Theme's `Theme.of(context)` resolves above
      // the scope and overwrites the fill it had just added — the fields came
      // out flush with the panel again, which is what a nested override always
      // does when it rebuilds a value from the wrong context.
      content: Theme(
        data: Theme.of(context).copyWith(
          inputDecorationTheme: Theme.of(context).inputDecorationTheme.copyWith(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
        ),
        child: FilledFieldScope(
          child: twoPane ? _buildTwoPane(colorScheme) : _buildSinglePane(colorScheme),
        ),
      ),
      // actionsOverride, not actions: the footer pairs a left-aligned reason
      // the save is unavailable with the right-aligned buttons.
      actionsOverride: _buildFooter(context, colorScheme),
    );
  }

  // --- Header -------------------------------------------------------------

  /// The heading: tinted icon tile, name, model id, close.
  ///
  /// No bottom rule any more — the app's panels gave up hard divider lines
  /// for spacing, and [AppDialog]'s own gap already separates this from the
  /// form. Type comes from the scale so it matches every other dialog title.
  Widget _buildHeader(
    BuildContext context,
    ColorScheme colorScheme, {
    required bool showChannelBadge,
  }) {
    final l10n = widget.l10n;
    final isEdit = widget.model != null;
    final textTheme = Theme.of(context).textTheme;
    final channel = _selectedChannel(widget.appState);

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
                  style: textTheme.bodySmall?.mono.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        // Which endpoint this model will be reached through, restated in the
        // heading. Only in the two-pane layout: there the channel field sits
        // at the top of a column the eye no longer starts at, and the fields
        // it governs (reasoning effort, host web search) are a pane away.
        if (showChannelBadge && channel != null) ...[
          const SizedBox(width: 12),
          // Non-flex, capped. As a Flexible it shared the row's free space
          // with the title's Expanded, and its unused share became trailing
          // blank — parking the badge and the close button mid-row instead of
          // in the corner the design puts them in.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
              child: Text(
                '${channel.displayName} · ${channel.type}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelSmall?.mono.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
        IconButton(
          icon: const Icon(Icons.close, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  // --- Footer -------------------------------------------------------------

  /// Cancel and save, with the reason save is unavailable beside them.
  ///
  /// The hint is on the left rather than under the field that is empty
  /// because there is no single such field — it is the *combination* of
  /// channel, name and id that gates the button, and a disabled button with
  /// nothing explaining it is the thing this dialog was most often stuck on.
  Widget _buildFooter(BuildContext context, ColorScheme colorScheme) {
    final l10n = widget.l10n;

    return Row(
      children: [
        Expanded(
          child: _canSave
              ? const SizedBox.shrink()
              : Text(
                  l10n.modelSaveRequirementHint,
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(color: colorScheme.outline),
                ),
        ),
        const SizedBox(width: 12),
        AppButton(
          label: l10n.cancel,
          variant: AppButtonVariant.text,
          onPressed: () => Navigator.pop(context),
        ),
        const SizedBox(width: 8),
        AppButton(
          label: widget.model == null ? l10n.add : l10n.save,
          icon: Icons.save_outlined,
          onPressed: _canSave ? _save : null,
        ),
      ],
    );
  }

  // --- Layouts ------------------------------------------------------------

  /// Every section in one column, in the order the form is read.
  ///
  /// Name and id share a row on anything but a phone: they are the same kind
  /// of short identifier and the 620-wide dialog has room for both.
  Widget _buildSinglePane(ColorScheme colorScheme) {
    final pairNameAndId = !Responsive.isMobile(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _basicInfoSection(colorScheme, pairNameAndId: pairNameAndId),
        const SizedBox(height: 24),
        _contextSection(colorScheme),
        // The protocol section leads the settings it governs (17c: the
        // protocol is the *cause* of the parameters under it) and does not
        // exist at all on a single-entry menu — unless a stale selection
        // needs explaining (state ④).
        if (_showProtocolSection) ...[
          const SizedBox(height: 24),
          _protocolSection(colorScheme),
        ],
        const SizedBox(height: 24),
        _capabilitiesSection(colorScheme),
        const SizedBox(height: 24),
        _agentSection(colorScheme),
        const SizedBox(height: 24),
        _billingSection(colorScheme),
      ],
    );
  }

  /// Identity on the left, behaviour on the right, with a summary of both
  /// under the behaviour column.
  ///
  /// Separated by a gap rather than the centre rule the spec draws. A rule
  /// has to span whichever pane is taller, which means [IntrinsicHeight], and
  /// the channel picker cannot be measured intrinsically — it sizes its tag
  /// chip against a [LayoutBuilder]. Spacing is also what the rest of the
  /// app's panels use in place of hard dividers, so the gap is the more
  /// consistent of the two answers rather than only the cheaper one.
  Widget _buildTwoPane(ColorScheme colorScheme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Stacked here, not paired: a pane is half the dialog, and two
              // fields side by side in it truncate the very ids they exist to
              // show.
              _basicInfoSection(colorScheme, pairNameAndId: false),
              // 20, a step under the single column's 24: the wide layout's
              // whole point is fitting without a scrollbar, and these two
              // gaps are the cheapest height left.
              const SizedBox(height: 20),
              _contextSection(colorScheme),
              const SizedBox(height: 20),
              _billingSection(colorScheme),
            ],
          ),
        ),
        const SizedBox(width: 32),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // First section of the right pane (17c placement B): the
              // protocol is the cause of everything under it. Absent
              // entirely on a single-entry menu (no placeholder height)
              // unless a stale selection needs explaining (state ④).
              if (_showProtocolSection) ...[
                _protocolSection(colorScheme),
                const SizedBox(height: 20),
              ],
              _capabilitiesSection(colorScheme),
              const SizedBox(height: 20),
              _agentSection(colorScheme),
              const SizedBox(height: 20),
              _previewCard(colorScheme),
            ],
          ),
        ),
      ],
    );
  }

  // --- Sections -----------------------------------------------------------

  Widget _basicInfoSection(ColorScheme colorScheme, {required bool pairNameAndId}) {
    final l10n = widget.l10n;
    final appState = widget.appState;
    final textTheme = Theme.of(context).textTheme;
    final channel = _selectedChannel(appState);

    final nameField = AppLabelledField(
      label: l10n.displayName,
      child: TextField(
        controller: nameCtrl,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.badge_outlined),
          hintText: 'e.g. GPT-4o, Gemini Pro',
        ),
      ),
    );
    final idField = AppLabelledField(
      label: l10n.modelIdLabel,
      child: TextField(
        controller: idCtrl,
        onChanged: (_) => setState(() {}),
        // Mono: this is an identifier the wire will see verbatim, and the
        // spec sets it apart from the display name that way.
        style: textTheme.bodyMedium?.mono,
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.fingerprint),
          hintText: 'e.g. gpt-4, gemini-1.5-pro',
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(l10n.basicInfo),
        const SizedBox(height: 12),
        // The searchable picker, not a `DropdownButton`: it carries the
        // channel's own identity disc — the round form the design gives this
        // field — and is the control every other channel choice in the app
        // uses.
        AppLabelledField(
          label: l10n.channel,
          child: SearchablePickerField<int>(
            selected: channel == null ? null : channelPickerOption(channel),
            optionsBuilder: () => appState.allChannels.map(channelPickerOption).toList(),
            onChanged: (v) => setState(() => channelId = v),
            hint: l10n.selectAChannel,
            searchHint: l10n.searchChannels,
            dialogIcon: Icons.hub_outlined,
            enabled: appState.allChannels.isNotEmpty,
            badgeStyle: PickerBadge.avatar,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.hub_outlined),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (pairNameAndId)
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
          const SizedBox(height: 12),
          idField,
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (value, label) in _tagOptions)
              _buildTagChoice(value, label, textTheme, colorScheme),
          ],
        ),
      ],
    );
  }

  Widget _contextSection(ColorScheme colorScheme) {
    final l10n = widget.l10n;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(l10n.contextWindow),
        const SizedBox(height: 8),
        AppSegmentedControl<ContextWindowMode>(
          expand: true,
          // The form skin: this track sits among input boxes and `13a` draws
          // it as one of them. Every other segmented control in the app is on
          // a toolbar or a canvas, where the filled track is right.
          track: AppSegmentTrack.outlined,
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
                      ?.copyWith(color: colorScheme.primary),
                ),
              ],
            ),
          ),
          // Divisions for the snap, but no tick dots: the spec's track is a
          // clean line, and the scale row below already says where the stops
          // are.
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              tickMarkShape: SliderTickMarkShape.noTickMark,
              // A 14px halo instead of Material's 24: the default budgets
              // 48px of height for a control the spec draws in 26, and the
              // difference is most of what pushed the wide layout past its
              // no-scroll promise.
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: contextSizeIdx,
              min: 0,
              max: (_contextSizes.length - 1).toDouble(),
              divisions: _contextSizes.length - 1,
              label: _formatTokens(_contextSizes[contextSizeIdx.round()]),
              onChanged: (v) => setState(() => contextSizeIdx = v),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final size in _contextSizes)
                Text(
                  _formatTokens(size),
                  style: textTheme.labelSmall?.mono
                      .copyWith(color: colorScheme.outline),
                ),
            ],
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
      ],
    );
  }

  Widget _capabilitiesSection(ColorScheme colorScheme) {
    final l10n = widget.l10n;
    final textTheme = Theme.of(context).textTheme;
    final asyncPinned = _asyncImagePinned;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(l10n.capabilities),
        const SizedBox(height: 4),
        // With the async task pinned the streaming toggle is inert: the value
        // is preserved, not rewritten (18a state ③ — switch back to auto and
        // it comes back untouched), the row just dims and says why.
        Opacity(
          opacity: asyncPinned ? 0.55 : 1.0,
          child: AppToggleRow(
            icon: Icons.waves,
            title: l10n.supportsStreaming,
            description: asyncPinned
                ? l10n.protocolStreamIgnoredAsync
                : l10n.supportsStreamingDesc,
            value: supportsStream,
            onChanged:
                asyncPinned ? null : (v) => setState(() => supportsStream = v),
          ),
        ),
        AppToggleRow(
          icon: Icons.http,
          title: l10n.supportsStandardRequest,
          description: l10n.supportsStandardRequestDesc,
          value: supportsStandard,
          onChanged: (v) => setState(() => supportsStandard = v),
        ),
        // The queue note (18a linkage: appears with the async selection).
        AnimatedSize(
          duration: AppMotion.durationOf(context, AppMotion.reveal),
          curve: AppMotion.enter,
          alignment: Alignment.topCenter,
          child: !asyncPinned
              ? const SizedBox(width: double.infinity)
              : Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    border: Border.all(
                        color: colorScheme.primary.withValues(alpha: 0.28)),
                  ),
                  child: Text(
                    l10n.protocolAsyncQueueNote,
                    style: textTheme.labelMedium
                        ?.copyWith(color: colorScheme.primary),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _agentSection(ColorScheme colorScheme) {
    final l10n = widget.l10n;
    final appState = widget.appState;
    final family = _channelFamily(appState);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(l10n.agentBehavior),
        const SizedBox(height: 4),
        AppToggleRow(
          icon: Icons.visibility_outlined,
          title: l10n.forceViewAllImages,
          description: l10n.forceViewAllImagesDesc,
          value: forceViewAllImages,
          onChanged: (v) => setState(() => forceViewAllImages = v),
        ),
        // Which families consume the knob is the dispatcher's knowledge, not
        // this dialog's — a copy here went stale the day C2 started reading
        // reasoningEffort and hid the control on dashscope-native channels.
        if (family != null && LLMDispatcher.chatConsumesReasoningEffort(family))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: AppLabelledField(
              label: l10n.reasoningEffort,
              child: DropdownButtonFormField<String>(
                // '' stands in for null: a nullable-valued form field cannot
                // distinguish "user picked default" from "no selection".
                initialValue: reasoningEffort ?? '',
                isExpanded: true,
                items: [
                  for (final (value, label) in _effortOptions)
                    DropdownMenuItem(value: value, child: Text(label)),
                ],
                onChanged: (v) =>
                    setState(() => reasoningEffort = (v == null || v.isEmpty) ? null : v),
                decoration: InputDecoration(
                  helperText: l10n.reasoningEffortDesc,
                  helperMaxLines: 3,
                  prefixIcon: const Icon(Icons.lightbulb_outlined),
                ),
              ),
            ),
          ),
        // Host-run web search only exists on ④.
        if (family == ProtocolFamily.anthropic)
          AppToggleRow(
            icon: Icons.public,
            title: l10n.enableWebSearch,
            description: l10n.enableWebSearchDesc,
            value: enableWebSearch,
            onChanged: (v) => setState(() => enableWebSearch = v),
          ),
      ],
    );
  }

  Widget _billingSection(ColorScheme colorScheme) {
    final l10n = widget.l10n;
    final appState = widget.appState;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(l10n.billing),
        const SizedBox(height: 12),
        AppLabelledField(
          label: l10n.feeGroup,
          child: DropdownButtonFormField<int>(
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
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.money_outlined),
          ),
          ),
        ),
      ],
    );
  }

  // --- Summary card -------------------------------------------------------

  /// What the models screen will show for this model once it is saved.
  ///
  /// The wide layout has room the narrow one does not, and the thing worth
  /// spending it on is the answer to "what did I just configure?" — the four
  /// settings that live on the model card, gathered from both panes so
  /// neither has to be re-read.
  Widget _previewCard(ColorScheme colorScheme) {
    final l10n = widget.l10n;
    final appState = widget.appState;
    final textTheme = Theme.of(context).textTheme;

    final channel = _selectedChannel(appState);
    final family = _channelFamily(appState);
    final name = nameCtrl.text.trim();

    final capabilities = [
      if (supportsStream) l10n.capabilityStreamingShort,
      if (supportsStandard) l10n.capabilityStandardShort,
    ];

    final feeGroup = appState.allPricingGroups
        .cast<PricingGroup?>()
        .firstWhere((g) => g?.id == feeGroupId, orElse: () => null);

    return AppCard(
      outlined: true,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // A disc, not the chip the picker above draws. The spec gives
              // the channel its round form wherever it is being *named* rather
              // than chosen, and this is the same glyph the models screen puts
              // on a channel row — so the card previews what the row will
              // actually look like.
              if (channel != null) ...[
                ChannelAvatar(channel),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  name.isEmpty ? l10n.displayName : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleSmall?.copyWith(
                    color: name.isEmpty ? colorScheme.outline : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ModelTagChip(tag),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: AppAlpha.tint),
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                child: Text(
                  l10n.cardPreview,
                  style: textTheme.labelSmall?.mono
                      .copyWith(color: colorScheme.primary, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          _previewRow(
            colorScheme,
            l10n.contextWindow,
            switch (contextMode) {
              ContextWindowMode.unset => l10n.contextUnset,
              ContextWindowMode.unlimited => l10n.contextUnlimited,
              ContextWindowMode.specified =>
                l10n.contextTokens(_formatTokens(_contextSizes[contextSizeIdx.round()])),
            },
          ),
          _previewRow(
            colorScheme,
            l10n.capabilities,
            capabilities.isEmpty ? '—' : capabilities.join(' · '),
          ),
          if (family != null &&
              LLMDispatcher.chatConsumesReasoningEffort(family))
            _previewRow(
              colorScheme,
              l10n.reasoningEffort,
              _effortOptions
                  .firstWhere((o) => o.$1 == (reasoningEffort ?? ''))
                  .$2,
            ),
          _previewRow(colorScheme, l10n.feeGroup, feeGroup?.name ?? l10n.noFeeGroup),
        ],
      ),
    );
  }

  Widget _previewRow(ColorScheme colorScheme, String label, String value) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: textTheme.labelMedium?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  // --- Wire protocol (18a) ------------------------------------------------

  /// The protocol menu for the current channel + model-id pair, or empty when
  /// either is missing. Length ≤ 1 means the whole section does not render —
  /// state ①: no section header, no placeholder height.
  List<WireProtocol> get _protocolMenu {
    final channel = _selectedChannel(widget.appState);
    final id = idCtrl.text.trim();
    if (channel == null || id.isEmpty) return const [];
    return LLMDispatcher.protocolMenuFor(channel.type, id);
  }

  /// The stored selection when it is still valid on the current menu; null
  /// for auto *and* for a stale value (which routes as auto).
  WireProtocol? get _activePin {
    final parsed = WireProtocol.tryParse(wireProtocol);
    if (parsed == null) return null;
    return _protocolMenu.contains(parsed) ? parsed : null;
  }

  /// Whether the stored selection exists but no longer applies (18a state ④).
  bool get _pinIsStale =>
      wireProtocol != null && wireProtocol!.isNotEmpty && _activePin == null;

  /// The image-generation route is the async task flow — drives the
  /// stream-toggle downgrade and the queue note in the capabilities section.
  bool get _asyncImagePinned =>
      _activePin == WireProtocol.dashscopeImagesAsync;

  /// Whether the protocol section renders at all: a real choice exists, or a
  /// stale selection needs explaining (18a state ④ shows the section on a
  /// single-protocol vendor so the fallback note has somewhere to live).
  bool get _showProtocolSection => _protocolMenu.length > 1 || _pinIsStale;

  Widget _protocolSection(ColorScheme colorScheme) {
    final l10n = widget.l10n;
    final textTheme = Theme.of(context).textTheme;
    final menu = _protocolMenu;
    final active = _activePin;
    final auto = menu.isEmpty ? null : menu.first;

    final String? helper;
    if (_pinIsStale) {
      // State ④: helper-text tone, not a warning — the model still runs.
      helper = l10n.protocolStaleHelper(
          storedProtocolLabel(l10n, wireProtocol!));
    } else if (active == null) {
      helper = l10n.protocolAutoHelper;
    } else {
      helper = wireProtocolDescription(l10n, active);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(l10n.requestMethod),
        const SizedBox(height: 12),
        AppLabelledField(
          label: l10n.interfaceProtocol,
          child: DropdownButtonFormField<String>(
            // Re-created whenever the pair changes: a form field only reads
            // initialValue once, and the menu it belongs to changes with the
            // channel and the id.
            key: ValueKey(
                'wire-protocol-${_selectedChannel(widget.appState)?.type}-${idCtrl.text.trim()}'),
            // '' stands in for auto, same convention as the effort dropdown.
            // A stale stored value also *displays* as auto (that is how it
            // routes) — the helper line below says why.
            initialValue: active?.id ?? '',
            isExpanded: true,
            items: [
              DropdownMenuItem(value: '', child: Text(l10n.protocolAuto)),
              for (final p in menu)
                DropdownMenuItem(
                    value: p.id, child: Text(wireProtocolLabel(l10n, p))),
            ],
            // The closed field answers "which one actually runs": the auto
            // entry names its resolution (18a: 自动 · 当前解析为 X).
            selectedItemBuilder: (context) => [
              Text(
                auto == null
                    ? l10n.protocolAuto
                    : l10n.protocolAutoResolved(wireProtocolLabel(l10n, auto)),
                overflow: TextOverflow.ellipsis,
              ),
              for (final p in menu)
                Text(wireProtocolLabel(l10n, p),
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium
                        ?.copyWith(color: colorScheme.primary)),
            ],
            onChanged: (v) => setState(
                () => wireProtocol = (v == null || v.isEmpty) ? null : v),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.alt_route_outlined),
              helperText: helper,
              helperMaxLines: 3,
            ),
          ),
        ),
      ],
    );
  }

  // --- Channel lookups ----------------------------------------------------

  /// The channel the form currently points at, or null when none is picked.
  LLMChannel? _selectedChannel(AppState appState) => appState.allChannels
      .cast<LLMChannel?>()
      .firstWhere((c) => c?.id == channelId, orElse: () => null);

  /// The selected channel's protocol family, or null when no channel is
  /// picked. Read-only Layer 2 consumption, like app_state's video check.
  ProtocolFamily? _channelFamily(AppState appState) {
    final channel = _selectedChannel(appState);
    return channel == null ? null : Vendors.byId(channel.type).family;
  }

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
      // Auto stores null; a stale value is silently cleared *here* — on the
      // user's own save, never behind their back (18a state ④ contract).
      'wire_protocol': _activePin?.id,
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
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.primary,
                letterSpacing: AppType.trackedLabelSpacing,
              ),
        ),
        const SizedBox(height: 4),
        // Half-strength. The spec draws these baselines a shade the eye
        // barely registers; at full outlineVariant five of them plus the
        // structural heading/footer rules read as a page full of lines.
        Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: AppAlpha.edge)),
      ],
    );
  }
}
