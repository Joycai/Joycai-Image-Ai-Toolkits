import 'package:flutter/material.dart';

import '../../core/app_semantic_colors.dart';
import '../../core/app_theme.dart';
import '../../core/constants.dart';
import '../../core/design_tokens.dart';
import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../services/llm/channel_probe_service.dart';
import '../../services/llm/llm_types.dart';
import '../../services/llm/vendors/vendors.dart';
import '../../state/app_state.dart';
import '../api_key_field.dart';
import '../app_button.dart';
import '../app_dialog.dart';
import '../app_segmented_control.dart';
import '../app_text_field.dart';
import 'channel_form_sections.dart';
import 'channel_provider_presets.dart';

/// Adding a channel, in one page where there is room and in two steps where
/// there is not.
///
/// **One page is the real design.** Choosing a provider and filling in its
/// endpoint and key is a single decision — the provider *is* the endpoint and
/// the key's shape — and a wizard that hid the form behind a Next button made
/// the user commit to a provider before seeing what it would ask for. The
/// two-column layout puts the picker on the left and its configuration on the
/// right, so switching providers rewrites the form in place and the whole
/// thing commits from one footer.
///
/// **Two steps is the fallback, not a second design.** Below
/// [Responsive.tabletBreakpoint] the two columns cannot both be usable: the
/// rail alone wants ~288px and the form wants ~420px before its labels start
/// wrapping. Rather than squeeze them, the same state is shown as pick-then-
/// configure — step 2 carries every field the right column has, so nothing is
/// reachable only on a wide window.
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
  /// Steps in the narrow fallback only; the wide layout has no steps at all.
  static const int _totalSteps = 2;
  int _currentStep = 0;

  String _selectedProviderId = 'openai-official';

  /// Dialect for the `custom` preset (OpenAI-, Gemini- or Claude-shaped REST).
  String _customProtocol = Vendors.openAIRest;

  final TextEditingController _endpointCtrl = TextEditingController();
  final TextEditingController _apiKeyCtrl = TextEditingController();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _tagCtrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();

  bool _enableDiscovery = true;
  int _tagColor = AppConstants.tagColors.first.toARGB32();

  /// Errors stay hidden until the user tries to commit. A required-field
  /// message shown on an untouched form reads as "you did something wrong"
  /// before they have done anything at all.
  bool _submitAttempted = false;

  bool _probing = false;
  ChannelProbeStatus? _probeStatus;
  String? _probeDetail;

  ChannelProviderPreset get _preset =>
      kChannelProviderPresets.firstWhere((p) => p.id == _selectedProviderId);

  @override
  void initState() {
    super.initState();
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
    _endpointCtrl.text = _preset.defaultEndpoint ?? '';
  }

  void _selectProvider(String id) {
    setState(() {
      _selectedProviderId = id;
      _applyPresetEndpoint();
      _clearProbe();
    });
  }

  /// A probe result describes one endpoint/key pair. Any edit to either makes
  /// the previous verdict stale, and a stale green tick is worse than none —
  /// it is the one thing that would let a broken channel through.
  void _clearProbe() {
    _probeStatus = null;
    _probeDetail = null;
  }

  bool get _endpointMissing => _endpointCtrl.text.trim().isEmpty;
  bool get _apiKeyMissing => _apiKeyCtrl.text.trim().isEmpty;

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

  String _resolvedEndpoint() {
    final preset = _preset;
    if (preset.isRelayBase) {
      return _resolveNewApiEndpoint(_endpointCtrl.text, preset.endpointSuffix);
    }
    var raw = _endpointCtrl.text.trim();
    while (raw.endsWith('/')) {
      raw = raw.substring(0, raw.length - 1);
    }
    return raw;
  }

  String _resolvedChannelType() =>
      _selectedProviderId == 'custom' ? _customProtocol : _preset.channelType;

  String _resolvedName() => _nameCtrl.text.trim().isEmpty
      ? _selectedProviderId
      : _nameCtrl.text.trim();

  Future<void> _submit() async {
    setState(() => _submitAttempted = true);
    if (_endpointMissing || _apiKeyMissing) {
      // On the narrow layout the offending fields live on step 2; land there
      // rather than flagging fields the user cannot see.
      if (_currentStep != _totalSteps - 1) {
        setState(() => _currentStep = _totalSteps - 1);
      }
      return;
    }

    await widget.appState.addChannel({
      'display_name': _resolvedName(),
      'endpoint': _resolvedEndpoint(),
      'api_key': _apiKeyCtrl.text.trim(),
      'type': _resolvedChannelType(),
      'enable_discovery': _enableDiscovery ? 1 : 0,
      'tag': _tagCtrl.text.trim().isEmpty
          ? _selectedProviderId.split('-').first
          : _tagCtrl.text.trim(),
      'tag_color': _tagColor,
    });
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
      _probeStatus = result.status;
      _probeDetail = result.status == ChannelProbeStatus.ok
          ? '${result.modelCount}'
          : result.detail;
    });
  }

  // --- Build -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (Responsive.isDesktop(context)) return _buildOnePageDialog(widget.l10n);
    if (Responsive.isMobile(context)) return _buildSteppedPage(widget.l10n);
    return _buildSteppedDialog(widget.l10n);
  }

  // --- Layout A: one page, two columns ---------------------------------------

  Widget _buildOnePageDialog(AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;

    // The body claims what the window can spare, between a floor that keeps
    // the rail scrollable and a ceiling that stops the dialog from stretching
    // edge to edge on a tall display. Heading, footer and the dialog's own
    // vertical inset account for the subtracted band.
    final bodyHeight =
        (MediaQuery.sizeOf(context).height - 250).clamp(340.0, 540.0);

    return AppDialog(
      title: l10n.addChannel,
      subtitle: l10n.addChannelSubtitle,
      maxWidth: 960,
      clipBehavior: Clip.antiAlias,
      // The columns carry their own padding and the rail reaches the edges.
      contentPadding: EdgeInsets.zero,
      onClose: () => Navigator.pop(context),
      content: SizedBox(
        height: bodyHeight,
        child: Row(
          // Stretch, so the rule between the columns is full height. A
          // VerticalDivider would collapse to nothing here — a Row hands its
          // children loose vertical constraints and the divider has no
          // intrinsic height of its own.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 288, child: _buildProviderRail(l10n)),
            Container(width: 1, color: colorScheme.outlineVariant),
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                      child: _buildConfigColumn(l10n, pinnedDiscovery: true),
                    ),
                  ),
                  // Pinned to the foot of the column rather than trailing the
                  // form: it is a property of the channel as a whole, not the
                  // next field after the tag, and leaving it in the flow left
                  // the pane's spare height dangling below everything.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
                    child: _buildDiscoveryCard(l10n),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actionsOverride: Row(
        children: [
          AppButton(
            label: l10n.probeChannel,
            icon: Icons.network_check,
            variant: AppButtonVariant.secondary,
            size: AppButtonSize.compact,
            loading: _probing,
            onPressed: _endpointMissing ? null : _runProbe,
          ),
          const SizedBox(width: 10),
          Expanded(child: _buildProbeStatus(l10n)),
          const SizedBox(width: 10),
          AppButton(
            label: l10n.cancel,
            variant: AppButtonVariant.text,
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          AppButton(label: l10n.addChannel, onPressed: _submit),
        ],
      ),
    );
  }

  /// The left column: a search box over every preset, grouped by protocol.
  Widget _buildProviderRail(AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    final matches = _filteredPresets(l10n);

    return Container(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: AppTextField(
              controller: _searchCtrl,
              hint: l10n.searchProviders,
              prefixIcon: const Icon(Icons.search, size: AppSize.iconMd),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Expanded(
            child: matches.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        l10n.noProviderMatch,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                    children: [
                      for (final group in ChannelProviderGroup.values)
                        ...() {
                          final inGroup =
                              matches.where((p) => p.group == group).toList();
                          if (inGroup.isEmpty) return <Widget>[];
                          return <Widget>[
                            _buildRailHeading(
                                channelProviderGroupLabel(l10n, group)),
                            for (final preset in inGroup)
                              _buildRailRow(l10n, preset),
                          ];
                        }(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

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
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  Widget _buildRailHeading(String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 6),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.bold,
          letterSpacing: AppType.trackedLabelSpacing,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildRailRow(AppLocalizations l10n, ChannelProviderPreset preset) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isSelected = _selectedProviderId == preset.id;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: InkWell(
        onTap: () => _selectProvider(preset.id),
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            color: isSelected ? colorScheme.accentTint : null,
            border: Border.all(
              color: isSelected ? colorScheme.accentRing : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Icon(
                preset.icon,
                size: AppSize.iconMd,
                color: isSelected
                    ? colorScheme.onAccentTint
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  channelProviderTitle(l10n, preset.id),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  // The label's colour belongs to the row it sits in, not to
                  // the slot it borrows its metrics from.
                  style: textTheme.bodyMedium?.metricsOnly.copyWith(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected
                        ? colorScheme.onAccentTint
                        : colorScheme.onSurface,
                  ),
                ),
              ),
              if (isSelected) ...[
                const SizedBox(width: 6),
                Icon(Icons.check,
                    size: AppSize.iconSm, color: colorScheme.onAccentTint),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// The right column, and the whole of step 2 on the narrow layout.
  ///
  /// [showPreview] swaps the provider header — which restates a choice still
  /// visible in the rail beside it — for a preview of the channel as the list
  /// will draw it, which is what the narrow layout needs instead: there the
  /// provider was picked on a step the user has left.
  ///
  /// [pinnedDiscovery] drops the discovery card, for a caller that draws it
  /// at the foot of its own column.
  Widget _buildConfigColumn(
    AppLocalizations l10n, {
    bool showPreview = false,
    bool pinnedDiscovery = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showPreview) ...[
          _buildChannelPreview(l10n),
          const SizedBox(height: 16),
        ] else ...[
          _buildProviderHeader(l10n),
          const SizedBox(height: 16),
        ],
        if (_selectedProviderId == 'custom') ...[
          _buildDialectPicker(l10n),
          const SizedBox(height: 16),
        ],
        _buildEndpointField(l10n),
        const SizedBox(height: 16),
        ApiKeyField(
          controller: _apiKeyCtrl,
          label: l10n.enterApiKey,
          errorText: _apiKeyError(l10n),
          onChanged: (_) => setState(_clearProbe),
        ),
        const SizedBox(height: 6),
        _buildHelperText(l10n.apiKeyStorageNotice),
        const SizedBox(height: 16),
        _buildAppearanceRow(l10n),
        const SizedBox(height: 14),
        _buildColorRow(l10n),
        if (!pinnedDiscovery) ...[
          const SizedBox(height: 16),
          _buildDiscoveryCard(l10n),
        ],
      ],
    );
  }

  Widget _buildProviderHeader(AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final preset = _preset;

    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: colorScheme.accentTint,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Icon(preset.icon,
              size: AppSize.iconLg, color: colorScheme.onAccentTint),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                channelProviderTitle(l10n, preset.id),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              Text(
                channelProviderSubtitle(l10n, preset),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall
                    ?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        _buildTypeBadge(_resolvedChannelType()),
      ],
    );
  }

  /// The vendor id the channel will be stored under. Shown because it is what
  /// every later screen — the channel list, the debug log, a support thread —
  /// calls this channel, and it is not derivable from the provider's name.
  Widget _buildTypeBadge(String type) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        type,
        style: Theme.of(context)
            .textTheme
            .labelMedium
            ?.copyWith(color: colorScheme.onSurfaceVariant),
      ),
    );
  }

  /// How the channel will read in the list once added — the narrow layout's
  /// answer to the wide one's provider header, which the user has just left
  /// behind on step 1.
  Widget _buildChannelPreview(AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final name = _resolvedName();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.accentTint,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colorScheme.accentRing),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Color(_tagColor),
              shape: BoxShape.circle,
            ),
            child: Icon(_preset.icon, size: AppSize.iconSm, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleSmall?.metricsOnly.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onAccentTint,
                  ),
                ),
                Text(
                  '${l10n.countModels(0)} · ${_resolvedChannelType()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall
                      ?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            l10n.channelListPreview,
            style: textTheme.labelMedium?.copyWith(color: colorScheme.onAccentTint),
          ),
        ],
      ),
    );
  }

  Widget _buildDialectPicker(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.channelType,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 8),
        // Bare brand names rather than the localized protocol titles used as
        // rail headings: three of those in one track ellipsize to
        // "OpenAI Compa…" on a phone, and these three words are the same in
        // every language the app ships.
        AppSegmentedControl<String>(
          segments: const [
            AppSegment(value: Vendors.openAIRest, label: 'OpenAI'),
            AppSegment(value: Vendors.googleRest, label: 'Google'),
            AppSegment(value: Vendors.anthropicRest, label: 'Anthropic'),
          ],
          value: _customProtocol,
          onChanged: (v) => setState(() {
            _customProtocol = v;
            _clearProbe();
          }),
          expand: true,
        ),
      ],
    );
  }

  Widget _buildEndpointField(AppLocalizations l10n) {
    final preset = _preset;
    final isRelay = preset.isRelayBase;
    final isMidjourney = preset.id == 'midjourney-proxy';
    final canReset = preset.defaultEndpoint != null &&
        _endpointCtrl.text.trim() != preset.defaultEndpoint;

    final helper = isRelay
        ? l10n.newApiBaseHint
        : isMidjourney
            ? l10n.midjourneyEndpointHint
            : preset.defaultEndpoint != null
                ? l10n.endpointOverrideHint
                : switch (_customProtocol) {
                    Vendors.googleRest => l10n.googleV1BetaHint,
                    Vendors.anthropicRest => l10n.anthropicV1Hint,
                    _ => l10n.openaiV1Hint,
                  };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppTextField(
          controller: _endpointCtrl,
          label: isRelay ? l10n.newApiBaseUrl : l10n.endpointUrl,
          hint: isRelay || isMidjourney
              ? 'https://your-newapi-host.com'
              : 'https://your-api.com/v1',
          errorText: _endpointError(l10n),
          prefixIcon: const Icon(Icons.link, size: AppSize.iconMd),
          // Reset lives in the field rather than as a link beside its label:
          // the label is the floating one every other input in the app uses,
          // and a second label above it to hang the link off would read as
          // two names for one field.
          suffixIcon: canReset
              ? IconButton(
                  icon: const Icon(Icons.restart_alt, size: AppSize.iconMd),
                  tooltip: l10n.resetToDefault,
                  onPressed: () => setState(() {
                    _applyPresetEndpoint();
                    _clearProbe();
                  }),
                )
              : null,
          onChanged: (_) => setState(_clearProbe),
        ),
        const SizedBox(height: 6),
        _buildHelperText(helper),
      ],
    );
  }

  Widget _buildHelperText(String text) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodySmall
          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
    );
  }

  Widget _buildAppearanceRow(AppLocalizations l10n) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: AppTextField(
            controller: _nameCtrl,
            label: l10n.displayName,
            hint: l10n.nameHint,
            prefixIcon: const Icon(Icons.label_outline, size: AppSize.iconMd),
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: AppTextField(
            controller: _tagCtrl,
            label: l10n.tag,
            hint: l10n.tagHint,
            prefixIcon: const Icon(Icons.tag, size: AppSize.iconMd),
          ),
        ),
      ],
    );
  }

  Widget _buildColorRow(AppLocalizations l10n) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          l10n.tagColor,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ChannelColorStrip(
            l10n: l10n,
            selectedColor: _tagColor,
            onColorChanged: (color) => setState(() => _tagColor = color),
          ),
        ),
      ],
    );
  }

  Widget _buildDiscoveryCard(AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.enableDiscovery,
                  style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.enableDiscoveryDesc,
                  style: textTheme.bodySmall
                      ?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Switch(
            value: _enableDiscovery,
            onChanged: (v) => setState(() => _enableDiscovery = v),
          ),
        ],
      ),
    );
  }

  /// The connection verdict, as a coloured dot plus one line of text. Empty
  /// until a probe has run, so the footer stays quiet on an untouched form.
  Widget _buildProbeStatus(AppLocalizations l10n) {
    final status = _probeStatus;
    if (status == null) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    final semantic = context.semantic;

    final (Color color, String message) = switch (status) {
      ChannelProbeStatus.ok => (
          semantic.onSuccessContainer,
          '${l10n.probeOk} · ${_probeDetail ?? '0'} ${l10n.probeModels}',
        ),
      ChannelProbeStatus.connectedNoModels => (
          semantic.onSuccessContainer,
          l10n.probeConnectedNoModels,
        ),
      ChannelProbeStatus.authFailed => (colorScheme.error, l10n.probeAuthFailed),
      ChannelProbeStatus.notAnApi => (colorScheme.error, l10n.probeNotAnApi),
      ChannelProbeStatus.unreachable => (
          colorScheme.error,
          _probeDetail == null
              ? l10n.probeUnreachable
              : '${l10n.probeUnreachable} — ${_clip(_probeDetail!)}',
        ),
      ChannelProbeStatus.notSupported => (
          colorScheme.onSurfaceVariant,
          l10n.probeNotSupported,
        ),
    };

    final failed = status == ChannelProbeStatus.authFailed ||
        status == ChannelProbeStatus.notAnApi ||
        status == ChannelProbeStatus.unreachable;

    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
        if (failed)
          AppButton(
            label: l10n.probeRetry,
            variant: AppButtonVariant.text,
            size: AppButtonSize.compact,
            onPressed: _probing ? null : _runProbe,
          ),
      ],
    );
  }

  static String _clip(String s) => s.length > 120 ? '${s.substring(0, 120)}…' : s;

  // --- Layout B: two steps (tablet dialog and phone page) --------------------

  Widget _buildSteppedDialog(AppLocalizations l10n) {
    return AppDialog(
      title: l10n.addChannel,
      subtitle: _stepCaption(l10n),
      maxWidth: 560,
      clipBehavior: Clip.antiAlias,
      contentPadding: EdgeInsets.zero,
      // Fixed height so the dialog doesn't resize between steps; the shorter
      // step simply leaves whitespace below.
      content: SizedBox(height: 520, child: _buildStepBody(l10n)),
      // Not `actions`: the step dots are pinned opposite the buttons, and the
      // shell's right-aligned row would shove the whole thing to one side.
      actionsOverride: Row(
        children: [
          _buildStepDots(),
          const Spacer(),
          if (_currentStep > 0)
            AppButton(
              label: l10n.back,
              variant: AppButtonVariant.text,
              onPressed: _back,
            )
          else
            AppButton(
              label: l10n.cancel,
              variant: AppButtonVariant.text,
              onPressed: () => Navigator.pop(context),
            ),
          const SizedBox(width: 8),
          AppButton(
            label: _currentStep == _totalSteps - 1 ? l10n.addChannel : l10n.next,
            onPressed: _currentStep == _totalSteps - 1
                ? _submit
                : () => setState(() => _currentStep++),
          ),
        ],
      ),
    );
  }

  Widget _buildSteppedPage(AppLocalizations l10n) {
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.addChannel),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              // Same treatment AppDialog gives the desktop dialog's subtitle,
              // so the step caption reads the same on both.
              child: Text(
                _stepCaption(l10n),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          ),
          Expanded(child: _buildStepBody(l10n)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  _buildStepDots(),
                  const Spacer(),
                  if (_currentStep > 0) ...[
                    AppButton(
                      label: l10n.back,
                      variant: AppButtonVariant.secondary,
                      onPressed: _back,
                    ),
                    const SizedBox(width: 12),
                  ],
                  AppButton(
                    label: _currentStep == _totalSteps - 1
                        ? l10n.addChannel
                        : l10n.next,
                    onPressed: _currentStep == _totalSteps - 1
                        ? _submit
                        : () => setState(() => _currentStep++),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _back() {
    if (_currentStep > 0) setState(() => _currentStep--);
  }

  String _stepCaption(AppLocalizations l10n) {
    final name = _currentStep == 0
        ? l10n.stepProvider
        : l10n.stepConnectionAppearance;
    return '${_currentStep + 1}/$_totalSteps · $name';
  }

  Widget _buildStepBody(AppLocalizations l10n) {
    return AnimatedSwitcher(
      duration: AppMotion.durationOf(context, AppMotion.reveal),
      switchInCurve: AppMotion.enter,
      switchOutCurve: AppMotion.enter,
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: KeyedSubtree(
        key: ValueKey(_currentStep),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: _currentStep == 0
              ? _buildProviderStep(l10n)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildConfigColumn(l10n, showPreview: true),
                    const SizedBox(height: 14),
                    // Test connection has no footer to live in here — the
                    // footer belongs to the step dots — so it sits at the end
                    // of the form it tests.
                    Row(
                      children: [
                        AppButton(
                          label: l10n.probeChannel,
                          icon: Icons.network_check,
                          variant: AppButtonVariant.secondary,
                          size: AppButtonSize.compact,
                          loading: _probing,
                          onPressed: _endpointMissing ? null : _runProbe,
                        ),
                      ],
                    ),
                    if (_probeStatus != null) ...[
                      const SizedBox(height: 8),
                      _buildProbeStatus(l10n),
                    ],
                  ],
                ),
        ),
      ),
    );
  }

  /// Step 1 of the fallback: the same catalogue as the rail, as cards.
  Widget _buildProviderStep(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final group in ChannelProviderGroup.values) ...[
          if (group != ChannelProviderGroup.values.first)
            const SizedBox(height: 14),
          _buildRailHeading(channelProviderGroupLabel(l10n, group)),
          _buildProviderGrid(
            l10n,
            kChannelProviderPresets.where((p) => p.group == group).toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildProviderGrid(
    AppLocalizations l10n,
    List<ChannelProviderPreset> presets,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 440;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: twoColumns ? 2 : 1,
            mainAxisExtent: 64,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: presets.length,
          itemBuilder: (context, index) =>
              _buildProviderCard(l10n, presets[index]),
        );
      },
    );
  }

  Widget _buildProviderCard(AppLocalizations l10n, ChannelProviderPreset preset) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isSelected = _selectedProviderId == preset.id;

    return InkWell(
      onTap: () => _selectProvider(preset.id),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: AnimatedContainer(
        duration: AppMotion.durationOf(context, AppMotion.state),
        curve: AppMotion.enter,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: isSelected ? colorScheme.primary : colorScheme.outlineVariant,
            width: isSelected ? 2 : 1,
          ),
          color: isSelected ? colorScheme.accentTint : null,
        ),
        child: Row(
          children: [
            Icon(
              preset.icon,
              size: AppSize.iconLg,
              color: isSelected
                  ? colorScheme.onAccentTint
                  : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    channelProviderTitle(l10n, preset.id),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleSmall?.metricsOnly.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isSelected
                          ? colorScheme.onAccentTint
                          : colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    channelProviderSubtitle(l10n, preset),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelMedium
                        ?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (isSelected) ...[
              const SizedBox(width: 6),
              Icon(Icons.check_circle,
                  color: colorScheme.onAccentTint, size: AppSize.iconMd),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStepDots() {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < _totalSteps; i++) ...[
          AnimatedContainer(
            duration: AppMotion.durationOf(context, AppMotion.reveal),
            curve: AppMotion.move,
            width: i == _currentStep ? 18 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == _currentStep
                  ? colorScheme.primary
                  : colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          if (i < _totalSteps - 1) const SizedBox(width: 5),
        ],
      ],
    );
  }
}
