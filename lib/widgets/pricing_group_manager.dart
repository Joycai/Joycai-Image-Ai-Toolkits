import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/responsive.dart';
import '../l10n/app_localizations.dart';
import '../models/pricing_group.dart';
import '../state/app_state.dart';

enum PricingGroupManagerMode {
  section,
  fullPage
}

/// Accent colors for the three token price kinds. Deliberately the same hues the
/// usage screens use for their input / cache / output stats, so a price here and
/// a token count there read as the same thing.
const Color _inputAccent = Colors.blue;
const Color _cacheAccent = Colors.teal;
const Color _outputAccent = Colors.green;
const Color _requestAccent = Colors.purple;

/// Below this width a group row stacks its prices under the name instead of
/// lining them up beside it.
const double _compactWidth = 620;

/// Lists fee groups and hosts their editor.
///
/// Groups render as full-width rows rather than a card grid: a group is little
/// more than a name and three short numbers, so rows keep the prices aligned in
/// scannable columns and give long names room, where fixed-height cards clipped
/// them.
class PricingGroupManager extends StatelessWidget {
  final PricingGroupManagerMode mode;

  const PricingGroupManager({
    super.key,
    this.mode = PricingGroupManagerMode.section,
  });

  bool get _isFullPage => mode == PricingGroupManagerMode.fullPage;

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final l10n = AppLocalizations.of(context)!;
    final groups = appState.allPricingGroups;
    final isMobile = Responsive.isMobile(context);

    if (groups.isEmpty) {
      return _buildEmptyState(context, appState, l10n);
    }

    final list = _buildList(context, groups, appState, l10n);

