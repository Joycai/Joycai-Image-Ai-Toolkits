import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_theme.dart';
import '../../core/design_tokens.dart';
import '../../core/model_kind_palette.dart';
import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../models/llm_channel.dart';
import '../../models/llm_model.dart';
import '../../models/pricing_group.dart';
import '../../services/llm/context_budget.dart';
import '../../services/llm/llm_dispatcher.dart';
import '../../services/llm/llm_types.dart';
import '../../services/llm/vendors/vendors.dart';
import '../../state/app_state.dart';
import '../app_button.dart';
import '../app_dialog.dart';
import '../app_dropdown.dart';
import '../app_field_size.dart';
import '../app_labelled_field.dart';
import '../app_section_label.dart';
import '../glass/app_glass.dart';
import '../searchable_picker.dart';
import 'model_edit_card_preview.dart';
import 'model_edit_controls.dart';
import 'model_picker_options.dart';
import 'model_protocol_section.dart';
import 'protocol_section_form.dart';
import 'wire_protocol_labels.dart';

/// Edits a model, or adds one (design D1c).
///
/// Three forms from one state:
///
/// - **Edit, dialog** (`1a`): 920 wide, two columns — what the model *is* on
///   the left (identity, capabilities, the card it will make), how it is
///   *requested* on the right (request method, context window, agent
///   behaviour, reasoning, provider features). Folds to one column when the
///   dialog is too narrow to hold two.
/// - **Edit, phone** (`1e`): a full-screen page under a glass bar with a
///   tinted-glass Save.
/// - **Add** (`1e` right): 520 wide, ID / name / kind only — everything else
///   stays on Auto or its default until the model has run once.
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

  /// The Specify figure, typed rather than picked off a preset ladder (`1d`).
  late TextEditingController contextCtrl;

  int? channelId;
  late String tag;
  int? feeGroupId;
  late bool supportsStream;
  late bool supportsStandard;
  late bool forceViewAllImages;
  String? reasoningEffort;
  late bool enableWebSearch;
  late ContextWindowMode contextMode;

  /// Stored wire-protocol selection (`WireProtocol.id` string), null = auto.
  /// Kept verbatim while editing — a stale value is *shown* as stale but not
  /// touched until the user saves, at which point it is silently cleared
  /// (never mutate what the user hasn't opened).
  String? wireProtocol;

  /// The selection each protocol surface had when the kind moved off it, for
  /// this opening of the dialog only. See [_selectKind].
  final Map<Surface, String?> _pinBySurface = {};

  /// Whether a field has been typed into, so an empty new form does not open
  /// covered in error strokes.
  bool _idTouched = false;
  bool _contextTouched = false;

  /// The kinds offered, in order. Colours live in [modelTagAccent] only.
  static const List<String> _kinds = ['chat', 'image', 'video', 'multimodal'];

  // D1c 「尺寸」.
  static const double _dialogWidth = 920;
  static const double _addDialogWidth = 520;
  static const double _columnGap = 32;
  static const double _sectionGap = 14;
  static const double _fieldGap = AppSpace.s10;
  static const double _phoneBarHeight = 56;

  /// The narrowest a column may be before the dialog folds to one. A layout
  /// form decision, measured against the width the dialog actually got.
  static const double _minColumnWidth = 320;

  /// The reasoning-effort ladder, in the order it is offered. `''` is the
  /// default rung — "send no field at all" — spelled that way because a
  /// nullable selection cannot tell "picked default" from "nothing picked".
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

    channelId = model?.channelId ??
        widget.preChannelId ??
        (widget.appState.allChannels.isNotEmpty ? widget.appState.allChannels.first.id : null);
    tag = model?.tag ?? 'chat';
    feeGroupId = model?.feeGroupId;
    supportsStream = model?.supportsStream ?? true;
    supportsStandard = model?.supportsStandard ?? true;
    forceViewAllImages = model?.forceViewAllImages ?? false;
    // Legacy rows carry only the boolean; show its effort equivalent so what
    // the chips display is what the request layer will actually do.
    reasoningEffort = model?.reasoningEffort ?? ((model?.enableThinking ?? false) ? 'medium' : null);
    enableWebSearch = model?.enableWebSearch ?? false;
    wireProtocol = model?.wireProtocol;

    // Context window: null = not set, 0 = unlimited, >0 = token limit. A new
    // model starts unset — this number budgets the Prompt Assistant, and a
    // default nobody chose would silently pass for a real answer.
    final cw = model?.contextWindow;
    contextMode = ContextBudget.modeOf(cw);
    contextCtrl = TextEditingController(text: cw != null && cw > 0 ? '$cw' : '');
  }

  @override
  void dispose() {
    idCtrl.dispose();
    nameCtrl.dispose();
    contextCtrl.dispose();
    super.dispose();
  }

  int? get _contextTokens => int.tryParse(contextCtrl.text.trim());

  /// Specify needs a positive whole number; blank or zero blocks saving.
  bool get _contextValid =>
      contextMode != ContextWindowMode.specified || (_contextTokens ?? 0) > 0;

  /// The ID is the only required field — a blank name saves as the ID.
  bool get _canSave => channelId != null && idCtrl.text.trim().isNotEmpty && _contextValid;

  @override
  Widget build(BuildContext context) {
    final phone = Responsive.isMobile(context);
    if (widget.model == null) return _buildAddDialog(context, phone: phone);
    return phone ? _buildPhonePage(context) : _buildEditDialog(context);
  }

  // --- The three forms ----------------------------------------------------

  /// `1a`: the 920 dialog.
  Widget _buildEditDialog(BuildContext context) {
    return AppDialog(
      maxWidth: _dialogWidth,
      maxHeight: 880,
      scrollable: true,
      dividedHeading: true,
      titleWidget: _editHeading(context),
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.s22, vertical: 20),
      content: ModelEditFieldScope(
        metrics: ModelEditMetrics.desktop,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final twoColumns = constraints.maxWidth >= _minColumnWidth * 2 + _columnGap;
            return twoColumns ? _twoColumns(context) : _singleColumn(context, pairFields: true);
          },
        ),
      ),
      actionsOverride: _editFooter(context),
    );
  }

  /// `1e`: the phone page. The bar is the screen's one glass layer; the form
  /// scrolls under it.
  Widget _buildPhonePage(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final insets = MediaQuery.paddingOf(context);

    return Dialog.fullscreen(
      backgroundColor: scheme.surfaceContainerLow,
      child: ModelEditFieldScope(
        metrics: ModelEditMetrics.phoneForm,
        child: Builder(
          builder: (context) => Stack(
            children: [
              Positioned.fill(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    12,
                    insets.top + _phoneBarHeight + _sectionGap,
                    12,
                    insets.bottom + _sectionGap,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _singleColumn(context, pairFields: false),
                      const SizedBox(height: _sectionGap),
                      AppButton(
                        label: widget.l10n.deleteModel,
                        icon: Icons.delete_outline,
                        variant: AppButtonVariant.destructiveText,
                        onPressed: _confirmDelete,
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(top: 0, left: 0, right: 0, child: _phoneBar(context)),
            ],
          ),
        ),
      ),
    );
  }

  /// `1e` right: the 520 add dialog. Channel is asked only when the caller
  /// did not open it from one.
  Widget _buildAddDialog(BuildContext context, {required bool phone}) {
    final l10n = widget.l10n;

    return AppDialog(
      maxWidth: _addDialogWidth,
      maxHeight: 640,
      scrollable: true,
      icon: Icons.add,
      title: l10n.addModel,
      subtitle: l10n.addModelSubtitle,
      content: ModelEditFieldScope(
        metrics: phone ? ModelEditMetrics.phoneDialog : ModelEditMetrics.desktop,
        child: Builder(builder: (context) {
          final size = _fieldSize(context);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _idField(size, autofocus: true, helper: l10n.addModelIdHelper),
              const SizedBox(height: _fieldGap),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _nameField(size)),
                  const SizedBox(width: _fieldGap),
                  Expanded(
                    child: AppLabelledField(
                      label: l10n.type,
                      size: size,
                      child: _kindMenuField(context),
                    ),
                  ),
                ],
              ),
              if (widget.preChannelId == null) ...[
                const SizedBox(height: _fieldGap),
                _channelField(size),
              ],
              const SizedBox(height: _sectionGap),
              // Everything else starts on Auto or its default; say so, so the
              // missing controls read as deferred rather than absent.
              ModelEditNotice(tone: ModelEditTone.info, text: l10n.addModelDefaultsNote),
            ],
          );
        }),
      ),
      actions: [
        AppButton(
          label: l10n.cancel,
          variant: AppButtonVariant.text,
          onPressed: () => Navigator.pop(context),
        ),
        AppButton(label: l10n.add, onPressed: _canSave ? _save : null),
      ],
    );
  }

  // --- Chrome -------------------------------------------------------------

  /// The ID and the channel it is reached through, as the heading's second
  /// line.
  String get _headingSubtitle {
    final channel = _selectedChannel;
    return [idCtrl.text.trim(), channel?.displayName ?? '']
        .where((s) => s.isNotEmpty)
        .join(' · ');
  }

  /// `1a`: the kind's plate, the title, the mono subtitle, close.
  Widget _editHeading(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final kindColor = modelTagAccent(tag);
    final subtitle = _headingSubtitle;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: AppSize.touch,
          height: AppSize.touch,
          decoration: BoxDecoration(
            color: kindColor.withValues(alpha: AppAlpha.tint),
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          child: Icon(modelKindIcon(tag), size: 24, color: kindColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.l10n.editModel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleLarge,
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelSmall?.mono.copyWith(
                      fontWeight: FontWeight.w400,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        IconButton(
          icon: const Icon(Icons.close, size: AppSize.iconMd),
          tooltip: widget.l10n.close,
          onPressed: () => Navigator.pop(context),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(
            width: AppSize.iconButton,
            height: AppSize.iconButton,
          ),
          style: IconButton.styleFrom(
            foregroundColor: scheme.onSurfaceVariant,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.control),
              side: BorderSide(color: scheme.outlineVariant),
            ),
          ),
        ),
      ],
    );
  }

  /// `1a`: delete on the left in the error ink; cancel and save on the right.
  Widget _editFooter(BuildContext context) {
    final l10n = widget.l10n;
    return Row(
      children: [
        AppButton(
          label: l10n.deleteModel,
          icon: Icons.delete_outline,
          variant: AppButtonVariant.destructiveText,
          onPressed: _confirmDelete,
        ),
        const Spacer(),
        AppButton(
          label: l10n.cancel,
          variant: AppButtonVariant.text,
          onPressed: () => Navigator.pop(context),
        ),
        const SizedBox(width: AppSpace.s6),
        AppButton(label: l10n.save, onPressed: _canSave ? _save : null),
      ],
    );
  }

  /// `1e`: back, title over the mono ID, and Save as tinted glass.
  Widget _phoneBar(BuildContext context) {
    final l10n = widget.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final top = MediaQuery.paddingOf(context).top;
    final enabled = _canSave;

    return AppGlass(
      grade: GlassGrade.bar,
      edges: GlassEdges.bottom,
      shadow: false,
      child: Padding(
        padding: EdgeInsets.only(top: top),
        child: SizedBox(
          height: _phoneBarHeight,
          child: Builder(builder: (context) {
            final ink = GlassInk.maybeOf(context)?.ink ?? scheme.onSurface;
            return Padding(
              padding: const EdgeInsetsDirectional.only(start: AppSpace.s6, end: 12),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    color: ink,
                    tooltip: l10n.back,
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: AppSpace.s4),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.editModel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleLarge?.copyWith(color: ink),
                        ),
                        Text(
                          idCtrl.text.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.labelSmall?.mono.copyWith(
                            fontWeight: FontWeight.w400,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Semantics(
                    button: true,
                    enabled: enabled,
                    label: l10n.save,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: enabled ? _save : null,
                      child: AppTintedGlass(
                        enabled: enabled,
                        child: SizedBox(
                          height: AppSize.control,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: Center(
                              child: Text(
                                l10n.save,
                                style: textTheme.labelLarge?.metricsOnly.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: enabled ? scheme.onPrimary : scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }

  // --- Layouts ------------------------------------------------------------

  Widget _twoColumns(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _stack([
            _identitySection(context, pairFields: true),
            _capabilitiesSection(context),
            _previewSection(context),
          ]),
        ),
        const SizedBox(width: _columnGap),
        Expanded(
          child: _stack([
            // The protocol is the cause of what follows it, so it leads the
            // column. Absent entirely (no placeholder height) when there is
            // nothing to choose and nothing to explain.
            if (_showProtocolSection) _protocolSection(context),
            _contextSection(context),
            _agentSection(context),
            _reasoningSection(context),
            if (_isAnthropicChannel) _providerSection(context),
          ]),
        ),
      ],
    );
  }

  Widget _singleColumn(BuildContext context, {required bool pairFields}) {
    return _stack([
      _identitySection(context, pairFields: pairFields),
      if (_showProtocolSection) _protocolSection(context),
      _capabilitiesSection(context),
      _contextSection(context),
      _agentSection(context),
      _reasoningSection(context),
      if (_isAnthropicChannel) _providerSection(context),
      _previewSection(context),
    ]);
  }

  Widget _stack(List<Widget> sections) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < sections.length; i++) ...[
            if (i > 0) const SizedBox(height: _sectionGap),
            sections[i],
          ],
        ],
      );

  AppFieldSize _fieldSize(BuildContext context) =>
      ModelEditMetrics.of(context).phone ? AppFieldSize.large : AppFieldSize.regular;

  Widget _caption(String text, {AppSectionTone tone = AppSectionTone.accent}) =>
      AppSectionLabel(text, padding: EdgeInsets.zero, tone: tone);

  // --- Identity -----------------------------------------------------------

  Widget _identitySection(BuildContext context, {required bool pairFields}) {
    final l10n = widget.l10n;
    final size = _fieldSize(context);
    final name = _nameField(size);
    final channel = _channelField(size);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _caption(l10n.basicInfo),
        const SizedBox(height: AppSpace.s6),
        _idField(size),
        const SizedBox(height: _fieldGap),
        if (pairFields)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: name),
              const SizedBox(width: _fieldGap),
              Expanded(child: channel),
            ],
          )
        else ...[
          name,
          const SizedBox(height: _fieldGap),
          channel,
        ],
        const SizedBox(height: _fieldGap),
        AppLabelledField(
          label: l10n.type,
          size: size,
          child: ModelEditChoiceGrid<String>(
            choices: [
              for (final k in _kinds)
                ModelEditChoice(
                  value: k,
                  label: modelKindLabel(l10n, k),
                  dotColor: modelTagAccent(k),
                ),
            ],
            value: tag,
            onChanged: _selectKind,
          ),
        ),
        const SizedBox(height: _fieldGap),
        _feeGroupField(size),
      ],
    );
  }

  /// The ID field. Once typed into and emptied it carries the save-blocking
  /// note; until then, [helper] (the add dialog's) says the same thing
  /// quietly.
  Widget _idField(AppFieldSize size, {bool autofocus = false, String? helper}) {
    final l10n = widget.l10n;
    final missing = _idTouched && idCtrl.text.trim().isEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppLabelledField(
          label: l10n.modelIdLabel,
          size: size,
          child: ModelEditTextField(
            controller: idCtrl,
            icon: Icons.tag,
            // Mono: an identifier the wire sees verbatim.
            mono: true,
            autofocus: autofocus,
            hint: 'e.g. gpt-4, gemini-1.5-pro',
            error: missing,
            onChanged: (_) => setState(() => _idTouched = true),
          ),
        ),
        if (missing)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.s6),
            child: ModelEditValidationNote(
              title: l10n.modelIdRequiredTitle,
              description: l10n.modelIdRequiredDesc,
            ),
          )
        else if (helper != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.s4),
            child: ModelEditHelperText(helper),
          ),
      ],
    );
  }

  Widget _nameField(AppFieldSize size) {
    return AppLabelledField(
      label: widget.l10n.displayName,
      size: size,
      child: ModelEditTextField(
        controller: nameCtrl,
        icon: Icons.badge_outlined,
        // Optional: a blank name saves as the ID.
        hint: widget.l10n.modelNameOptionalHint,
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _channelField(AppFieldSize size) {
    final l10n = widget.l10n;
    final appState = widget.appState;
    final channel = _selectedChannel;

    return AppLabelledField(
      label: l10n.channel,
      size: size,
      // The channel's tag colour as a dot beside its name (`1a`), in the
      // picker every other channel choice in the app uses.
      child: SearchablePickerField<int>(
        selected: channel == null ? null : channelPickerOption(channel),
        optionsBuilder: () => appState.allChannels.map(channelPickerOption).toList(),
        onChanged: (v) => setState(() => channelId = v),
        hint: l10n.selectAChannel,
        searchHint: l10n.searchChannels,
        dialogIcon: Icons.hub_outlined,
        enabled: appState.allChannels.isNotEmpty,
        badgeStyle: PickerBadge.dot,
        size: size,
      ),
    );
  }

  /// The add dialog's kind select: the dot, the kind's name.
  Widget _kindMenuField(BuildContext context) {
    final l10n = widget.l10n;
    Widget dot(String kind) => Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: modelTagAccent(kind), shape: BoxShape.circle),
        );

    return ModelEditMenuField<String>(
      leading: dot(tag),
      selected: tag,
      onSelected: _selectKind,
      entries: [
        for (final k in _kinds)
          ModelEditMenuEntry(value: k, label: modelKindLabel(l10n, k), leading: dot(k)),
      ],
      child: Text(
        modelKindLabel(l10n, tag),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _feeGroupField(AppFieldSize size) {
    final l10n = widget.l10n;
    return AppLabelledField(
      label: l10n.feeGroup,
      size: size,
      child: AppDropdown<int?>(
        value: feeGroupId,
        items: [
          // A real answer — no group — drawn as the absence it is.
          AppDropdownItem(value: null, label: l10n.noFeeGroup, muted: true),
          for (final g in widget.appState.allPricingGroups) AppDropdownItem(value: g.id!, label: g.name),
        ],
        onChanged: (v) => setState(() => feeGroupId = v),
        prefixIcon: Icons.payments_outlined,
        size: size,
      ),
    );
  }

  // --- Capabilities and preview --------------------------------------------

  Widget _capabilitiesSection(BuildContext context) {
    final l10n = widget.l10n;
    final ignoredBy = _streamIgnoredBy;
    final asyncPinned = _asyncImagePinned;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _caption(l10n.capabilities),
        const SizedBox(height: AppSpace.s6),
        ModelEditCard(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10, vertical: AppSpace.s4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // With a non-streaming route pinned the toggle is inert: the
              // value is preserved, not rewritten — switch back to auto and it
              // comes back untouched. The notice below says which route.
              ModelEditToggleRow(
                title: l10n.supportsStreaming,
                tooltip: l10n.supportsStreamingDesc,
                value: supportsStream,
                dimmed: ignoredBy != null,
                onChanged: ignoredBy != null ? null : (v) => setState(() => supportsStream = v),
              ),
              const Divider(height: 1),
              ModelEditToggleRow(
                title: l10n.supportsStandardRequest,
                tooltip: l10n.supportsStandardRequestDesc,
                value: supportsStandard,
                onChanged: (v) => setState(() => supportsStandard = v),
              ),
            ],
          ),
        ),
        AnimatedSize(
          duration: AppMotion.durationOf(context, AppMotion.reveal),
          curve: AppMotion.enter,
          alignment: Alignment.topCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // `1d`: a statement of fact, not an error.
              if (ignoredBy != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: ModelEditNotice(
                    tone: ModelEditTone.info,
                    text: l10n.protocolStreamIgnored(wireProtocolLabel(l10n, ignoredBy)),
                  ),
                ),
              if (asyncPinned)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: ModelEditNotice(tone: ModelEditTone.info, text: l10n.protocolAsyncQueueNote),
                ),
              const SizedBox(width: double.infinity),
            ],
          ),
        ),
      ],
    );
  }

  Widget _previewSection(BuildContext context) {
    final l10n = widget.l10n;
    final feeGroup = widget.appState.allPricingGroups
        .cast<PricingGroup?>()
        .firstWhere((g) => g?.id == feeGroupId, orElse: () => null);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _caption(l10n.cardPreview),
        const SizedBox(height: AppSpace.s6),
        ModelEditCardPreview(
          model: _draftModel,
          channel: _selectedChannel,
          feeGroup: feeGroup,
        ),
      ],
    );
  }

  /// The model as it would be saved right now, for the card preview. Carries
  /// the raw stored selection so the card can mark a stale one itself, and
  /// no context window while Specify holds nothing savable.
  LLMModel get _draftModel {
    final id = idCtrl.text.trim();
    final name = nameCtrl.text.trim();
    return LLMModel(
      id: widget.model?.id,
      modelId: id,
      modelName: name.isEmpty ? id : name,
      tag: tag,
      supportsStream: supportsStream,
      supportsStandard: supportsStandard,
      channelId: channelId,
      feeGroupId: feeGroupId,
      contextWindow: _contextValid ? ContextBudget.store(contextMode, _contextTokens ?? 0) : null,
      forceViewAllImages: forceViewAllImages,
      enableThinking: reasoningEffort != null && reasoningEffort != 'off',
      reasoningEffort: reasoningEffort,
      enableWebSearch: enableWebSearch,
      wireProtocol: wireProtocol,
    );
  }

  // --- Behaviour ------------------------------------------------------------

  Widget _contextSection(BuildContext context) {
    final l10n = widget.l10n;
    final theme = Theme.of(context);
    final tokens = _contextTokens;
    final invalid = _contextTouched && !_contextValid;

    final description = switch (contextMode) {
      // An image or video model has no conversation to budget, so "unset" is
      // not a guess there but the right answer.
      ContextWindowMode.unset => switch (tag) {
          'image' => l10n.contextImageUnsetDesc,
          'video' => l10n.contextVideoUnsetDesc,
          _ => l10n.contextUnsetDesc,
        },
      ContextWindowMode.specified => l10n.contextWindowHint,
      ContextWindowMode.unlimited => l10n.contextUnlimitedDesc,
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _caption(l10n.contextWindow),
        const SizedBox(height: AppSpace.s6),
        ModelEditChoiceGrid<ContextWindowMode>(
          choices: [
            ModelEditChoice(value: ContextWindowMode.unset, label: l10n.contextUnset),
            ModelEditChoice(value: ContextWindowMode.specified, label: l10n.contextSpecify),
            ModelEditChoice(value: ContextWindowMode.unlimited, label: l10n.contextUnlimited),
          ],
          value: contextMode,
          onChanged: (v) => setState(() => contextMode = v),
        ),
        AnimatedSize(
          duration: AppMotion.durationOf(context, AppMotion.reveal),
          curve: AppMotion.enter,
          alignment: Alignment.topCenter,
          child: contextMode != ContextWindowMode.specified
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: _fieldGap),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppLabelledField(
                        label: l10n.contextMax,
                        size: _fieldSize(context),
                        child: Row(
                          children: [
                            Expanded(
                              child: ModelEditTextField(
                                controller: contextCtrl,
                                icon: Icons.memory_outlined,
                                mono: true,
                                hint: '${ContextBudget.defaultWindowTokens}',
                                keyboardType: TextInputType.number,
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                error: invalid,
                                onChanged: (_) => setState(() => _contextTouched = true),
                              ),
                            ),
                            const SizedBox(width: _fieldGap),
                            Text(
                              l10n.contextTokens(
                                  tokens != null && tokens > 0 ? formatGroupedTokens(tokens) : '—'),
                              style: theme.textTheme.bodySmall?.mono
                                  .copyWith(color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      // Shown whenever Specify holds nothing savable — the
                      // user chose Specify, and this is why Save is off. The
                      // stroke waits for typing.
                      if (!_contextValid)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpace.s6),
                          child: ModelEditValidationNote(title: l10n.contextSpecifyInvalid),
                        ),
                    ],
                  ),
                ),
        ),
        const SizedBox(height: AppSpace.s6),
        ModelEditHelperText(description),
      ],
    );
  }

  Widget _agentSection(BuildContext context) {
    final l10n = widget.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _caption(l10n.agentBehavior),
        const SizedBox(height: AppSpace.s6),
        ModelEditCard(
          child: ModelEditToggleRow(
            title: l10n.forceViewAllImages,
            description: l10n.forceViewAllImagesDesc,
            emphasized: true,
            value: forceViewAllImages,
            onChanged: (v) => setState(() => forceViewAllImages = v),
          ),
        ),
      ],
    );
  }

  /// Always present. Greyed but kept — value included — where the request
  /// would not carry it, so switching the kind back lights it up again.
  Widget _reasoningSection(BuildContext context) {
    final l10n = widget.l10n;
    final supported = _reasoningSupported;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _caption(
          l10n.reasoningEffort,
          tone: supported ? AppSectionTone.accent : AppSectionTone.neutral,
        ),
        const SizedBox(height: AppSpace.s6),
        ModelEditPillChips<String>(
          choices: [
            for (final (value, label) in _effortOptions) ModelEditChoice(value: value, label: label),
          ],
          value: reasoningEffort ?? '',
          enabled: supported,
          onChanged: (v) => setState(() => reasoningEffort = v.isEmpty ? null : v),
        ),
        const SizedBox(height: AppSpace.s6),
        ModelEditHelperText(
          supported ? l10n.reasoningEffortDesc : l10n.reasoningEffortUnsupported,
          muted: !supported,
        ),
      ],
    );
  }

  /// `1d`'s provider card: extended thinking and host web search, both
  /// Anthropic-format only.
  ///
  /// Extended thinking is a view of [reasoningEffort], not a column of its
  /// own: on this wire Off and Default both send nothing, so "on" is any
  /// effort rung, and turning it on picks Medium.
  Widget _providerSection(BuildContext context) {
    final l10n = widget.l10n;
    final supported = _reasoningSupported;
    final thinkingOn = reasoningEffort != null && reasoningEffort != 'off';

    return ModelEditCard(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10, vertical: AppSpace.s4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.s6),
            child: ModelEditToggleRow(
              title: l10n.enableThinking,
              description: l10n.enableThinkingDesc,
              value: thinkingOn,
              dimmed: !supported,
              onChanged: !supported
                  ? null
                  : (v) => setState(() => reasoningEffort = v ? (thinkingOn ? reasoningEffort : 'medium') : null),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.s6),
            child: ModelEditToggleRow(
              title: l10n.enableWebSearch,
              description: l10n.enableWebSearchDesc,
              value: enableWebSearch,
              onChanged: (v) => setState(() => enableWebSearch = v),
            ),
          ),
        ],
      ),
    );
  }

  // --- Wire protocol --------------------------------------------------------

  /// The protocol menu for the current channel, model id and kind, or null
  /// when channel or id is missing. The kind is read because it decides the
  /// surface: the same id tagged image offers the image menu.
  ProtocolMenu? get _menu {
    final channel = _selectedChannel;
    final id = idCtrl.text.trim();
    if (channel == null || id.isEmpty) return null;
    return LLMDispatcher.protocolMenu(channel.type, id, tag: tag);
  }

  /// The menu's options, or empty.
  List<WireProtocol> get _protocolMenu => _menu?.options ?? const [];

  /// The stored selection when it is still valid on the current menu; null
  /// for auto *and* for a stale value (which routes as auto).
  WireProtocol? get _activePin {
    final parsed = WireProtocol.tryParse(wireProtocol);
    if (parsed == null) return null;
    return _protocolMenu.contains(parsed) ? parsed : null;
  }

  /// Whether the stored selection exists but no longer applies.
  bool get _pinIsStale => wireProtocol != null && wireProtocol!.isNotEmpty && _activePin == null;

  /// The image route is the async task flow — drives the queue note and the
  /// card's Async task chip.
  bool get _asyncImagePinned => _activePin == WireProtocol.dashscopeImagesAsync;

  /// Which shape the protocol section takes — see [protocolSectionForm].
  ProtocolSectionForm get _protocolForm => protocolSectionForm(_menu, pinIsStale: _pinIsStale);

  /// Whether the protocol section renders at all.
  bool get _showProtocolSection => _protocolForm != ProtocolSectionForm.none;

  /// The pinned protocol when its route has no streaming form, else null.
  /// Asked of the dispatcher with the form as it stands, so the editor cannot
  /// disagree with the router about which protocols stream. Auto never dims
  /// the toggle: it is only ignored because of something the user chose.
  WireProtocol? get _streamIgnoredBy {
    final pin = _activePin;
    final channel = _selectedChannel;
    if (pin == null || channel == null) return null;
    final singleShot = LLMDispatcher().streamIsSingleShot(LLMModelConfig(
      modelId: idCtrl.text.trim(),
      channelType: channel.type,
      endpoint: channel.endpoint,
      apiKey: channel.apiKey,
      tag: tag,
      wireProtocol: pin.id,
    ));
    return singleShot ? pin : null;
  }

  /// Whether a reasoning level would reach the request: the channel's chat
  /// wire consumes it (the dispatcher's answer, not a copy), and the kind
  /// sends the model down that chat wire at all.
  bool get _reasoningSupported {
    final family = _channelFamily;
    if (family == null || !LLMDispatcher.chatConsumesReasoningEffort(family)) return false;
    return LLMDispatcher.surfaceForModel(idCtrl.text.trim(), tag: tag) == Surface.chat;
  }

  /// Moves the kind.
  ///
  /// A kind on another surface swaps the protocol menu, so the selection made
  /// for the old surface is set aside and the new surface's comes back — auto
  /// if it never had one. Remembered per *surface*, not per kind: chat and
  /// multimodal share one menu, and swapping between them must not throw
  /// away a choice that is still valid. Lives only as long as this dialog;
  /// saving writes the current surface's choice.
  void _selectKind(String value) {
    if (value == tag) return;
    final id = idCtrl.text.trim();
    final from = LLMDispatcher.surfaceForModel(id, tag: tag);
    final to = LLMDispatcher.surfaceForModel(id, tag: value);
    setState(() {
      if (from != to) {
        _pinBySurface[from] = wireProtocol;
        wireProtocol = _pinBySurface[to];
      }
      tag = value;
    });
  }

  Widget _protocolSection(BuildContext context) {
    final l10n = widget.l10n;
    final menu = _menu;
    final family = _channelFamily;
    final channel = _selectedChannel;
    if (menu == null || family == null || channel == null) {
      return const SizedBox.shrink();
    }
    final id = idCtrl.text.trim();
    final name = nameCtrl.text.trim();

    return ModelProtocolSection(
      header: _caption('${l10n.requestMethod} · ${l10n.interfaceProtocol}'),
      menu: menu,
      form: _protocolForm,
      channelFamily: family,
      kind: tag,
      modelName: name.isEmpty ? id : name,
      stored: wireProtocol,
      activePin: _activePin,
      pinIsStale: _pinIsStale,
      // As the model will be served once saved: with the choice on screen,
      // not the one in the database.
      paramsCapabilities: LLMDispatcher.descriptorFor(
        channelType: channel.type,
        modelId: id,
        tag: tag,
        wireProtocol: _activePin?.id,
      ).capabilities,
      onChanged: (v) => setState(() => wireProtocol = v),
    );
  }

  // --- Channel lookups ------------------------------------------------------

  /// The channel the form currently points at, or null when none is picked.
  LLMChannel? get _selectedChannel => widget.appState.allChannels
      .cast<LLMChannel?>()
      .firstWhere((c) => c?.id == channelId, orElse: () => null);

  /// The selected channel's protocol family, or null when no channel is
  /// picked. Read-only Layer 2 consumption.
  ProtocolFamily? get _channelFamily {
    final channel = _selectedChannel;
    return channel == null ? null : Vendors.byId(channel.type).family;
  }

  /// Host web search and extended thinking only exist on the ④ wire.
  bool get _isAnthropicChannel => _channelFamily == ProtocolFamily.anthropic;

  // --- Persistence ----------------------------------------------------------

  Future<void> _confirmDelete() async {
    final model = widget.model;
    if (model?.id == null) return;
    final l10n = widget.l10n;

    final confirmed = await AppDialog.show<bool>(
      context,
      icon: Icons.delete_outline,
      iconColor: Theme.of(context).colorScheme.error,
      title: l10n.deleteModelConfirmTitle,
      content: Text(l10n.deleteModelConfirmMessage(model!.modelName)),
      actions: [
        AppButton(
          label: l10n.cancel,
          variant: AppButtonVariant.text,
          onPressed: () => Navigator.pop(context, false),
        ),
        AppButton(
          label: l10n.delete,
          variant: AppButtonVariant.destructive,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    );
    if (confirmed != true || !mounted) return;

    await widget.appState.deleteModel(model.id!);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _save() async {
    if (!_canSave) return;
    final id = idCtrl.text.trim();
    final name = nameCtrl.text.trim();

    final data = {
      'model_id': id,
      // A blank name is the ID.
      'model_name': name.isEmpty ? id : name,
      'tag': tag,
      'is_paid': 1,
      'supports_stream': supportsStream ? 1 : 0,
      'supports_standard': supportsStandard ? 1 : 0,
      'force_view_all_images': forceViewAllImages ? 1 : 0,
      // The legacy flag is kept in sync so a backup restored into an older
      // build (which only reads the boolean) preserves thinking behavior.
      'enable_thinking': (reasoningEffort != null && reasoningEffort != 'off') ? 1 : 0,
      'reasoning_effort': reasoningEffort,
      'enable_web_search': enableWebSearch ? 1 : 0,
      // Auto stores null; a stale value is silently cleared *here* — on the
      // user's own save, never behind their back.
      'wire_protocol': _activePin?.id,
      'fee_group_id': feeGroupId,
      'channel_id': channelId,
      'context_window': ContextBudget.store(contextMode, _contextTokens ?? 0),
    };

    if (widget.model == null) {
      await widget.appState.addModel(data);
    } else {
      await widget.appState.updateModel(widget.model!.id!, data);
    }

    if (mounted) Navigator.pop(context);
  }
}
