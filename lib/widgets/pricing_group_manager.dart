import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_theme.dart';
import '../core/design_tokens.dart';
import '../core/responsive.dart';
import '../l10n/app_localizations.dart';
import '../models/pricing_group.dart';
import '../state/app_state.dart';
import 'app_button.dart';
import 'app_dialog.dart';
import 'app_section_label.dart';
import 'app_segmented_control.dart';

enum PricingGroupManagerMode {
  /// Embedded in a page that scrolls it — the usage screen's fee-group tab. A
  /// heading with the description and Add, then the list, all in unbounded
  /// height.
  section,

  /// A page of its own, scrolling its list under a fixed heading.
  fullPage,

  /// The body of the fee-management dialog (`D1a · 1d`): its own heading — the
  /// payments plate, the counts, Add and close — over a scrolling list. Host
  /// it in an [AppDialog] with no title and a `maxHeight`.
  dialog,
}

/// Lists fee groups and edits them in place.
///
/// `D1a · 1d`: each group is one row — the name, how many models it prices
/// (or that none do), its rates as mono tags, and edit / delete. Editing
/// opens the row into an accent-edged card with the name, the billing mode
/// and the rates, validated as they are typed; adding opens the same card at
/// the top of the list. There is no second dialog.
class PricingGroupManager extends StatefulWidget {
  final PricingGroupManagerMode mode;

  const PricingGroupManager({
    super.key,
    this.mode = PricingGroupManagerMode.section,
  });

  @override
  State<PricingGroupManager> createState() => _PricingGroupManagerState();
}

/// The [_PricingGroupManagerState._editing] value for a group being added.
const Object _newGroup = Object();

class _PricingGroupManagerState extends State<PricingGroupManager> {
  /// Null, [_newGroup], or the id of the group open in the editor.
  Object? _editing;

  void _startAdd() => setState(() => _editing = _newGroup);

  void _startEdit(PricingGroup group) => setState(() => _editing = group.id);

  void _stopEditing() {
    if (mounted) setState(() => _editing = null);
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final l10n = AppLocalizations.of(context)!;
    final groups = appState.allPricingGroups;

    // A group deleted while open simply closes its editor.
    if (_editing is int && !groups.any((g) => g.id == _editing)) _editing = null;

    final body = _buildBody(context, appState, l10n, groups);

    switch (widget.mode) {
      case PricingGroupManagerMode.dialog:
        final groupIds = {for (final g in groups) g.id};
        final pricedModels = appState.allModels.where((m) => groupIds.contains(m.feeGroupId)).length;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DialogHeading(
              groupCount: groups.length,
              modelCount: pricedModels,
              onAdd: _startAdd,
            ),
            const SizedBox(height: AppSpace.s16),
            Flexible(child: SingleChildScrollView(child: body)),
          ],
        );
      case PricingGroupManagerMode.fullPage:
        final isMobile = Responsive.isMobile(context);
        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: isMobile
              ? FloatingActionButton.extended(
                  onPressed: _startAdd,
                  icon: const Icon(Icons.add),
                  label: Text(l10n.addFeeGroup),
                )
              : null,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!isMobile)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                  child: _SectionHeading(onAdd: _startAdd),
                ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: body,
                ),
              ),
            ],
          ),
        );
      case PricingGroupManagerMode.section:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _SectionHeading(onAdd: _startAdd),
            const SizedBox(height: AppSpace.s16),
            body,
          ],
        );
    }
  }

  Widget _buildBody(BuildContext context, AppState appState, AppLocalizations l10n, List<PricingGroup> groups) {
    final adding = identical(_editing, _newGroup);
    if (groups.isEmpty && !adding) return const _EmptyGroups();

    final modelsByGroup = _modelsByGroup(appState);
    final children = <Widget>[
      if (adding)
        _GroupEditor(
          key: const ValueKey('fee-group-new'),
          appState: appState,
          group: null,
          onDone: _stopEditing,
        ),
      for (final group in groups)
        if (_editing == group.id)
          _GroupEditor(
            key: ValueKey('fee-group-${group.id}'),
            appState: appState,
            group: group,
            onDone: _stopEditing,
          )
        else
          _GroupRow(
            group: group,
            models: modelsByGroup[group.id] ?? const [],
            onEdit: () => _startEdit(group),
            onDelete: () => _confirmDelete(appState, l10n, group),
          ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (index, child) in children.indexed) ...[
          if (index > 0) const SizedBox(height: 8),
          child,
        ],
      ],
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

  void _confirmDelete(AppState appState, AppLocalizations l10n, PricingGroup group) {
    AppDialog.show<void>(
      context,
      icon: Icons.delete_outline,
      iconColor: Theme.of(context).colorScheme.error,
      maxWidth: 440,
      title: l10n.delete,
      content: Text(l10n.deleteFeeGroupConfirm(group.name)),
      actions: [
        AppButton(
          label: l10n.cancel,
          variant: AppButtonVariant.text,
          autofocus: true,
          onPressed: () => Navigator.pop(context),
        ),
        AppButton(
          label: l10n.delete,
          variant: AppButtonVariant.destructive,
          onPressed: () async {
            await appState.deletePricingGroup(group.id!);
            if (mounted) Navigator.pop(context);
          },
        ),
      ],
    );
  }
}