    if (_isFullPage) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: isMobile
            ? FloatingActionButton.extended(
                onPressed: () => _showGroupEditor(context, appState, l10n),
                icon: const Icon(Icons.add),
                label: Text(l10n.addFeeGroup),
              )
            : null,
        body: Column(
          children: [
            if (!isMobile)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.feeGroups,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          l10n.feeGroupDesc,
                          style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 13),
                        ),
                      ],
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: () => _showGroupEditor(context, appState, l10n),
                      icon: const Icon(Icons.add),
                      label: Text(l10n.addFeeGroup),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: list,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.feeGroupDesc,
                style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 12),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.tonalIcon(
              onPressed: () => _showGroupEditor(context, appState, l10n),
              icon: const Icon(Icons.add, size: 18),
              label: Text(l10n.addFeeGroup),
              style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
          ],
        ),
        const SizedBox(height: 12),
        list,
      ],
    );
  }

  /// The rows, hosted on a bordered Material so ink splashes clip to the
  /// rounded corners instead of painting on the card behind.
  Widget _buildList(BuildContext context, List<PricingGroup> groups, AppState appState, AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    final modelsByGroup = _modelsByGroup(appState);

    return Material(
      color: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant.withAlpha(90)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < _compactWidth;
          return Column(
            children: [
              for (var i = 0; i < groups.length; i++) ...[
                if (i > 0) Divider(height: 1, color: colorScheme.outlineVariant.withAlpha(70)),
                _buildGroupRow(
                  context,
                  groups[i],
                  appState,
                  l10n,
                  models: modelsByGroup[groups[i].id] ?? const [],
                  compact: compact,
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  /// Display names of the models pointing at each group, by group id.
  ///
  /// A group only means something through the models it prices, so the row
  /// says which ones — and a group no model uses says that, which is otherwise
  /// invisible from this screen.
  Map<int, List<String>> _modelsByGroup(AppState appState) {
    final map = <int, List<String>>{};
    for (final model in appState.allModels) {
      final groupId = model.feeGroupId;
      if (groupId != null) {
        (map[groupId] ??= []).add(model.modelName);
      }
    }
    return map;
  }

  Widget _buildGroupRow(
    BuildContext context,
    PricingGroup group,
    AppState appState,
    AppLocalizations l10n, {
    required List<String> models,
    required bool compact,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final isToken = group.billingMode == 'token';
    final accent = isToken ? _inputAccent : _requestAccent;

    final identity = Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: accent.withAlpha(25),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(isToken ? Icons.token_outlined : Icons.ads_click, size: 19, color: accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                group.name,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                isToken ? l10n.tokenBilling : l10n.requestBilling,
                style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );

    final actions = IconButton(
      icon: const Icon(Icons.delete_outline, size: 18),
      visualDensity: VisualDensity.compact,
      tooltip: l10n.delete,
      onPressed: () => _confirmDelete(context, appState, l10n, group),
    );

    final prices = _buildPrices(context, group, l10n, compact: compact);
    final consumers = _buildConsumers(context, models, l10n);

    return InkWell(
      onTap: () => _showGroupEditor(context, appState, l10n, group: group),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: compact ? 12 : 10),
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [Expanded(child: identity), actions]),
                  const SizedBox(height: 8),
                  consumers,
                  const SizedBox(height: 10),
                  prices,
                ],
              )
            : Row(
                children: [
                  Expanded(flex: 4, child: identity),
                  const SizedBox(width: 16),
                  // The gap between a name and its prices used to be air. The
                  // row is wide because this fills it, not the other way round.
                  Expanded(flex: 4, child: consumers),
                  const SizedBox(width: 16),
                  Expanded(flex: 5, child: Align(alignment: Alignment.centerRight, child: prices)),
                  const SizedBox(width: 8),
                  actions,
                ],
              ),
      ),
    );
  }

  /// The models billed by this group: a count, and as many names as fit.
  Widget _buildConsumers(BuildContext context, List<String> models, AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;

    if (models.isEmpty) {
      // Worth saying out loud: an orphaned group prices nothing, and nothing
      // else on this screen would ever tell you.
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.link_off, size: 13, color: colorScheme.outline),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              l10n.feeGroupUnused,
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.outline,
                fontStyle: FontStyle.italic,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }

    return Tooltip(
      message: models.join('\n'),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.memory_outlined, size: 13, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.feeGroupModelCount(models.length),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  models.join(', '),
                  style: TextStyle(fontSize: 10.5, color: colorScheme.outline),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrices(BuildContext context, PricingGroup group, AppLocalizations l10n, {required bool compact}) {
    if (group.billingMode != 'token') {
      return Wrap(
        alignment: compact ? WrapAlignment.start : WrapAlignment.end,
        children: [
          _pricePill(context, l10n.priceLabelRequest, group.requestPrice, _requestAccent, unit: 'Req'),
        ],
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: compact ? WrapAlignment.start : WrapAlignment.end,
      children: [
        _pricePill(context, l10n.priceLabelInput, group.inputPrice, _inputAccent),
        // Always shown, even when unset: an inherited rate is still the rate the
        // user gets billed, so hiding it would just raise the question.
        _pricePill(
          context,
          l10n.priceLabelCache,
          group.effectiveCacheInputPrice,
          _cacheAccent,
          inherited: group.cacheInputPrice == null,
          tooltip: group.cacheInputPrice == null ? l10n.cachePriceFollowsInput : null,
        ),
        _pricePill(context, l10n.priceLabelOutput, group.outputPrice, _outputAccent),
      ],
    );
  }

  /// One price chip. [inherited] renders the value muted — it is not configured
  /// on this group, it is following the input price.
  Widget _pricePill(
    BuildContext context,
    String label,
    double price,
    Color accent, {
    String unit = 'M',
    bool inherited = false,
    String? tooltip,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = inherited ? colorScheme.outline : accent;

    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(inherited ? 12 : 22),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color),
          ),
          const SizedBox(width: 6),
          Text(
            '\$${price.toStringAsFixed(4)}/$unit',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
              fontStyle: inherited ? FontStyle.italic : FontStyle.normal,
              color: inherited ? colorScheme.onSurfaceVariant : colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );

    return tooltip == null ? pill : Tooltip(message: tooltip, child: pill);
  }

  Widget _buildEmptyState(BuildContext context, AppState appState, AppLocalizations l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withAlpha(40),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.monetization_on_outlined, size: 64, color: Theme.of(context).colorScheme.primary.withAlpha(150)),
            ),
            const SizedBox(height: 24),
            Text(l10n.noFeeGroups, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(l10n.feeGroupDesc, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.outline)),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () => _showGroupEditor(context, appState, l10n),
              icon: const Icon(Icons.add),
              label: Text(l10n.addFeeGroup),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, AppState appState, AppLocalizations l10n, PricingGroup group) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.delete),
        content: Text(l10n.deleteFeeGroupConfirm(group.name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await appState.deletePricingGroup(group.id!);
              if (context.mounted) Navigator.pop(context);
            },
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }

  void _showGroupEditor(BuildContext context, AppState appState, AppLocalizations l10n, {PricingGroup? group}) {
    if (Responsive.isMobile(context)) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (context) => _PricingGroupEditor(appState: appState, l10n: l10n, group: group, isMobile: true),
      );
    } else {
      showDialog(
        context: context,
        builder: (context) => _PricingGroupEditor(appState: appState, l10n: l10n, group: group, isMobile: false),
      );
    }
  }
}

