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
                _buildGroupRow(context, groups[i], appState, l10n, compact: compact),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildGroupRow(
    BuildContext context,
    PricingGroup group,
    AppState appState,
    AppLocalizations l10n, {
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

    return InkWell(
      onTap: () => _showGroupEditor(context, appState, l10n, group: group),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: compact ? 12 : 10),
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [Expanded(child: identity), actions]),
                  const SizedBox(height: 10),
                  prices,
                ],
              )
            : Row(
                children: [
                  Expanded(flex: 4, child: identity),
                  const SizedBox(width: 16),
                  Expanded(flex: 5, child: Align(alignment: Alignment.centerRight, child: prices)),
                  const SizedBox(width: 8),
                  actions,
                ],
              ),
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
        builder: (context) => _PricingGroupEditor(appState: appState, l10n: l10n, group: group, isMobile: true),
      );
    } else {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(group == null ? l10n.addFeeGroup : l10n.editFeeGroup),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 450),
            child: _PricingGroupEditor(appState: appState, l10n: l10n, group: group, isMobile: false),
          ),
        ),
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

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;

    final content = SingleChildScrollView(
      padding: widget.isMobile ? const EdgeInsets.all(24) : EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.isMobile) ...[
            Text(
              widget.group == null ? l10n.addFeeGroup : l10n.editFeeGroup,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
          ],
          TextField(
            controller: nameCtrl,
            decoration: InputDecoration(
              labelText: l10n.groupName,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.label_outline),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: billingMode,
            items: [
              DropdownMenuItem(value: 'token', child: Text(l10n.perToken)),
              DropdownMenuItem(value: 'request', child: Text(l10n.perRequest)),
            ],
            onChanged: (v) => setState(() => billingMode = v!),
            decoration: InputDecoration(
              labelText: l10n.billingMode,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.payments_outlined),
            ),
          ),
          const SizedBox(height: 24),
          if (billingMode == 'token') ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildPriceField(inputPriceCtrl, l10n.inputPrice, "\$/M")),
                const SizedBox(width: 16),
                Expanded(child: _buildPriceField(outputPriceCtrl, l10n.outputPrice, "\$/M")),
              ],
            ),
            const SizedBox(height: 16),
            // Full width rather than sharing the row above, so its hint — the
            // part that explains the empty-means-inherit rule — has room.
            _buildPriceField(
              cacheInputPriceCtrl,
              l10n.cacheInputPrice,
              "\$/M",
              hintText: inputPriceCtrl.text.trim().isEmpty ? null : inputPriceCtrl.text.trim(),
              helperText: l10n.cacheInputPriceHint,
            ),
          ] else
            _buildPriceField(requestPriceCtrl, l10n.requestPrice, "\$/Req"),

          if (widget.isMobile) ...[
            const SizedBox(height: 40),
            FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              child: Text(widget.group == null ? l10n.add : l10n.save),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(minimumSize: const Size.fromHeight(56)),
              child: Text(l10n.cancel),
            ),
          ],
        ],
      ),
    );

    if (widget.isMobile) return content;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        content,
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: _save,
              child: Text(widget.group == null ? l10n.add : l10n.save),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPriceField(
    TextEditingController ctrl,
    String label,
    String suffix, {
    String? hintText,
    String? helperText,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        hintText: hintText,
        helperText: helperText,
        helperMaxLines: 2,
        suffixText: suffix,
        suffixStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
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