/// The embedded heading: 「Fee Groups」 over what they are for, and Add.
class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // `D2 · 1b`: the embedded list names itself with the tracked
              // caption, not a second page title under the canvas tabs.
              AppSectionLabel(l10n.feeGroups, padding: EdgeInsets.zero),
              const SizedBox(height: AppSpace.s4),
              Text(
                l10n.feeGroupDesc,
                style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        AppButton(label: l10n.addFeeGroup, icon: Icons.add, onPressed: onAdd),
      ],
    );
  }
}

/// `D1a · 1d` 费用管理 heading: the 44 payments plate on the accent wash, the
/// title over the mono counts, Add and close.
class _DialogHeading extends StatelessWidget {
  const _DialogHeading({required this.groupCount, required this.modelCount, required this.onAdd});

  final int groupCount;
  final int modelCount;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: scheme.accentTint,
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          child: Icon(Icons.payments_outlined, size: 24, color: scheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.feeManagement, maxLines: 1, overflow: TextOverflow.ellipsis, style: textTheme.titleLarge),
              const SizedBox(height: 2),
              Text(
                '${l10n.countGroups(groupCount)} · ${l10n.feeGroupModelCount(modelCount)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelSmall?.mono.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        AppButton(label: l10n.newFeeGroup, icon: Icons.add, onPressed: onAdd),
        const SizedBox(width: AppSpace.s6),
        IconButton(
          icon: const Icon(Icons.close, size: AppSize.iconMd),
          tooltip: l10n.close,
          onPressed: () => Navigator.pop(context),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: AppSize.iconButton, height: AppSize.iconButton),
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
}

/// `D1a · 1e` 「No fee groups created yet」.
class _EmptyGroups extends StatelessWidget {
  const _EmptyGroups();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.s28, horizontal: AppSpace.s16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.payments_outlined, size: AppSpace.s28, color: scheme.outline),
          const SizedBox(height: AppSpace.s10),
          Text(l10n.noFeeGroups, textAlign: TextAlign.center, style: textTheme.titleMedium),
          const SizedBox(height: AppSpace.s4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Text(
              l10n.noFeeGroupsHint,
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: AppType.proseHeight),
            ),
          ),
        ],
      ),
    );
  }
}

/// One fee group at rest (`D1a · 1d` 组行). Tap anywhere to edit.
class _GroupRow extends StatelessWidget {
  const _GroupRow({
    required this.group,
    required this.models,
    required this.onEdit,
    required this.onDelete,
  });

  final PricingGroup group;
  final List<String> models;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  bool get _isToken => group.billingMode == 'token';

  static String _rate(double price, String unit) => '\$${price.toStringAsFixed(4)}/$unit';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final prices = _isToken
        ? [
            _PriceTag(label: l10n.priceLabelInput, value: _rate(group.inputPrice, 'M')),
            // Always shown, even when unset: an inherited rate is still the
            // rate the user gets billed, so hiding it would just raise the
            // question.
            _PriceTag(
              label: l10n.priceLabelCache,
              value: _rate(group.effectiveCacheInputPrice, 'M'),
              inherited: group.cacheInputPrice == null,
              tooltip: group.cacheInputPrice == null ? l10n.cachePriceFollowsInput : null,
            ),
            _PriceTag(label: l10n.priceLabelOutput, value: _rate(group.outputPrice, 'M')),
          ]
        : [_PriceTag(label: l10n.priceLabelRequest, value: _rate(group.requestPrice, 'Req'))];

