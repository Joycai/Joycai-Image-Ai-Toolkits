import 'package:flutter/material.dart';

import '../../../core/app_semantic_colors.dart';
import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../core/responsive.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/llm_channel.dart';
import '../../../services/llm/channel_probe_service.dart';
import '../../../services/llm/channel_routes.dart';
import '../../../services/llm/llm_dispatcher.dart';
import '../../../services/llm/llm_types.dart';
import '../../../services/llm/vendors/platforms.dart';
import '../../../services/llm/vendors/vendors.dart';
import '../../../state/app_state.dart';
import '../../../widgets/models/app_route_badge.dart';
import '../../../widgets/models/channel_form_sections.dart';
import '../../../widgets/models/channel_provider_presets.dart';
import '../../../widgets/models/channel_provider_row.dart';
import '../../../widgets/models/route_labels.dart';
import '../../../widgets/ui/app_button.dart';
import '../../../widgets/ui/app_dialog.dart';
import 'channel_probe_result_card.dart';

part 'channel_wizard/wizard_chrome.dart';
part 'channel_wizard/wizard_form_steps.dart';
part 'channel_wizard/wizard_preview.dart';
part 'channel_wizard/wizard_provider_steps.dart';

/// The steps the wizard can show. [variant] exists only for a provider with
/// more than one way in, which is why the rail's length follows the choice
/// made on [provider].
enum _WizardStep { provider, variant, connection, appearance }

/// Adding a channel as a stepped dialog (design `D1b`): a 760 panel with a
/// 200px step rail on the left and the current step's form on the right.
///
/// **Step names over a progress bar.** Someone halfway through wants to know
/// what is left, not how far along a line they are, so the rail names every
/// step and marks each done / current / to do. Its length is the provider's:
/// Google, MiniMax and NewAPI insert a "way in" step between choosing the
/// provider and filling in its endpoint, because that choice decides both the
/// stored type and the address.
///
/// Every rule the one-page layout had survives: switching provider replaces
/// the endpoint, a relay host survives a format switch, the key is optional
/// only for the local runtimes, and nothing is committed until the endpoint
/// and key checks pass — here at the connection step's Next, and again at
/// the final Add, which lands back on that step when they fail.
///
/// On a phone the same steps are a full-screen page with the footer pinned
/// to the bottom.
class ChannelWizardDialog extends StatefulWidget {
  final AppLocalizations l10n;
  final AppState appState;

  const ChannelWizardDialog({super.key, required this.l10n, required this.appState});

  @override
  State<ChannelWizardDialog> createState() => _ChannelWizardDialogState();
}

class _ChannelWizardDialogState extends State<ChannelWizardDialog> {
  int _stepIndex = 0;

  /// The step the body last showed, and which way the wizard went to leave
  /// it: +1 forward, −1 back. The step enum is declared in wizard order, so
  /// its index is the order whether or not the variant step is in the list.
  _WizardStep? _shownStep;

  /// One serial per step change, keying the switcher's child, and the
  /// direction of the move that brought each serial in. A child's slide is
  /// read from these rather than from the step it shows: going A → B → A
  /// quickly leaves the first A still on its way out while the new A comes
  /// in, and the two would otherwise be told apart by nothing.
  int _stepSerial = 0;
  final Map<int, int> _serialDirection = {0: 1};

  /// How far a step body travels as it changes, as a fraction of its width.
  /// A hint of direction, not a page turn.
  static const double _stepShift = 0.05;

  /// [setState] for the builders in the parts. They are extensions on this
  /// class, and an extension may not call a protected member itself.
  void _rebuild(VoidCallback fn) => setState(fn);

  String _selectedProviderId = 'openai-official';

  /// Which of a multi-face preset's [ChannelProviderVariant]s is selected;
  /// null for the presets that have exactly one way in. Reset on every
  /// provider change — a variant id is scoped to its preset.
  String? _variantId;

  final TextEditingController _endpointCtrl = TextEditingController();
  final TextEditingController _apiKeyCtrl = TextEditingController();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _tagCtrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();

  bool _enableDiscovery = true;
  late int _tagColor;

  /// Whether the user picked a tag colour themselves. Until they do, the
  /// colour follows the provider's avatar, so the list preview and the rows
  /// they just chose from agree.
  bool _tagColorChosen = false;

  /// Errors stay hidden until the user tries to move past the connection
  /// step. A required-field message on an untouched form reads as "you did
  /// something wrong" before they have done anything at all.
  bool _submitAttempted = false;

  bool _submitting = false;

  bool _probing = false;
  ChannelProbeResult? _probe;