class _PricingGroupEditor extends StatefulWidget {
  final AppState appState;
  final AppLocalizations l10n;
  final PricingGroup? group;
  final bool isMobile;

  const _PricingGroupEditor({
    required this.appState,
    required this.l10n,
    this.group,
    required this.isMobile,
  });

  @override
  State<_PricingGroupEditor> createState() => _PricingGroupEditorState();
}

class _PricingGroupEditorState extends State<_PricingGroupEditor> {
  late TextEditingController nameCtrl;
  late TextEditingController inputPriceCtrl;
  late TextEditingController cacheInputPriceCtrl;
  late TextEditingController outputPriceCtrl;
  late TextEditingController requestPriceCtrl;
  late String billingMode;

  @override
  void initState() {
    super.initState();
    final g = widget.group;
    nameCtrl = TextEditingController(text: g?.name ?? '');
    inputPriceCtrl = TextEditingController(text: (g?.inputPrice ?? 0.0).toString());
    // Left blank when unset, which is what makes the field mean "follow the
    // input price" rather than "free".
    cacheInputPriceCtrl = TextEditingController(text: g?.cacheInputPrice?.toString() ?? '');
    outputPriceCtrl = TextEditingController(text: (g?.outputPrice ?? 0.0).toString());
    requestPriceCtrl = TextEditingController(text: (g?.requestPrice ?? 0.0).toString());
    billingMode = g?.billingMode ?? 'token';

    // The cache field hints the value it would inherit, so it has to follow the
    // input field as it's typed.
    inputPriceCtrl.addListener(_refreshCacheHint);
  }