    return Material(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, AppSpace.s10, 8, AppSpace.s10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      group.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleSmall?.copyWith(color: scheme.onSurface),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _RowIconButton(icon: Icons.edit_outlined, tooltip: l10n.edit, onPressed: onEdit),
                  const SizedBox(width: 2),
                  _RowIconButton(
                    icon: Icons.delete_outline,
                    tooltip: l10n.delete,
                    onPressed: onDelete,
                    danger: true,
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: AppSpace.s4),
                child: _buildConsumers(context, l10n),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: AppSpace.s6, runSpacing: AppSpace.s6, children: prices),
            ],
          ),
        ),
      ),
    );
  }

  /// The models this group bills — or, worth saying out loud, that it bills
  /// none: an orphaned group prices nothing, and nothing else would tell you.
  Widget _buildConsumers(BuildContext context, AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final mono = Theme.of(context).textTheme.labelSmall?.mono;

    if (models.isEmpty) {
      return Text(
        l10n.feeGroupUnused,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: mono?.copyWith(color: scheme.outline),
      );
    }

    return Row(
      children: [
        Text(
          l10n.feeGroupModelCount(models.length),
          style: mono?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Tooltip(
            message: models.join('\n'),
            child: Text(
              models.join(', '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: mono?.copyWith(color: scheme.outline),
            ),
          ),
        ),
      ],
    );
  }
}

/// A rate as `D1a` tags it: the rate's name beside the mono figure, r4 on the
/// card tone. [inherited] renders the figure muted — it is not configured on
/// this group, it follows the input price.
class _PriceTag extends StatelessWidget {
  const _PriceTag({required this.label, required this.value, this.inherited = false, this.tooltip});

  final String label;
  final String value;
  final bool inherited;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final Widget tag = Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(width: AppSpace.s4),
          Text(
            value,
            style: textTheme.labelSmall?.mono.copyWith(
              color: inherited ? scheme.outline : scheme.onSurface,
              fontStyle: inherited ? FontStyle.italic : FontStyle.normal,
            ),
          ),
        ],
      ),
    );

    return tooltip == null ? tag : Tooltip(message: tooltip!, child: tag);
  }
}

class _RowIconButton extends StatelessWidget {
  const _RowIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.danger = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return IconButton(
      icon: Icon(icon, size: AppSize.iconMd),
      tooltip: tooltip,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: AppSize.compact, height: AppSize.compact),
      style: IconButton.styleFrom(
        minimumSize: const Size.square(AppSize.compact),
        foregroundColor: danger ? scheme.error : scheme.onSurfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
      ),
    );
  }
}

/// The editor, open in place of a row (`D1a · 1d` 内嵌编辑态卡): the accent
/// edge on the accent wash, the name, the billing mode, and that mode's rates.
class _GroupEditor extends StatefulWidget {
  const _GroupEditor({
    super.key,
    required this.appState,
    required this.group,
    required this.onDone,
  });

  final AppState appState;
  final PricingGroup? group;
  final VoidCallback onDone;

  @override
  State<_GroupEditor> createState() => _GroupEditorState();
}

class _GroupEditorState extends State<_GroupEditor> {
  late final TextEditingController nameCtrl;
  late final TextEditingController inputPriceCtrl;
  late final TextEditingController cacheInputPriceCtrl;
  late final TextEditingController outputPriceCtrl;
  late final TextEditingController requestPriceCtrl;
  late String billingMode;
  bool _saving = false;

  /// Narrowest a rate field gets before the three stack instead of sharing a
  /// row.
  static const double _minRateField = 110;

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