  ChannelProviderPreset get _preset =>
      kChannelProviderPresets.firstWhere((p) => p.id == _selectedProviderId);

  /// The selected variant, or the preset's first when it has any. A preset
  /// with variants always has one active: the endpoint has to come from
  /// somewhere.
  ChannelProviderVariant? get _variant {
    final preset = _preset;
    if (!_choosesVariant) return null;
    return preset.variants.firstWhere(
      (v) => v.id == _variantId,
      orElse: () => preset.variants.first,
    );
  }

  /// Whether the preset's ways in are a real choice. Variants that are
  /// routes are not: the channel gets every route (`D1f · 4b`), so only
  /// Ark's two addresses — one protocol, two keys — still ask.
  bool get _choosesVariant => _preset.hasVariants && !channelPresetVariantsAreRoutes(_preset);

  List<_WizardStep> get _steps => [
    _WizardStep.provider,
    if (_choosesVariant) _WizardStep.variant,
    _WizardStep.connection,
    _WizardStep.appearance,
  ];

  _WizardStep get _step {
    final steps = _steps;
    return steps[_stepIndex.clamp(0, steps.length - 1)];
  }

  bool get _isLastStep => _stepIndex >= _steps.length - 1;

  @override
  void initState() {
    super.initState();
    _tagColor = channelPresetIdentityColor(_preset).toARGB32();
    _applyPresetEndpoint();
  }

