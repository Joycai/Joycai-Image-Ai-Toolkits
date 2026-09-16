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
import '../../services/catalogue/context_window_scale.dart';
import '../../services/llm/context_budget.dart';
import '../../services/llm/llm_dispatcher.dart';
import '../../services/llm/llm_types.dart';
import '../../services/llm/vendors/vendors.dart';
import '../../services/catalogue/model_id_uniqueness.dart';
import '../../state/app_state.dart';
import '../ui/app_button.dart';
import '../ui/app_dialog.dart';
import '../ui/app_dropdown.dart';
import '../ui/app_field_size.dart';
import '../ui/app_labelled_field.dart';
import '../ui/app_section_label.dart';
import '../glass/app_glass.dart';
import '../ui/searchable_picker.dart';
import 'context_window_slider.dart';
import 'model_edit_card_preview.dart';
import 'fee_group_summary.dart';
import 'model_edit_controls.dart';
import 'model_picker_options.dart';
import 'model_protocol_section.dart';
import 'protocol_section_form.dart';
import 'wire_protocol_labels.dart';

part 'model_edit/model_edit_capabilities.dart';
part 'model_edit/model_edit_context.dart';
part 'model_edit/model_edit_identity.dart';
part 'model_edit/model_edit_layouts.dart';
part 'model_edit/model_edit_protocol.dart';

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

  /// Focus on the Specify field, watched so a `128k` typed there becomes
  /// `131072` once the user moves on.
  final FocusNode _contextFocus = FocusNode();

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

  /// Whether the fee group was picked by hand. Until it is, a new model's
  /// group follows its channel's default as the channel changes.
  bool _feeGroupTouched = false;
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

  /// [setState] for the builders in the parts. They are extensions on this
  /// class, and an extension may not call a protected member itself.
  void _rebuild(VoidCallback fn) => setState(fn);

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
    // A new model starts in its channel's default group (`D1b · 1e`); an
    // existing one keeps what it has.
    feeGroupId = model == null ? widget.appState.defaultFeeGroupFor(channelId) : model.feeGroupId;
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
    _contextFocus.addListener(_normaliseContextOnBlur);
  }

  void _normaliseContextOnBlur() {
    if (_contextFocus.hasFocus) return;
    final tokens = _contextTokens;
    if (tokens != null && contextCtrl.text != '$tokens') {
      setState(() => contextCtrl.text = '$tokens');
    }
  }

  @override
  void dispose() {
    idCtrl.dispose();
    nameCtrl.dispose();
    contextCtrl.dispose();
    _contextFocus.dispose();
    super.dispose();
  }

  /// The Specify figure — digits, or the `128k` / `1m` shorthand the labels use.
  int? get _contextTokens => ContextWindowScale.parse(contextCtrl.text);

  /// Specify needs a positive whole number; blank or zero blocks saving.
  bool get _contextValid =>
      contextMode != ContextWindowMode.specified || (_contextTokens ?? 0) > 0;

  /// The ID is the only required field — a blank name saves as the ID.
  bool get _canSave => channelId != null && idCtrl.text.trim().isNotEmpty && !_idTaken && _contextValid;

  /// The ID is already on the selected channel, under another model.
  bool get _idTaken => isModelIdTaken(
        widget.appState.allModels,
        channelId: channelId,
        modelId: idCtrl.text,
        exceptId: widget.model?.id,
      );

  @override
  Widget build(BuildContext context) {
    final phone = Responsive.isMobile(context);
    if (widget.model == null) return _buildAddDialog(context, phone: phone);
    return phone ? _buildPhonePage(context) : _buildEditDialog(context);
  }

  // --- The three forms ----------------------------------------------------

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
