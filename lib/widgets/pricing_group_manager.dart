import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/fee_group_palette.dart';
import '../core/responsive.dart';
import '../l10n/app_localizations.dart';
import '../models/pricing_group.dart';
import '../state/app_state.dart';
import 'app_icon_button.dart';
import 'app_segmented_control.dart';

enum PricingGroupManagerMode {
  section,
  fullPage
}

/// Accent colors for the three token price kinds, used by the editor's price
/// fields. Deliberately the same hues the usage screens use for their input /
/// cache / output stats, so a rate here and a token count there read as the
/// same thing.
const Color _inputAccent = Colors.blue;
const Color _cacheAccent = Colors.teal;
const Color _outputAccent = Colors.green;
const Color _requestAccent = Colors.purple;

/// Narrowest a group card gets before its name starts truncating.
const double _minCardWidth = 320;
const double _cardSpacing = 12;

/// Lists fee groups and hosts their editor.
///
/// A group is a name, a billing mode, the models it prices and up to three
/// rates — more than a row can line up in columns without either squeezing the
/// names or hiding the models behind a tooltip. Each group gets a card, and its
/// identity colour ([feeGroupAccent]) is the same one its bar carries in the
/// usage tab, so the expensive bar there is findable here.
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Named again under the tab that already names it: the tab is
                  // where you were going, this is the top of what you found —
                  // and it is what the button on the right adds to.
                  Text(
                    l10n.feeGroups,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    l10n.feeGroupDesc,
                    style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: () => _showGroupEditor(context, appState, l10n),
              icon: const Icon(Icons.add, size: 18),
              label: Text(l10n.addFeeGroup),
            ),
          ],
        ),
        const SizedBox(height: 16),
        list,
      ],
    );
  }

  /// The cards, in as many columns as fit.
  Widget _buildList(BuildContext context, List<PricingGroup> groups, AppState appState, AppLocalizations l10n) {
    final modelsByGroup = _modelsByGroup(appState);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Capped at four: wider than that a card is mostly empty space between
        // a short name and three short numbers.
        final columns = ((constraints.maxWidth + _cardSpacing) / (_minCardWidth + _cardSpacing))
            .floor()
            .clamp(1, 4);
        final cardWidth = (constraints.maxWidth - _cardSpacing * (columns - 1)) / columns;

        return Wrap(
          spacing: _cardSpacing,
          runSpacing: _cardSpacing,
          children: [
            for (final group in groups)
              SizedBox(
                width: cardWidth,
                child: _GroupCard(
                  group: group,
                  models: modelsByGroup[group.id] ?? const [],
                  onEdit: () => _showGroupEditor(context, appState, l10n, group: group),
                  onDelete: () => _confirmDelete(context, appState, l10n, group),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Display names of the models pointing at each group, by group id.
  ///
  /// A group only means something through the models it prices, so the card
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

/// One fee group. Tap anywhere to edit; the delete button waits for hover so
/// the card's face stays the group rather than the controls for it.
class _GroupCard extends StatefulWidget {
  final PricingGroup group;
  final List<String> models;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _GroupCard({
    required this.group,
    required this.models,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_GroupCard> createState() => _GroupCardState();
}

class _GroupCardState extends State<_GroupCard> {
  bool _hovering = false;

  bool get _isToken => widget.group.billingMode == 'token';

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final accent = feeGroupAccent(widget.group.id);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Material(
        color: colorScheme.surfaceContainerHigh,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: _hovering ? accent.withAlpha(120) : colorScheme.outlineVariant.withAlpha(90),
          ),
        ),
        child: InkWell(
          onTap: widget.onEdit,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // The group's colour, along the top edge where it can be picked
              // out from across the grid without tinting the card's contents.
              Container(height: 3, color: accent),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildIdentity(colorScheme, l10n, accent),
                    const SizedBox(height: 10),
                    _buildConsumers(colorScheme, l10n),
                    const SizedBox(height: 12),
                    Divider(height: 1, color: colorScheme.outlineVariant.withAlpha(90)),
                    const SizedBox(height: 12),
                    // A floor, not a height: everything above this line is
                    // one line tall, so the price block is the only reason two
                    // cards in a row would end at different heights — a
                    // request group's single rate is shorter than a token
                    // group's three stacked ones.
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 38),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _buildPrices(colorScheme, l10n),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIdentity(ColorScheme colorScheme, AppLocalizations l10n, Color accent) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: accent.withAlpha(35),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(_isToken ? Icons.token_outlined : Icons.ads_click, size: 18, color: accent),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.group.name,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  _buildModeBadge(l10n, accent),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      l10n.feeGroupModelCount(widget.models.length),
                      style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // Reserved, not conjured on hover: a button that appears from nowhere
        // would reflow the name it sits beside. On touch layouts there is no
        // pointer to hover with, so the button must simply be there — same
        // rule as the usage list's delete action.
        SizedBox(
          width: 28,
          child: _hovering || !Responsive.isDesktop(context)
              ? IconButton(
                  icon: const Icon(Icons.delete_outline, size: 17),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  visualDensity: VisualDensity.compact,
                  tooltip: l10n.delete,
                  onPressed: widget.onDelete,
                )
              : null,
        ),
      ],
    );
  }

  Widget _buildModeBadge(AppLocalizations l10n, Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: accent.withAlpha(30),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        _isToken ? l10n.tokenBilling : l10n.requestBilling,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: accent),
      ),
    );
  }

  /// The models this group bills.
  Widget _buildConsumers(ColorScheme colorScheme, AppLocalizations l10n) {
    if (widget.models.isEmpty) {
      // Worth saying out loud: an orphaned group prices nothing, and nothing
      // else on this screen would ever tell you.
      return Row(
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
      message: widget.models.join('\n'),
      child: Text(
        widget.models.join(', '),
        style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: colorScheme.outline),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildPrices(ColorScheme colorScheme, AppLocalizations l10n) {
    final group = widget.group;

    if (!_isToken) {
      return Row(
        children: [
          Text(
            l10n.priceLabelRequest,
            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
          ),
          const Spacer(),
          _priceValue(colorScheme, group.requestPrice, unit: 'Req', large: true),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _priceColumn(colorScheme, l10n.priceLabelInput, group.inputPrice),
        _priceColumn(
          colorScheme,
          l10n.priceLabelCache,
          group.effectiveCacheInputPrice,
          // Always shown, even when unset: an inherited rate is still the rate
          // the user gets billed, so hiding it would just raise the question.
          inherited: group.cacheInputPrice == null,
          tooltip: group.cacheInputPrice == null ? l10n.cachePriceFollowsInput : null,
        ),
        _priceColumn(colorScheme, l10n.priceLabelOutput, group.outputPrice),
      ],
    );
  }

  /// One rate under its name. [inherited] renders the value muted — it is not
  /// configured on this group, it is following the input price.
  Widget _priceColumn(
    ColorScheme colorScheme,
    String label,
    double price, {
    bool inherited = false,
    String? tooltip,
  }) {
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 10.5, color: colorScheme.onSurfaceVariant),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 3),
        _priceValue(colorScheme, price, inherited: inherited),
      ],
    );

    return Expanded(child: tooltip == null ? column : Tooltip(message: tooltip, child: column));
  }

  Widget _priceValue(
    ColorScheme colorScheme,
    double price, {
    String unit = 'M',
    bool large = false,
    bool inherited = false,
  }) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      // One Text, two spans: the unit is smaller than the rate but part of the
      // same number, and two Texts in a Row would let a line break fall between
      // them.
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '\$${price.toStringAsFixed(4)}'),
            // A rate with no unit is not a rate: $0.78 per million tokens and
            // $0.78 per request differ by six orders of magnitude, and the
            // number alone cannot say which it is.
            TextSpan(
              text: '/$unit',
              style: TextStyle(
                fontSize: large ? 10 : 9,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        maxLines: 1,
        style: TextStyle(
          fontSize: large ? 16 : 12.5,
          fontWeight: FontWeight.w700,
          fontFamily: 'monospace',
          fontStyle: inherited ? FontStyle.italic : FontStyle.normal,
          color: inherited ? colorScheme.outline : colorScheme.onSurface,
        ),
      ),
    );
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

  /// Price fields whose current text failed validation on the last save
  /// attempt. Cleared per field as soon as it is edited again.
  final Set<TextEditingController> _invalidFields = {};

  /// Parses a price the way users type them, not just the way Dart does:
  /// accepts a decimal comma ('1,25'), rejects garbage and negatives.
  /// Returns null when the text is not a usable price.
  static double? _parsePrice(String text) {
    final normalized = text.trim().replaceAll(',', '.');
    final value = double.tryParse(normalized);
    if (value == null || value.isNaN || value.isInfinite || value < 0) {
      return null;
    }
    return value;
  }

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

  /// The group's own colour, so the editor reads as the card you clicked,
  /// opened up. A group being added has no identity yet — nothing to match, so
  /// it borrows the app's.
  Color _accent(ColorScheme colorScheme) =>
      widget.group == null ? colorScheme.primary : feeGroupAccent(widget.group!.id);

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
    final accent = _accent(colorScheme);
    final isAdd = widget.group == null;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 14, 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withAlpha(90))),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent.withAlpha(35),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(isAdd ? Icons.add_moderator : Icons.shield_outlined, size: 22, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isAdd ? l10n.addFeeGroup : l10n.editFeeGroup,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                // What the dialog is for, not which mode is selected: the mode
                // is a control 100px below, and a header that echoes it says
                // nothing the user cannot already see and change.
                Text(
                  l10n.feeGroupEditorSubtitle,
                  style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          AppIconButton(
            icon: Icons.close,
            tooltip: l10n.cancel,
            size: 34,
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
        const SizedBox(height: 12),
        TextField(
          controller: nameCtrl,
          style: const TextStyle(fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            // A hint, not a label: under a "Basic Info" heading with a tag
            // icon in the field, a floating "Group Name" label only crowds the
            // name it is labelling.
            hintText: l10n.groupName,
            hintStyle: TextStyle(color: colorScheme.outline, fontWeight: FontWeight.w400),
            border: _fieldBorder(colorScheme),
            enabledBorder: _fieldBorder(colorScheme),
            focusedBorder: _fieldBorder(colorScheme, color: colorScheme.primary, width: 2),
            prefixIcon: Icon(Icons.label_outline, size: 19, color: colorScheme.onSurfaceVariant),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          ),
        ),
        const SizedBox(height: 22),
        _sectionHeader(l10n.billingMode),
        const SizedBox(height: 12),
        // Segmented rather than a dropdown: there are only two modes and each
        // one rewrites the price fields below, so the choice should be visible
        // next to what it changes instead of hidden behind a menu.
        AppSegmentedControl<String>(
          segments: [
            AppSegment(value: 'token', label: l10n.perToken, icon: Icons.token_outlined),
            AppSegment(value: 'request', label: l10n.perRequest, icon: Icons.ads_click),
          ],
          value: billingMode,
          onChanged: (mode) => setState(() => billingMode = mode),
          expand: true,
        ),
        const SizedBox(height: 22),
        _sectionHeader(l10n.priceConfig),
        const SizedBox(height: 12),
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

  /// The rounded outline every field in this editor wears.
  OutlineInputBorder _fieldBorder(ColorScheme colorScheme, {Color? color, double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: color ?? colorScheme.outlineVariant.withAlpha(120),
        width: width,
      ),
    );
  }

  /// A price input styled as the editable twin of its column on the group card:
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
      style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700, fontSize: 17),
      onChanged: (_) {
        if (_invalidFields.remove(ctrl)) setState(() {});
      },
      decoration: InputDecoration(
        labelText: label,
        // Always up, never sitting in the field: the label rides the border so
        // the rate below it has the whole field to itself, and an empty cache
        // field still says which rate it is empty of.
        floatingLabelBehavior: FloatingLabelBehavior.always,
        border: _fieldBorder(colorScheme),
        enabledBorder: _fieldBorder(colorScheme),
        focusedBorder: _fieldBorder(colorScheme, color: accent, width: 2),
        labelStyle: TextStyle(color: accent, fontWeight: FontWeight.w700, fontSize: 15),
        floatingLabelStyle: TextStyle(color: accent, fontWeight: FontWeight.w700, fontSize: 15),
        prefixIcon: Icon(icon, size: 19, color: accent),
        prefixIconConstraints: const BoxConstraints(minWidth: 42, minHeight: 42),
        hintText: hintText,
        hintStyle: TextStyle(
          fontFamily: 'monospace',
          fontStyle: FontStyle.italic,
          fontWeight: FontWeight.w400,
          fontSize: 14,
          color: colorScheme.outline,
        ),
        helperText: helperText,
        helperMaxLines: 2,
        helperStyle: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
        errorText: _invalidFields.contains(ctrl)
            ? AppLocalizations.of(context)!.invalidPriceValue
            : null,
        suffixText: suffix,
        suffixStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: colorScheme.onSurfaceVariant),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      ),
    );
  }

  /// Names a group of fields. No rule under it and no shouting: it is a label
  /// on the form, not a heading competing with the dialog's own title.
  Widget _sectionHeader(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.primary,
      ),
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
    // Rates are snapshotted onto every usage row at request time, so a rate
    // that silently saved as 0.0 (the old `tryParse ?? 0.0` behavior) poisoned
    // history irreversibly. Unparseable input now blocks the save and marks
    // the field instead.
    final cacheText = cacheInputPriceCtrl.text.trim();
    final requiredFields = billingMode == 'token'
        ? [inputPriceCtrl, outputPriceCtrl]
        : [requestPriceCtrl];

    _invalidFields.clear();
    for (final ctrl in requiredFields) {
      if (_parsePrice(ctrl.text) == null) _invalidFields.add(ctrl);
    }
    // Blank cache is a valid "inherit" value; non-blank must parse. This keeps
    // 'empty' (null) distinct from 'invalid' — garbage used to silently flip
    // the field's meaning to "inherit the input price".
    if (cacheText.isNotEmpty && _parsePrice(cacheText) == null) {
      _invalidFields.add(cacheInputPriceCtrl);
    }
    if (_invalidFields.isNotEmpty) {
      setState(() {});
      return;
    }

    final data = {
      'name': nameCtrl.text.trim().isEmpty ? "Unnamed Group" : nameCtrl.text.trim(),
      'billing_mode': billingMode,
      'input_price': _parsePrice(inputPriceCtrl.text) ?? 0.0,
      // Blank stays null so the cost math falls back to the input price; an
      // explicit 0 is kept as a real (free) cache rate.
      'cache_input_price': cacheText.isEmpty ? null : _parsePrice(cacheText),
      'output_price': _parsePrice(outputPriceCtrl.text) ?? 0.0,
      'request_price': _parsePrice(requestPriceCtrl.text) ?? 0.0,
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
