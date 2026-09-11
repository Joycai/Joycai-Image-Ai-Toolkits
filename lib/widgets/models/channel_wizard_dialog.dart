import 'package:flutter/material.dart';

import '../../core/app_semantic_colors.dart';
import '../../core/app_theme.dart';
import '../../core/design_tokens.dart';
import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../services/llm/channel_probe_service.dart';
import '../../services/llm/llm_types.dart';
import '../../services/llm/vendors/vendors.dart';
import '../../state/app_state.dart';
import '../app_button.dart';
import '../app_dialog.dart';
import 'channel_form_sections.dart';
import 'channel_probe_result_card.dart';
import 'channel_provider_presets.dart';
import 'channel_provider_row.dart';

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

  const ChannelWizardDialog({
    super.key,
    required this.l10n,
    required this.appState,
  });

  @override
  State<ChannelWizardDialog> createState() => _ChannelWizardDialogState();
}

class _ChannelWizardDialogState extends State<ChannelWizardDialog> {
  int _stepIndex = 0;

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
    if (!preset.hasVariants) return null;
    return preset.variants.firstWhere(
      (v) => v.id == _variantId,
      orElse: () => preset.variants.first,
    );
  }

  List<_WizardStep> get _steps => [
        _WizardStep.provider,
        if (_preset.hasVariants) _WizardStep.variant,
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
    _endpointCtrl.text =
        _variant?.defaultEndpoint ?? _preset.defaultEndpoint ?? '';
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

  String get _endpointSuffix =>
      _variant?.endpointSuffix ?? _preset.endpointSuffix;

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

  String _resolvedName() => _nameCtrl.text.trim().isEmpty
      ? _selectedProviderId
      : _nameCtrl.text.trim();

  String _resolvedTag() => _tagCtrl.text.trim().isEmpty
      ? _selectedProviderId.split('-').first
      : _tagCtrl.text.trim();

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
      await widget.appState.addChannel({
        'display_name': _resolvedName(),
        'endpoint': _resolvedEndpoint(),
        'api_key': _apiKeyCtrl.text.trim(),
        'type': _resolvedChannelType(),
        'enable_discovery': _enableDiscovery ? 1 : 0,
        'tag': _resolvedTag(),
        'tag_color': _tagColor,
      });
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
    if (_step == _WizardStep.connection &&
        _keyOptional &&
        _apiKeyCtrl.text.trim().isEmpty) {
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

  Widget _buildDialog(AppLocalizations l10n) {
    // The body claims what the window can spare, between a floor that keeps
    // the provider list scrollable and a ceiling that stops the dialog
    // stretching on a tall display. Heading, footer and the dialog's own
    // vertical inset account for the subtracted band.
    final bodyHeight =
        (MediaQuery.sizeOf(context).height - 230).clamp(320.0, 580.0);

    return AppDialog(
      titleWidget: _buildHeader(l10n),
      maxWidth: 760,
      dividedHeading: true,
      contentPadding: EdgeInsets.zero,
      content: SizedBox(
        height: bodyHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // The rail is 200 and the form needs ~320 before its two-column
            // rows stop being usable; below that the footer's counter still
            // says where the user is.
            final showRail = constraints.maxWidth >= 520;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showRail) SizedBox(width: 200, child: _buildStepRail(l10n)),
                Expanded(child: _buildStepBody(l10n)),
              ],
            );
          },
        ),
      ),
      actionsOverride: _buildFooter(l10n),
    );
  }

  Widget _buildPage(AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final steps = _steps;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(l10n.addChannel),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: l10n.close,
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpace.s16, AppSpace.s4, AppSpace.s16, AppSpace.s10),
            child: Row(
              children: [
                for (final (i, step) in steps.indexed) ...[
                  if (i > 0) const SizedBox(width: AppSpace.s4),
                  _StepDot(
                    number: i + 1,
                    done: i < _stepIndex,
                    current: step == _step,
                  ),
                ],
                const SizedBox(width: AppSpace.s10),
                Expanded(
                  child: Text(
                    _stepName(l10n, _step),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleSmall
                        ?.copyWith(color: colorScheme.onSurface),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildStepBody(l10n)),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.s16, vertical: AppSpace.s10),
                child: _buildFooter(l10n),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The heading follows the step: the add-channel plate and catalogue count
  /// while choosing, then the chosen provider's own avatar and what this step
  /// is about.
  Widget _buildHeader(AppLocalizations l10n) {
    final preset = _preset;
    final title = channelProviderTitle(l10n, preset.id);
    final avatar = ChannelIdentityAvatar(
      label: title,
      color: channelPresetIdentityColor(preset),
      size: AppSize.touch,
      radius: AppRadius.control,
    );

    return switch (_step) {
      _WizardStep.provider => ChannelDialogHeader(
          leading: const ChannelIconPlate(Icons.add_link),
          title: l10n.addChannel,
          subtitle: l10n.providerCountSummary(
            kChannelProviderPresets.length,
            ChannelProviderGroup.values.length,
          ),
          monoSubtitle: true,
          onClose: () => Navigator.pop(context),
        ),
      _WizardStep.variant => ChannelDialogHeader(
          leading: avatar,
          title: '$title · ${_stepName(l10n, _WizardStep.variant)}',
          subtitle: channelProviderVariantHint(l10n, preset.id),
          onClose: () => Navigator.pop(context),
        ),
      final step => ChannelDialogHeader(
          leading: avatar,
          title: '$title · ${_stepName(l10n, step)}',
          subtitle: '${channelProviderGroupHint(l10n, preset.group)}'
              ' · ${channelProviderNeedLabel(l10n, preset.need)}',
          onClose: () => Navigator.pop(context),
        ),
    };
  }

  Widget _buildStepRail(AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    final steps = _steps;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(right: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, AppSpace.s10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, step) in steps.indexed) ...[
                    if (i > 0) const SizedBox(height: 2),
                    _buildStepRow(l10n, i, step),
                  ],
                ],
              ),
            ),
          ),
          // Why the rail just grew or shrank: the provider decides whether a
          // "way in" step exists.
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.s22, 0, 14, 14),
            child: Text(
              l10n.wizardStepsAdaptNote,
              style: Theme.of(context).textTheme.labelSmall?.mono.copyWith(
                    fontWeight: FontWeight.w400,
                    color: colorScheme.outline,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepRow(AppLocalizations l10n, int index, _WizardStep step) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final done = index < _stepIndex;
    final current = index == _stepIndex;

    return Material(
      color: current ? colorScheme.accentTint : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.control),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // A finished step can be revisited; a future one has to be reached
        // through Next, which is where its checks run.
        onTap: done ? () => setState(() => _stepIndex = index) : null,
        child: SizedBox(
          height: AppSize.large,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10),
            child: Row(
              children: [
                _StepDot(number: index + 1, done: done, current: current),
                const SizedBox(width: AppSpace.s10),
                Expanded(
                  child: Text(
                    _stepName(l10n, step),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.metricsOnly.copyWith(
                      fontWeight: current ? FontWeight.w600 : FontWeight.w500,
                      color: current
                          ? colorScheme.onAccentTint
                          : done
                              ? colorScheme.onSurface
                              : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(AppLocalizations l10n) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(
          l10n.wizardStepCounter(_stepIndex + 1, _steps.length),
          style: theme.textTheme.labelSmall?.mono
              .copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const Spacer(),
        AppButton(
          label: l10n.back,
          variant: AppButtonVariant.text,
          onPressed: _stepIndex == 0 ? null : _back,
        ),
        const SizedBox(width: AppSpace.s6),
        AppButton(
          label: _nextLabel(l10n),
          loading: _submitting,
          onPressed: _next,
        ),
      ],
    );
  }

  Widget _buildStepBody(AppLocalizations l10n) {
    final step = _step;
    const formPadding = EdgeInsets.fromLTRB(16, 14, 16, 16);

    final Widget body = switch (step) {
      _WizardStep.provider => _buildProviderStep(l10n),
      _WizardStep.variant => SingleChildScrollView(
          padding: formPadding,
          child: _buildVariantStep(l10n),
        ),
      _WizardStep.connection => SingleChildScrollView(
          padding: formPadding,
          child: _buildConnectionStep(l10n),
        ),
      _WizardStep.appearance => SingleChildScrollView(
          padding: formPadding,
          child: _buildAppearanceStep(l10n),
        ),
    };

    return AnimatedSwitcher(
      duration: AppMotion.durationOf(context, AppMotion.state),
      switchInCurve: AppMotion.enter,
      switchOutCurve: AppMotion.enter,
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: KeyedSubtree(key: ValueKey(step), child: body),
    );
  }

  // --- Step 1: provider ------------------------------------------------------

  /// Presets matching the search box, in declaration order. An empty query
  /// matches everything, which is what keeps every preset reachable — the
  /// picker has gone blind to whole vendors before, when it was driven by
  /// hand-written id lists instead of the catalogue itself.
  List<ChannelProviderPreset> _filteredPresets(AppLocalizations l10n) {
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isEmpty) return kChannelProviderPresets;
    return kChannelProviderPresets.where((p) {
      final haystack = [
        p.id,
        p.channelType,
        channelProviderTitle(l10n, p.id),
        channelProviderSubtitle(l10n, p),
        p.defaultEndpoint ?? '',
        // The names a provider is also known by. Folding the separate
        // "Qianwen Platform" row into DashScope only works because 千问 /
        // Qwen / 通义 still land on it.
        ...p.searchAliases,
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  Widget _buildProviderStep(AppLocalizations l10n) {
    final matches = _filteredPresets(l10n);

    final rows = <Widget>[];
    for (final group in ChannelProviderGroup.values) {
      final inGroup = matches.where((p) => p.group == group).toList();
      if (inGroup.isEmpty) continue;
      rows.add(ChannelProviderGroupCaption(
        l10n: l10n,
        group: group,
        count: inGroup.length,
        first: rows.isEmpty,
      ));
      for (final preset in inGroup) {
        rows.add(ChannelProviderRow(
          l10n: l10n,
          preset: preset,
          selected: preset.id == _selectedProviderId,
          onTap: () => _selectProvider(preset.id),
        ));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, AppSpace.s10),
          child: ChannelField(
            controller: _searchCtrl,
            hint: l10n.searchProvidersAlias,
            prefixIcon: Icons.search,
            onChanged: (_) => setState(() {}),
          ),
        ),
        Expanded(
          child: matches.isEmpty
              ? ChannelProviderNoMatch(
                  l10n: l10n,
                  query: _searchCtrl.text.trim(),
                  onUseCustom: _useCustomProvider,
                )
              // Built eagerly: sixteen rows is nothing, and a lazy list leaves
              // the rows past the fold unbuilt — which is how a preset goes
              // missing from anything that looks for it without scrolling.
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: rows,
                  ),
                ),
        ),
      ],
    );
  }

  // --- Step 2: way in (variant presets only) ---------------------------------

  Widget _buildVariantStep(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final preset = _preset;
    final selected = _variant;
    if (selected == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChannelSectionLabel(channelProviderVariantTitle(l10n, preset.id)),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, variant) in preset.variants.indexed) ...[
                if (i > 0) const SizedBox(width: AppSpace.s6 + 2),
                Expanded(
                  child: _buildVariantCard(
                    l10n,
                    variant,
                    selected: variant.id == selected.id,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpace.s16),
        // What the choice resolves to: the stored protocol and the address
        // it will be sent to, before the next step asks for the key.
        Container(
          padding: const EdgeInsets.all(AppSpace.s10),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.variantResultLabel,
                style: theme.textTheme.labelSmall?.mono
                    .copyWith(color: colorScheme.outline),
              ),
              const SizedBox(width: AppSpace.s10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      channelTypeLabel(l10n, _resolvedChannelType()),
                      style: theme.textTheme.labelSmall?.mono
                          .copyWith(color: colorScheme.onSurface),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _endpointPreview(),
                      style: theme.textTheme.labelSmall?.mono
                          .copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The address the current face resolves to, or the version path a relay
  /// will append to a host not typed yet.
  String _endpointPreview() {
    if (_endpointCtrl.text.trim().isNotEmpty) return _resolvedEndpoint();
    final suffix = _endpointSuffix;
    return suffix.isEmpty ? '—' : 'https://…$suffix';
  }

  Widget _buildVariantCard(
    AppLocalizations l10n,
    ChannelProviderVariant variant, {
    required bool selected,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final preset = _preset;

    return Material(
      color: selected ? colorScheme.accentTint : colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        side: BorderSide(
          color: selected ? colorScheme.primary : colorScheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _selectVariant(variant.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.s10, vertical: AppSpace.s6 + 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                channelProviderVariantLabel(l10n, preset.id, variant.id),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? colorScheme.onAccentTint
                      : colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                protocolFamilyLabel(
                    l10n, Vendors.byId(variant.channelType).family),
                style: theme.textTheme.labelSmall?.mono.copyWith(
                  fontWeight: FontWeight.w400,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Step 3: endpoint & key ------------------------------------------------

  Widget _buildConnectionStep(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildEndpointField(l10n),
        const SizedBox(height: AppSpace.s16),
        ChannelLabelledField(
          // The field stays for the local runtimes rather than disappearing:
          // vanishing would leave someone who *has* put reverse-proxy auth in
          // front with nowhere to put the key.
          label: _keyOptional
              ? '${l10n.apiKey} · ${l10n.apiKeyOptional}'
              : l10n.apiKey,
          helper: _keyOptional ? l10n.apiKeyLocalNote : l10n.apiKeyStorageNotice,
          child: ChannelField(
            controller: _apiKeyCtrl,
            mono: true,
            obscurable: true,
            hint: _keyOptional ? l10n.apiKeyLocalPlaceholder : null,
            errorText: _apiKeyError(l10n),
            onChanged: (_) => setState(_clearProbe),
          ),
        ),
        const SizedBox(height: AppSpace.s16),
        Row(
          children: [
            AppButton(
              label: l10n.probeChannel,
              icon: Icons.network_check,
              variant: AppButtonVariant.secondary,
              accentLabel: true,
              loading: _probing,
              onPressed: _endpointMissing ? null : _runProbe,
            ),
            const SizedBox(width: AppSpace.s10),
            Expanded(
              child: Text(
                l10n.probeSkippableNote,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w400,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          ],
        ),
        if (_probe != null) ...[
          const SizedBox(height: AppSpace.s10),
          ChannelProbeResultCard(
            l10n: l10n,
            result: _probe!,
            onRetry: _probing ? null : _runProbe,
          ),
        ],
      ],
    );
  }

  Widget _buildEndpointField(AppLocalizations l10n) {
    final preset = _preset;
    final variant = _variant;
    // A relay is one whose *resolved* face appends a version path — which for
    // NewAPI is decided by the format, not by the preset.
    final isRelay = _endpointSuffix.isNotEmpty;
    final family = Vendors.byId(_resolvedChannelType()).family;
    final isMidjourney = family == ProtocolFamily.midjourney;
    final presetEndpoint = variant?.defaultEndpoint ?? preset.defaultEndpoint;
    final edited = presetEndpoint != null &&
        _endpointCtrl.text.trim() != presetEndpoint;

    final helper = isRelay
        ? l10n.newApiBaseHint
        : isMidjourney
            ? l10n.midjourneyEndpointHint
            : presetEndpoint != null
                ? l10n.endpointPresetValue(presetEndpoint)
                : switch (family) {
                    ProtocolFamily.gemini => l10n.googleV1BetaHint,
                    ProtocolFamily.anthropic => l10n.anthropicV1Hint,
                    ProtocolFamily.dashscope => l10n.dashscopeApiV1Hint,
                    _ => l10n.openaiV1Hint,
                  };

    return ChannelLabelledField(
      label: isRelay ? l10n.newApiBaseUrl : l10n.endpointUrl,
      badge: edited
          ? ChannelBadge(
              l10n.presetEndpointModified,
              tone: ChannelBadgeTone.warning,
            )
          : null,
      trailing: edited
          ? AppButton(
              label: l10n.restorePresetEndpoint,
              variant: AppButtonVariant.text,
              size: AppButtonSize.compact,
              onPressed: () => setState(() {
                _applyPresetEndpoint();
                _clearProbe();
              }),
            )
          : null,
      helper: helper,
      child: ChannelField(
        controller: _endpointCtrl,
        mono: true,
        hint: isRelay || isMidjourney
            ? 'https://your-newapi-host.com'
            : 'https://your-api.com/v1',
        errorText: _endpointError(l10n),
        onChanged: (_) => setState(_clearProbe),
      ),
    );
  }

  // --- Step 4: tag & appearance ----------------------------------------------

  Widget _buildAppearanceStep(AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: ChannelLabelledField(
                label: l10n.displayName,
                child: ChannelField(
                  controller: _nameCtrl,
                  hint: l10n.nameHint,
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ),
            const SizedBox(width: AppSpace.s10),
            Expanded(
              flex: 2,
              child: ChannelLabelledField(
                label: l10n.tag,
                child: ChannelField(
                  controller: _tagCtrl,
                  mono: true,
                  hint: l10n.tagHint,
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.s16),
        ChannelFieldLabel(l10n.tagColor),
        const SizedBox(height: AppSpace.s4),
        ChannelTagColorPicker(
          l10n: l10n,
          selectedColor: _tagColor,
          onColorChanged: (color) => setState(() {
            _tagColor = color;
            _tagColorChosen = true;
          }),
        ),
        const SizedBox(height: AppSpace.s16),
        ChannelFieldLabel(l10n.channelListPreview),
        const SizedBox(height: AppSpace.s4),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          // What will actually be stored: an empty name or tag falls back to
          // the provider's, and the preview says so rather than going blank.
          child: ChannelListRowPreview(
            name: _resolvedName(),
            tag: _resolvedTag(),
            color: Color(_tagColor),
            subline: l10n.countModels(0),
          ),
        ),
        const SizedBox(height: AppSpace.s16),
        ChannelToggleCard(
          title: l10n.enableDiscovery,
          description: l10n.enableDiscoveryDesc,
          value: _enableDiscovery,
          onChanged: (v) => setState(() => _enableDiscovery = v),
        ),
      ],
    );
  }

  // --- Preview ---------------------------------------------------------------

  /// `Ready to add this channel?` — every value that will be stored, as it
  /// will be stored, before anything is written.
  Future<bool?> _showPreview() {
    final l10n = widget.l10n;
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AppDialog(
        icon: Icons.fact_check_outlined,
        title: l10n.previewReady,
        subtitle: channelProviderTitle(l10n, _preset.id),
        maxWidth: 420,
        content: _buildPreviewSummary(dialogContext, l10n),
        actions: [
          AppButton(
            label: l10n.back,
            variant: AppButtonVariant.text,
            onPressed: () => Navigator.pop(dialogContext, false),
          ),
          AppButton(
            label: l10n.addChannel,
            autofocus: true,
            onPressed: () => Navigator.pop(dialogContext, true),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewSummary(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final keyStyle = theme.textTheme.labelSmall?.mono
        .copyWith(color: colorScheme.onSurfaceVariant);
    final valueStyle = theme.textTheme.labelSmall?.mono
        .copyWith(fontWeight: FontWeight.w400, color: colorScheme.onSurface);
    final key = _apiKeyCtrl.text.trim();

    Widget row(String label, Widget value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 84,
                child: Text(label,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: keyStyle),
              ),
              const SizedBox(width: AppSpace.s10),
              Expanded(child: value),
            ],
          ),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpace.s10),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Column(
            children: [
              row(l10n.displayName, Text(_resolvedName(), style: valueStyle)),
              row(l10n.tag, Text(_resolvedTag(), style: valueStyle)),
              row(
                l10n.protocolField,
                Text(channelTypeLabel(l10n, _resolvedChannelType()),
                    style: valueStyle),
              ),
              row(l10n.endpointUrl, Text(_resolvedEndpoint(), style: valueStyle)),
              row(
                l10n.apiKey,
                Text(
                  key.isEmpty ? '—' : '••••••••',
                  style: valueStyle?.copyWith(
                    color: key.isEmpty
                        ? colorScheme.outline
                        : context.semantic.onSuccessContainer,
                  ),
                ),
              ),
              row(
                l10n.enableDiscovery,
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Icon(
                    _enableDiscovery ? Icons.check : Icons.remove,
                    size: AppSize.iconSm,
                    color: _enableDiscovery
                        ? context.semantic.onSuccessContainer
                        : colorScheme.outline,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (key.isEmpty) ...[
          const SizedBox(height: AppSpace.s10),
          ChannelNoteStrip(l10n.previewEmptyKeyNote),
        ],
      ],
    );
  }
}

/// A step's 20px marker: a filled check once done, an accent ring on the
/// current step, a hairline ring with the step's number ahead.
class _StepDot extends StatelessWidget {
  const _StepDot({
    required this.number,
    required this.done,
    required this.current,
  });

  final int number;
  final bool done;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AnimatedContainer(
      duration: AppMotion.durationOf(context, AppMotion.state),
      curve: AppMotion.enter,
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? colorScheme.primary : Colors.transparent,
        border: done
            ? null
            : Border.all(
                color: current ? colorScheme.primary : colorScheme.outlineVariant,
                width: current ? 2 : 1.5,
              ),
      ),
      child: done
          ? Icon(Icons.check, size: AppSize.iconSm, color: colorScheme.onPrimary)
          : Text(
              '$number',
              style: theme.textTheme.labelSmall?.mono.copyWith(
                fontWeight: FontWeight.w600,
                height: 1,
                color: current
                    ? colorScheme.onAccentTint
                    : colorScheme.onSurfaceVariant,
              ),
            ),
    );
  }
}
