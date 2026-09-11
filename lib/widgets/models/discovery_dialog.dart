import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/design_tokens.dart';
import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../models/llm_channel.dart';
import '../../services/llm/llm_types.dart';
import '../../services/llm/model_discovery_service.dart';
import '../../services/llm/model_family.dart';
import '../../state/app_state.dart';
import 'model_tag_chip.dart';
import '../app_button.dart';
import '../app_search_field.dart';
import '../app_dialog.dart';

/// Fetches a channel's model list and adds the ones picked (`D1a · 1c`).
///
/// A 520 dialog: the cloud-sync plate over 「Select models to add」 and the
/// mono count, a search with Select All / Deselect All, a 48-row checklist on
/// the column tone — a model already on the channel greyed with an
/// 「Already Added」 badge — and 「Add Selected (n)」. On a phone the same body
/// is a full-screen page.
class DiscoveryDialog extends StatefulWidget {
  final LLMChannel channel;
  final LLMModelConfig config;
  final AppState appState;
  final AppLocalizations l10n;

  const DiscoveryDialog({
    super.key,
    required this.channel,
    required this.config,
    required this.appState,
    required this.l10n,
  });

  @override
  State<DiscoveryDialog> createState() => _DiscoveryDialogState();
}

class _DiscoveryDialogState extends State<DiscoveryDialog> {
  bool _isLoading = true;
  bool _adding = false;
  String? _error;
  List<DiscoveredModel> _discovered = [];
  List<DiscoveredModel> _filtered = [];
  final Set<String> _selectedIds = {};
  final TextEditingController _filterCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetch();
    _filterCtrl.addListener(_onFilterChanged);
  }

  @override
  void dispose() {
    _filterCtrl.dispose();
    super.dispose();
  }

  void _onFilterChanged() {
    final query = _filterCtrl.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filtered = List.from(_discovered);
      } else {
        _filtered = _discovered
            .where((m) => m.displayName.toLowerCase().contains(query) || m.modelId.toLowerCase().contains(query))
            .toList();
      }
    });
  }

  Future<void> _fetch() async {
    try {
      final models = await ModelDiscoveryService().discoverModels(widget.config);
      if (mounted) {
        setState(() {
          _discovered = models;
          _filtered = List.from(models);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _retry() {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    _fetch();
  }

  bool _isModelAdded(DiscoveredModel m) {
    return widget.appState.allModels.any((em) => em.modelId == m.modelId && em.channelId == widget.channel.id);
  }

  List<DiscoveredModel> get _available => _filtered.where((m) => !_isModelAdded(m)).toList();

  void _selectAll() => setState(() => _selectedIds.addAll(_available.map((m) => m.modelId)));

  void _deselectAll() => setState(_selectedIds.clear);

  void _toggle(DiscoveredModel m) => setState(() {
        if (!_selectedIds.remove(m.modelId)) _selectedIds.add(m.modelId);
      });

  bool get _ready => !_isLoading && _error == null && _discovered.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final scheme = Theme.of(context).colorScheme;

    if (Responsive.isMobile(context)) {
      return Scaffold(
        backgroundColor: scheme.surface,
        appBar: AppBar(
          title: Text(l10n.fetchModels),
          leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(52),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _buildToolbar(context, l10n),
            ),
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildMainContent(context, l10n),
        ),
        bottomNavigationBar: _ready
            ? SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _buildAddButton(l10n, size: AppButtonSize.large, fullWidth: true),
                ),
              )
            : null,
      );
    }

    final media = MediaQuery.sizeOf(context);

    return AppDialog(
      titleWidget: _buildHeading(context, l10n),
      maxWidth: 520,
      // A fixed height, not just a ceiling: the body swaps between a spinner,
      // an error and a list, and without one the dialog would resize under
      // the pointer each time discovery moves on.
      maxHeight: media.height.clamp(280.0, 640.0),
      contentPadding: const EdgeInsets.fromLTRB(AppSpace.s22, AppSpace.s10, AppSpace.s22, AppSpace.s16),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildToolbar(context, l10n),
          const SizedBox(height: AppSpace.s10),
          Expanded(child: _buildMainContent(context, l10n)),
        ],
      ),
      actions: [
        AppButton(
          label: l10n.cancel,
          variant: AppButtonVariant.text,
          onPressed: () => Navigator.pop(context),
        ),
        if (_ready) _buildAddButton(l10n),
      ],
    );
  }

  Widget _buildAddButton(AppLocalizations l10n, {AppButtonSize size = AppButtonSize.normal, bool fullWidth = false}) {
    return AppButton(
      label: l10n.addSelected(_selectedIds.length),
      icon: Icons.add,
      size: size,
      fullWidth: fullWidth,
      loading: _adding,
      onPressed: _selectedIds.isEmpty ? null : _handleAddSelected,
    );
  }

  /// The 44 plate, the title and the mono line saying how many came back from
  /// which channel.
  Widget _buildHeading(BuildContext context, AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final subtitle = _ready
        ? '${l10n.modelsDiscovered(_discovered.length)} · ${widget.channel.displayName}'
        : widget.channel.displayName;

    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: scheme.accentTint,
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          child: Icon(Icons.cloud_sync_outlined, size: 24, color: scheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.selectModelsToAdd, maxLines: 1, overflow: TextOverflow.ellipsis, style: textTheme.titleLarge),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelSmall?.mono.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The search on the column tone, and Select All / Deselect All in the deep
  /// ink once there is a list to act on.
  Widget _buildToolbar(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final available = _ready ? _available : const <DiscoveredModel>[];
    final allSelected = available.isNotEmpty && available.every((m) => _selectedIds.contains(m.modelId));

    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: AppSize.control,
            child: Theme(
              data: theme.copyWith(
                inputDecorationTheme: theme.inputDecorationTheme.copyWith(
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerLow,
                  prefixIconConstraints: const BoxConstraints(minWidth: AppSize.control, minHeight: 0),
                  suffixIconConstraints: const BoxConstraints(minWidth: AppSize.control, minHeight: 0),
                ),
              ),
              child: AppSearchField(
                controller: _filterCtrl,
                hint: l10n.searchModels,
                compact: true,
                onChanged: (_) => setState(() {}),
              ),
            ),
          ),
        ),
        if (_ready && available.isNotEmpty) ...[
          const SizedBox(width: AppSpace.s6),
          AppButton(
            label: l10n.selectAll,
            variant: AppButtonVariant.text,
            onPressed: allSelected ? null : _selectAll,
          ),
          AppButton(
            label: l10n.deselectAll,
            variant: AppButtonVariant.text,
            onPressed: _selectedIds.isEmpty ? null : _deselectAll,
          ),
        ],
      ],
    );
  }

  Widget _buildMainContent(BuildContext context, AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;

    if (_isLoading) {
      return Center(
        key: const ValueKey('discovery_dialog_loading'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
            const SizedBox(height: AppSpace.s16),
            Text(
              l10n.discoveringModels,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return _StateView(
        key: const ValueKey('discovery_dialog_error'),
        icon: Icons.error_outline,
        color: scheme.error,
        title: l10n.fetchFailedTitle,
        message: l10n.fetchFailed(_error!),
        action: AppButton(
          label: l10n.retryTask,
          icon: Icons.refresh,
          variant: AppButtonVariant.secondary,
          onPressed: _retry,
        ),
      );
    }

    if (_discovered.isEmpty) {
      return _StateView(
        key: const ValueKey('discovery_dialog_empty'),
        icon: Icons.cloud_off_outlined,
        color: scheme.outline,
        title: l10n.noNewModelsFound,
        message: l10n.noNewModelsFoundHint,
      );
    }

    if (_filtered.isEmpty) {
      return _StateView(
        key: const ValueKey('discovery_dialog_no_matches'),
        icon: Icons.search_off,
        color: scheme.outline,
        message: l10n.pickerNoMatches,
      );
    }

    return Column(
      key: const ValueKey('discovery_dialog_content'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Material(
            color: scheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.control),
              side: BorderSide(color: scheme.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: ListView.separated(
              itemCount: _filtered.length,
              separatorBuilder: (_, _) => Divider(height: 1, color: scheme.outlineVariant),
              itemBuilder: (context, index) {
                final m = _filtered[index];
                return _buildRow(context, m, isAdded: _isModelAdded(m), isSelected: _selectedIds.contains(m.modelId));
              },
            ),
          ),
        ),
        const SizedBox(height: AppSpace.s10),
        // What adding does not bring along, said before the user finds out.
        Text(
          l10n.discoveryCapabilitiesNote,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: AppType.tightHeight,
              ),
        ),
      ],
    );
  }

  Widget _buildRow(BuildContext context, DiscoveredModel m, {required bool isAdded, required bool isSelected}) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final showName = m.displayName.isNotEmpty && m.displayName != m.modelId;

    return Semantics(
      checked: isAdded || isSelected,
      enabled: !isAdded,
      child: Material(
        color: isSelected ? scheme.accentTint : Colors.transparent,
        child: InkWell(
          onTap: isAdded ? null : () => _toggle(m),
          child: SizedBox(
            height: 48,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  _CheckMark(checked: isSelected, added: isAdded),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          m.modelId,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.mono.copyWith(
                            color: isAdded ? scheme.outline : scheme.onSurface,
                          ),
                        ),
                        if (showName)
                          Text(
                            m.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ModelKindBadge(_inferTag(m)),
                  if (isAdded) ...[
                    const SizedBox(width: AppSpace.s6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s6, vertical: 1),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                      ),
                      child: Text(
                        widget.l10n.alreadyAdded,
                        style: textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleAddSelected() async {
    setState(() => _adding = true);
    for (var id in _selectedIds) {
      final m = _discovered.firstWhere((dm) => dm.modelId == id);
      await widget.appState.addModel({
        'model_id': m.modelId,
        'model_name': m.displayName,
        'tag': _inferTag(m),
        'is_paid': 1,
        'supports_stream': 1,
        'supports_standard': 1,
        'sort_order': widget.appState.allModels.length,
        'channel_id': widget.channel.id,
      });
    }
    if (mounted) Navigator.pop(context);
  }

  String _inferTag(DiscoveredModel m) => ModelFamilyClassifier.inferTag(m.modelId);
}

/// The 18px r4 check: the solid accent when picked, a 1.5px hairline when not,
/// the track with a weak check when the model is already on the channel.
class _CheckMark extends StatelessWidget {
  const _CheckMark({required this.checked, required this.added});

  final bool checked;
  final bool added;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.xs),
        color: added ? scheme.surfaceContainerHighest : (checked ? scheme.primary : null),
        border: added || checked ? null : Border.all(color: scheme.outlineVariant, width: 1.5),
      ),
      child: added || checked
          ? Icon(Icons.check, size: AppSize.iconSm, color: added ? scheme.outline : scheme.onPrimary)
          : null,
    );
  }
}

class _StateView extends StatelessWidget {
  const _StateView({
    super.key,
    required this.icon,
    required this.color,
    required this.message,
    this.title,
    this.action,
  });

  final IconData icon;
  final Color color;
  final String? title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpace.s22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: AppSpace.s28, color: color),
            const SizedBox(height: AppSpace.s10),
            if (title != null) ...[
              Text(
                title!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: scheme.onSurface),
              ),
              const SizedBox(height: AppSpace.s4),
            ],
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            if (action != null) ...[
              const SizedBox(height: AppSpace.s16),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