  @override
  void dispose() {
    _endpointCtrl.dispose();
    _apiKeyCtrl.dispose();
    _nameCtrl.dispose();
    _tagCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // --- Form state ------------------------------------------------------------

  /// Load the selected preset's suggested endpoint into the field.
  ///
  /// Called on open and on every provider tap, so the field always shows the
  /// current provider's address — switching presets after editing the URL
  /// replaces it rather than leaving the previous provider's host behind,
  /// which would otherwise ship a channel pointed at the wrong company.
  void _applyPresetEndpoint() {
    _endpointCtrl.text = _variant?.defaultEndpoint ?? _preset.defaultEndpoint ?? '';
  }

  void _selectProvider(String id) {
    setState(() {
      _selectedProviderId = id;
      _variantId = null;
      _applyPresetEndpoint();
      _clearProbe();
      if (!_tagColorChosen) {
        _tagColor = channelPresetIdentityColor(_preset).toARGB32();
      }
    });
  }

  /// A search that found nothing offers the custom group instead.
  void _useCustomProvider() {
    _searchCtrl.clear();
    _selectProvider(channelFallbackCustomPreset().id);
  }

  /// Switching face rewrites the endpoint: a relay host the user typed is
  /// kept — only its version suffix follows the format — while a
  /// preset-supplied host is replaced outright.
  void _selectVariant(String variantId) {
    setState(() {
      _variantId = variantId;
      final variant = _variant;
      if (variant != null && variant.defaultEndpoint != null) {
        _endpointCtrl.text = variant.defaultEndpoint!;
      } else if (variant != null && variant.endpointSuffix.isNotEmpty) {
        _endpointCtrl.text = _stripKnownVersionSuffix(_endpointCtrl.text);
      } else {
        _applyPresetEndpoint();
      }
      _clearProbe();
    });
  }

  /// Drops a trailing `/v1` or `/v1beta` so the newly-picked format can put
  /// its own back on. Without this, switching NewAPI from OpenAI to Gemini
  /// left `/v1` in place and the suffix logic respected it.
  String _stripKnownVersionSuffix(String input) {
    var base = input.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    for (final suffix in const ['/v1beta', '/v1']) {
      if (base.endsWith(suffix)) {
        return base.substring(0, base.length - suffix.length);
      }
    }
    return base;
  }

  /// A probe result describes one endpoint/key pair. Any edit to either makes
  /// the previous verdict stale, and a stale green tick is worse than none —
  /// it is the one thing that would let a broken channel through.
  void _clearProbe() {
    _probe = null;
  }

  bool get _endpointMissing => _endpointCtrl.text.trim().isEmpty;

  /// Whether this provider can be saved without a key. True for the local
  /// runtimes, which have no auth to give: requiring one there left the user
  /// typing a junk character to get past the check.
  bool get _keyOptional => Vendors.byId(_resolvedChannelType()).keyOptional;

  bool get _apiKeyMissing => !_keyOptional && _apiKeyCtrl.text.trim().isEmpty;

  String? _endpointError(AppLocalizations l10n) =>
      _submitAttempted && _endpointMissing ? l10n.endpointRequired : null;

  String? _apiKeyError(AppLocalizations l10n) =>
      _submitAttempted && _apiKeyMissing ? l10n.apiKeyRequired : null;

  /// Normalizes a New API base URL to the correct versioned path. If the user
  /// already typed a full path ending in `/v1` or `/v1beta`, it is respected;
  /// otherwise [suffix] is appended.
  String _resolveNewApiEndpoint(String input, String suffix) {
    var base = input.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    if (base.endsWith('/v1') || base.endsWith('/v1beta')) return base;
    return '$base$suffix';
  }

  String get _endpointSuffix => _variant?.endpointSuffix ?? _preset.endpointSuffix;

  String _resolvedEndpoint() {
    final suffix = _endpointSuffix;
    if (suffix.isNotEmpty) {
      return _resolveNewApiEndpoint(_endpointCtrl.text, suffix);
    }
    var raw = _endpointCtrl.text.trim();
    while (raw.endsWith('/')) {
      raw = raw.substring(0, raw.length - 1);
    }
    return raw;
  }

  String _resolvedChannelType() => _variant?.channelType ?? _preset.channelType;

  /// The routes the channel will be created with — what the connection step
  /// previews and what is stored.
  ChannelRoutes get _plannedRoutes =>
      plannedChannelRoutes(_preset, _resolvedChannelType(), _resolvedEndpoint());

  String _resolvedName() =>
      _nameCtrl.text.trim().isEmpty ? _selectedProviderId : _nameCtrl.text.trim();

  String _resolvedTag() =>
      _tagCtrl.text.trim().isEmpty ? _selectedProviderId.split('-').first : _tagCtrl.text.trim();

  // --- Flow ------------------------------------------------------------------

  void _next() {
    if (_step == _WizardStep.connection) {
      setState(() => _submitAttempted = true);
      if (_endpointMissing || _apiKeyMissing) return;
    }
    if (_isLastStep) {
      _requestSubmit();
      return;
    }
    setState(() => _stepIndex++);
  }

  void _back() {
    if (_stepIndex > 0) setState(() => _stepIndex--);
  }

  /// Validates, shows the preview, and adds on confirm. A failed check lands
  /// on the connection step rather than flagging fields the user cannot see.
  Future<void> _requestSubmit() async {
    setState(() => _submitAttempted = true);
    if (_endpointMissing || _apiKeyMissing) {
      setState(() => _stepIndex = _steps.indexOf(_WizardStep.connection));
      return;
    }
    final confirmed = await _showPreview();
    if (confirmed != true || !mounted) return;
    await _submit();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      final routes = _plannedRoutes;
      await widget.appState.addChannel(
        LLMChannel(
          displayName: _resolvedName(),
          endpoint: routes.primaryAddress,
          apiKey: _apiKeyCtrl.text.trim(),
          type: routes.primaryVendorId,
          routes: routes.encode(),
          enableDiscovery: _enableDiscovery,
          tag: _resolvedTag(),
          tagColor: _tagColor,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
    if (mounted) Navigator.pop(context);
  }

  /// Probes with the *form's current values* — the whole point is testing
  /// what is about to be saved, not what is already stored.
  Future<void> _runProbe() async {
    setState(() {
      _probing = true;
      _clearProbe();
    });
    final result = await ChannelProbeService().probe(
      LLMModelConfig(
        modelId: ChannelProbeService.probeModelId,
        channelType: _resolvedChannelType(),
        endpoint: _resolvedEndpoint(),
        apiKey: _apiKeyCtrl.text.trim(),
      ),
    );
    if (!mounted) return;
    setState(() {
      _probing = false;
      _probe = result;
    });
  }

  // --- Labels ----------------------------------------------------------------

  String _stepName(AppLocalizations l10n, _WizardStep step) => switch (step) {
    _WizardStep.provider => l10n.stepProvider,
    _WizardStep.variant => channelProviderVariantTitle(l10n, _preset.id),
    _WizardStep.connection => l10n.stepConnection,
    _WizardStep.appearance => l10n.tagAndAppearance,
  };

  String _nextLabel(AppLocalizations l10n) {
    if (_isLastStep) return l10n.addChannel;
    // A local runtime's key is optional: moving on with the box empty is
    // skipping it, and the button says so.
    if (_step == _WizardStep.connection && _keyOptional && _apiKeyCtrl.text.trim().isEmpty) {
      return l10n.skip;
    }
    return l10n.next;
  }

  // --- Build -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    if (Responsive.isMobile(context)) return _buildPage(l10n);
    return _buildDialog(l10n);
  }
}