  void _refreshCacheHint() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    inputPriceCtrl.removeListener(_refreshCacheHint);
    nameCtrl.dispose();
    inputPriceCtrl.dispose();
    cacheInputPriceCtrl.dispose();
    outputPriceCtrl.dispose();
    requestPriceCtrl.dispose();
    super.dispose();
  }

  bool get _isToken => billingMode == 'token';

  /// Accent for the current mode — the same one the group's row and icon tile
  /// use in the list, so the editor reads as that row opened up.
  Color get _modeAccent => _isToken ? _inputAccent : _requestAccent;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final body = Flexible(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
        child: _buildForm(colorScheme),
      ),
    );

    if (widget.isMobile) {
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildGrabber(colorScheme),
            _buildHeader(colorScheme),
            body,
            _buildFooter(colorScheme),
          ],
        ),
      );
    }

    return Dialog(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(colorScheme),
            body,
            _buildFooter(colorScheme),
          ],
        ),
      ),
    );
  }

  Widget _buildGrabber(ColorScheme colorScheme) {
    return Container(
      width: 36,
      height: 4,
      margin: const EdgeInsets.only(top: 10, bottom: 6),
      decoration: BoxDecoration(
        color: colorScheme.outlineVariant,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  // --- Header -------------------------------------------------------------

  Widget _buildHeader(ColorScheme colorScheme) {
    final l10n = widget.l10n;
    final accent = _modeAccent;

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
              color: accent.withAlpha(25),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_isToken ? Icons.token_outlined : Icons.ads_click, size: 21, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.group == null ? l10n.addFeeGroup : l10n.editFeeGroup,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _isToken ? l10n.tokenBilling : l10n.requestBilling,
                  style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
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

  Widget _buildForm(ColorScheme colorScheme) {
    final l10n = widget.l10n;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(l10n.basicInfo),
        const SizedBox(height: 14),
        TextField(
          controller: nameCtrl,
          decoration: InputDecoration(
            labelText: l10n.groupName,
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.label_outline),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          l10n.billingMode,
          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        // Segmented rather than a dropdown: there are only two modes and each
        // one rewrites the price fields below, so the choice should be visible
        // next to what it changes instead of hidden behind a menu.
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<String>(
            segments: [
              ButtonSegment(
                value: 'token',
                icon: const Icon(Icons.token_outlined, size: 17),
                label: Text(l10n.perToken, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              ButtonSegment(
                value: 'request',
                icon: const Icon(Icons.ads_click, size: 17),
                label: Text(l10n.perRequest, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
            selected: {billingMode},
            onSelectionChanged: (s) => setState(() => billingMode = s.first),
            showSelectedIcon: false,
            style: ButtonStyle(
              // Copied off the theme rather than built from scratch: this
              // replaces the button's whole text style, and the app's font is
              // user-selectable, so a bare TextStyle would drop it.
              textStyle: WidgetStatePropertyAll(
                Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ),
        const SizedBox(height: 24),
        _sectionHeader(l10n.priceConfig),
        const SizedBox(height: 14),
        if (_isToken) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildPriceField(inputPriceCtrl, l10n.priceLabelInput, '\$/M', _inputAccent, Icons.input)),
              const SizedBox(width: 12),
              Expanded(child: _buildPriceField(outputPriceCtrl, l10n.priceLabelOutput, '\$/M', _outputAccent, Icons.output)),
            ],
          ),
          const SizedBox(height: 16),
          // Full width rather than sharing the row above, so its hint — the
          // part that explains the empty-means-inherit rule — has room.
          _buildPriceField(
            cacheInputPriceCtrl,
            l10n.priceLabelCache,
            '\$/M',
            _cacheAccent,
            Icons.bolt,
            hintText: inputPriceCtrl.text.trim().isEmpty ? null : inputPriceCtrl.text.trim(),
            helperText: l10n.cacheInputPriceHint,
          ),
        ] else
          _buildPriceField(requestPriceCtrl, l10n.priceLabelRequest, '\$/Req', _requestAccent, Icons.repeat),
      ],
    );
  }

  /// A price input styled as the editable twin of its pill in the group row:
  /// same accent, same icon, same monospace number.
  Widget _buildPriceField(
    TextEditingController ctrl,
    String label,
    String suffix,
    Color accent,
    IconData icon, {
    String? hintText,
    String? helperText,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: accent, width: 2)),
        floatingLabelStyle: TextStyle(color: accent, fontWeight: FontWeight.w700),
        prefixIcon: Icon(icon, size: 18, color: accent),
        prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        hintText: hintText,
        hintStyle: TextStyle(
          fontFamily: 'monospace',
          fontStyle: FontStyle.italic,
          color: colorScheme.outline,
        ),
        helperText: helperText,
        helperMaxLines: 2,
        suffixText: suffix,
        suffixStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: colorScheme.onSurfaceVariant),
      ),
    );
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

  // --- Footer -------------------------------------------------------------

  Widget _buildFooter(ColorScheme colorScheme) {
    final l10n = widget.l10n;
    final saveLabel = widget.group == null ? l10n.add : l10n.save;

    return Container(
      padding: EdgeInsets.fromLTRB(16, 10, 16, widget.isMobile ? 16 : 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colorScheme.outlineVariant.withAlpha(90))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (widget.isMobile) ...[
            Expanded(
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                child: Text(l10n.cancel),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: _save,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                icon: const Icon(Icons.save, size: 18),
                label: Text(saveLabel),
              ),
            ),
          ] else ...[
            TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save, size: 18),
              label: Text(saveLabel),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _save() async {
    final cacheText = cacheInputPriceCtrl.text.trim();
    final data = {
      'name': nameCtrl.text.trim().isEmpty ? "Unnamed Group" : nameCtrl.text.trim(),
      'billing_mode': billingMode,
      'input_price': double.tryParse(inputPriceCtrl.text) ?? 0.0,
      // Blank stays null so the cost math falls back to the input price; an
      // explicit 0 is kept as a real (free) cache rate.
      'cache_input_price': cacheText.isEmpty ? null : double.tryParse(cacheText),
      'output_price': double.tryParse(outputPriceCtrl.text) ?? 0.0,
      'request_price': double.tryParse(requestPriceCtrl.text) ?? 0.0,
    };
    if (widget.group == null) {
      await widget.appState.addPricingGroup(data);
    } else {
      await widget.appState.updatePricingGroup(widget.group!.id!, data);
    }
    if (mounted) {
      Navigator.pop(context);
    }
  }
}