    // Validation is live, and the cache field hints the value it would inherit
    // from the input field as it is typed.
    for (final ctrl in _priceFields) {
      ctrl.addListener(_refresh);
    }
  }

  List<TextEditingController> get _priceFields =>
      [inputPriceCtrl, cacheInputPriceCtrl, outputPriceCtrl, requestPriceCtrl];

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final ctrl in _priceFields) {
      ctrl.removeListener(_refresh);
    }
    nameCtrl.dispose();
    inputPriceCtrl.dispose();
    cacheInputPriceCtrl.dispose();
    outputPriceCtrl.dispose();
    requestPriceCtrl.dispose();
    super.dispose();
  }

  bool get _isToken => billingMode == 'token';

  /// Whether [ctrl]'s text cannot be saved. A blank cache rate is a valid
  /// "inherit"; every other rate must parse.
  bool _invalid(TextEditingController ctrl) {
    final text = ctrl.text.trim();
    if (identical(ctrl, cacheInputPriceCtrl) && text.isEmpty) return false;
    return _parsePrice(text) == null;
  }

  List<TextEditingController> get _activeFields =>
      _isToken ? [inputPriceCtrl, cacheInputPriceCtrl, outputPriceCtrl] : [requestPriceCtrl];

  bool get _canSave => !_activeFields.any(_invalid);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isAdd = widget.group == null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.accentTint,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: scheme.primary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isAdd ? l10n.addFeeGroup : l10n.editFeeGroup,
            style: textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: AppType.trackedLabelSpacing,
              color: scheme.onAccentTint,
            ),
          ),
          const SizedBox(height: AppSpace.s10),
          TextField(
            controller: nameCtrl,
            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
            decoration: _decoration(context).copyWith(hintText: l10n.groupName),
          ),
          const SizedBox(height: AppSpace.s10),
          // Segmented rather than a dropdown: there are only two modes and
          // each one rewrites the rate fields below, so the choice should be
          // visible next to what it changes.
          AppSegmentedControl<String>(
            segments: [
              AppSegment(value: 'token', label: l10n.perToken, icon: Icons.token_outlined),
              AppSegment(value: 'request', label: l10n.perRequest, icon: Icons.ads_click),
            ],
            value: billingMode,
            onChanged: (mode) => setState(() => billingMode = mode),
            expand: true,
          ),
          const SizedBox(height: 12),
          if (_isToken)
            LayoutBuilder(
              builder: (context, constraints) {
                final fields = [
                  _priceField(context, inputPriceCtrl, l10n.priceLabelInput, '\$/M'),
                  _priceField(
                    context,
                    cacheInputPriceCtrl,
                    l10n.priceLabelCache,
                    '\$/M',
                    // The rate a blank field inherits; with no input rate yet,
                    // the rule itself.
                    hintText: inputPriceCtrl.text.trim().isEmpty
                        ? l10n.cachePriceBlankPlaceholder
                        : inputPriceCtrl.text.trim(),
                  ),
                  _priceField(context, outputPriceCtrl, l10n.priceLabelOutput, '\$/M'),
                ];
                if (constraints.maxWidth >= 3 * _minRateField + 2 * 8) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final (i, field) in fields.indexed) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(child: field),
                      ],
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (i, field) in fields.indexed) ...[
                      if (i > 0) const SizedBox(height: AppSpace.s10),
                      field,
                    ],
                  ],
                );
              },
            )
          else
            _priceField(context, requestPriceCtrl, l10n.priceLabelRequest, '\$/Req'),
          const SizedBox(height: AppSpace.s6),
          // What the numbers are charged against: blank cache inherits the
          // input rate; a request rate is per successful request. Per-token
          // and per-request rates differ by six orders of magnitude.
          Text(
            _isToken ? l10n.cacheInputPriceHint : l10n.requestPriceHint,
            style: textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant, height: AppType.tightHeight),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AppButton(
                label: l10n.cancel,
                variant: AppButtonVariant.text,
                onPressed: widget.onDone,
              ),
              const SizedBox(width: AppSpace.s6),
              AppButton(
                label: isAdd ? l10n.add : l10n.save,
                icon: Icons.save,
                loading: _saving,
                onPressed: _canSave ? _save : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  InputDecoration _decoration(BuildContext context) => InputDecoration(
        filled: true,
        fillColor: Theme.of(context).colorScheme.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.s10, vertical: 12),
      );

  Widget _priceField(
    BuildContext context,
    TextEditingController ctrl,
    String label,
    String suffix, {
    String? hintText,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final invalid = _invalid(ctrl);

    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: textTheme.bodyMedium?.mono,
      decoration: _decoration(context).copyWith(
        labelText: label,
        // Always up, never sitting in the field: an empty cache field still
        // says which rate it is empty of.
        floatingLabelBehavior: FloatingLabelBehavior.always,
        hintText: hintText,
        hintStyle: textTheme.bodyMedium?.mono.copyWith(color: scheme.outline, fontStyle: FontStyle.italic),
        suffixText: suffix,
        suffixStyle: textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
        error: invalid
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, size: AppSize.iconSm - 2, color: scheme.onErrorContainer),
                  const SizedBox(width: AppSpace.s4),
                  Expanded(
                    child: Text(
                      l10n.invalidPriceValue,
                      style: textTheme.labelSmall?.copyWith(color: scheme.onErrorContainer),
                    ),
                  ),
                ],
              )
            : null,
      ),
    );
  }

  Future<void> _save() async {
    // Rates are snapshotted onto every usage row at request time, so a rate
    // that silently saved as 0.0 poisoned history irreversibly. Unparseable
    // input blocks the save rather than being coerced.
    if (!_canSave) {
      setState(() {});
      return;
    }
    final cacheText = cacheInputPriceCtrl.text.trim();

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

    setState(() => _saving = true);
    if (widget.group == null) {
      await widget.appState.addPricingGroup(data);
    } else {
      await widget.appState.updatePricingGroup(widget.group!.id!, data);
    }
    if (mounted) widget.onDone();
  }
}
