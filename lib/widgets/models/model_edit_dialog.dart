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
import '../../services/catalogue/output_cap_scale.dart';
import '../../services/catalogue/route_switching.dart';
import '../../services/llm/channel_routes.dart';
import '../../services/llm/context_budget.dart';
import '../../services/llm/llm_dispatcher.dart';
import '../../services/llm/llm_types.dart';
import '../../services/llm/model_routes.dart';
import '../../services/llm/protocols/anthropic_wire.dart' show anthropicDefaultMaxTokens, anthropicMinThinkingBudget;
import '../../services/llm/vendors/platforms.dart';
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
import 'app_route_badge.dart';
import 'context_window_slider.dart';
import 'model_edit_card_preview.dart';
import 'fee_group_summary.dart';
import 'model_edit_controls.dart';
import 'model_picker_options.dart';
import 'model_protocol_section.dart';
import 'protocol_section_form.dart';
import 'route_labels.dart';
import 'wire_protocol_labels.dart';

part 'model_edit/model_edit_capabilities.dart';
part 'model_edit/model_edit_context.dart';
part 'model_edit/model_edit_identity.dart';
part 'model_edit/model_edit_layouts.dart';
part 'model_edit/model_edit_output_cap.dart';
part 'model_edit/model_edit_protocol.dart';
part 'model_edit/model_edit_routes.dart';

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

  /// The output cap's Specify field. Two states only (Auto = no cap sent),
  /// so a bool rather than a mode enum; see `_OutputCapSection`.
  late TextEditingController outputCapCtrl;
  final FocusNode _outputCapFocus = FocusNode();
  late bool outputCapSpecified;
  bool _outputCapTouched = false;

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

  /// The route a chat model rides (`llm_models.active_route`), null to
  /// follow the channel's primary, and the parameters parked under its other
  /// routes (`D1f · 4d`). Switched in the form; written on save.
  String? activeRoute;
  Map<RouteKind, RouteParams> _parked = const {};

  /// A route tapped in the strip that was never set up: its switch preview
  /// is open until confirmed or cancelled.
  RouteKind? _switchTarget;

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
    // A chat model whose route is gone opens on the primary with the
    // primary's own values, its chosen route's values parked under that
    // route (`RouteSwitching.recoverMissingRoute`) — never the gone route's
    // values shown, and then saved, as the primary's.
    final stored = widget.model;
    final storedChannel = stored == null
        ? null
        : widget.appState.allChannels
            .cast<LLMChannel?>()
            .firstWhere((c) => c?.id == stored.channelId, orElse: () => null);
    final model = stored == null || storedChannel == null
        ? stored
        : RouteSwitching.recoverMissingRoute(stored, RoutedChannel.routesOf(storedChannel));
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
    activeRoute = model?.activeRoute;
    _parked = model == null ? const {} : ModelRoutes.parked(model);

    // Context window: null = not set, 0 = unlimited, >0 = token limit. A new
    // model starts unset — this number budgets the Prompt Assistant, and a
    // default nobody chose would silently pass for a real answer.
    final cw = model?.contextWindow;
    contextMode = ContextBudget.modeOf(cw);
    contextCtrl = TextEditingController(text: cw != null && cw > 0 ? '$cw' : '');
    _contextFocus.addListener(_normaliseContextOnBlur);

    // Output cap: null = Auto (nothing sent). A new model starts on Auto for
    // the same reason the window starts unset — a cap nobody chose would be
    // sent as a fact.
    final cap = model?.maxOutputTokens;
    outputCapSpecified = cap != null && cap > 0;
    outputCapCtrl = TextEditingController(text: outputCapSpecified ? '$cap' : '');
    _outputCapFocus.addListener(_normaliseOutputCapOnBlur);
  }

  void _normaliseOutputCapOnBlur() {
    if (_outputCapFocus.hasFocus) return;
    final tokens = _outputCapTokens;
    if (tokens != null && outputCapCtrl.text != '$tokens') {
      setState(() => outputCapCtrl.text = '$tokens');
    }
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
    outputCapCtrl.dispose();
    _outputCapFocus.dispose();
    super.dispose();
  }

  /// The Specify figure — digits, or the `128k` / `1m` shorthand the labels use.
  int? get _contextTokens => ContextWindowScale.parse(contextCtrl.text);

  /// Specify needs a positive whole number; blank or zero blocks saving.
  bool get _contextValid =>
      contextMode != ContextWindowMode.specified || (_contextTokens ?? 0) > 0;

  /// The output cap's Specify figure, in the context field's grammar.
  int? get _outputCapTokens => OutputCapScale.parse(outputCapCtrl.text);

  /// An image or video model has no reply to cap: the section is absent for
  /// those kinds, and so is everything that reads it — a hidden field must
  /// neither block Save nor be stored.
  bool get _hasOutputCap => tag != 'image' && tag != 'video';

  /// Same rule as the window: Specify with nothing savable blocks Save.
  bool get _outputCapValid => !_hasOutputCap || !outputCapSpecified || (_outputCapTokens ?? 0) > 0;

  /// What the row stores: null on Auto (and for a kind without the
  /// section), the figure on Specify.
  int? get _storedOutputCap => _hasOutputCap && outputCapSpecified ? _outputCapTokens : null;

  /// The ID is the only required field — a blank name saves as the ID.
  bool get _canSave =>
      channelId != null && idCtrl.text.trim().isNotEmpty && !_idTaken && _contextValid && _outputCapValid;

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

  /// The protocol family of the vendor serving the model — through its route
  /// for a chat model — or null when no channel is picked. Read-only Layer 2
  /// consumption.
  ProtocolFamily? get _channelFamily {
    final routed = _routed;
    return routed == null ? null : Vendors.byId(routed.channelType).family;
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

    // A chat model saves on its route: the one rule for per-route
    // parameters applied, the route written explicitly (`RouteSwitching`).
    final routes = _routes;
    final saved = routes != null && _usesRoutes
        ? RouteSwitching.normalizedForSave(_draftModel, routes)
        : null;

    final data = LLMModel(
      modelId: id,
      // A blank name is the ID.
      modelName: name.isEmpty ? id : name,
      tag: tag,
      supportsStream: supportsStream,
      supportsStandard: supportsStandard,
      forceViewAllImages: forceViewAllImages,
      // The legacy flag is kept in sync so a backup restored into an older
      // build (which only reads the boolean) preserves thinking behavior.
      enableThinking: saved != null
          ? saved.enableThinking
          : (reasoningEffort != null && reasoningEffort != 'off'),
      reasoningEffort: saved != null ? saved.reasoningEffort : reasoningEffort,
      enableWebSearch: enableWebSearch,
      // Auto stores null; a stale value is silently cleared *here* — on the
      // user's own save, never behind their back.
      wireProtocol: saved != null ? saved.wireProtocol : _activePin?.id,
      activeRoute: saved?.activeRoute,
      routeParams: saved?.routeParams,
      feeGroupId: feeGroupId,
      channelId: channelId,
      contextWindow: ContextBudget.store(contextMode, _contextTokens ?? 0),
      maxOutputTokens: saved != null ? saved.maxOutputTokens : _storedOutputCap,
    );

    if (widget.model == null) {
      await widget.appState.addModel(data);
    } else {
      await widget.appState.updateModel(widget.model!.id!, data);
    }

    if (mounted) Navigator.pop(context);
  }
}
