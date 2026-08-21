import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/design_tokens.dart';
import '../l10n/app_localizations.dart';
import 'app_dialog.dart';
import 'app_search_field.dart';

/// One row of a [SearchablePickerField]'s picker.
///
/// Not const-constructible on purpose: [searchText] is folded once per option
/// and reused for every keystroke, which is what keeps filtering a few
/// thousand models off the frame budget.
class PickerOption<T> {
  PickerOption({
    required this.value,
    required this.label,
    this.secondary,
    this.badge,
    this.badgeColor,
  });

  final T value;

  /// The row's primary line — a model or channel name.
  final String label;

  /// A quieter second line, set in the mono role: an identifier the user may
  /// be searching by (a model id) rather than reading.
  final String? secondary;

  /// A short tag chip ahead of [label], carrying [badgeColor].
  final String? badge;
  final Color? badgeColor;

  /// Everything this option can be matched on, folded once.
  late final String searchText =
      '$label ${secondary ?? ''} ${badge ?? ''}'.toLowerCase();
}

/// A field that opens a searchable list instead of a dropdown menu.
///
/// Drawn as the app's own input — the outline, radius and insets all come from
/// [ThemeData.inputDecorationTheme], so it sits in a form beside an
/// `AppTextField` as the same kind of object. What it replaces, a bare
/// [DropdownButton] under a hand-drawn 1px rule, matched nothing else in the
/// app.
///
/// **The reason it exists is [optionsBuilder].** Material's `DropdownButton`
/// keeps every item mounted in an `IndexedStack` to render the one line on the
/// button, and its menu is a non-lazy `ListView` that has to build every row
/// *before* the selected one to honour its initial scroll offset. On a relay
/// channel with several hundred image models that is a third of a second of
/// frozen UI per tap, and it grows with the list. Here the options are built
/// only when the picker opens, and the picker itself is a `ListView.builder`
/// with a fixed extent, so opening costs the same whether the channel serves
/// ten models or two thousand.
class SearchablePickerField<T> extends StatelessWidget {
  const SearchablePickerField({
    super.key,
    required this.selected,
    required this.optionsBuilder,
    required this.onChanged,
    required this.hint,
    required this.searchHint,
    this.dialogTitle,
    this.dialogIcon,
    this.enabled = true,
  });

  /// The current selection, already resolved by the caller. `null` draws
  /// [hint] in the outline colour.
  ///
  /// Resolved rather than looked up from [optionsBuilder] so that a build of
  /// this field never touches the full list.
  final PickerOption<T>? selected;

  /// Builds the rows to choose from. Called when the picker opens, never
  /// during a build of this field.
  final ValueGetter<List<PickerOption<T>>> optionsBuilder;

  final ValueChanged<T> onChanged;

  /// Shown in place of a value when nothing is selected.
  final String hint;

  /// Placeholder for the picker's search field.
  final String searchHint;

  /// Heading for the picker. Falls back to [hint], which reads as an
  /// instruction ("Select a model") and so makes a serviceable title.
  final String? dialogTitle;
  final IconData? dialogIcon;

  final bool enabled;

  Future<void> _open(BuildContext context) async {
    final options = optionsBuilder();
    if (options.isEmpty) return;

    final picked = await showSearchablePicker<T>(
      context: context,
      title: dialogTitle ?? hint,
      icon: dialogIcon,
      searchHint: searchHint,
      options: options,
      selected: selected?.value,
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final value = selected;

    // bodySmall, matching the dense config panels these sit in and the
    // dropdowns they replace.
    final valueStyle = textTheme.bodySmall?.copyWith(
      color: enabled ? colorScheme.onSurface : colorScheme.onSurface.withValues(alpha: AppAlpha.disabled),
    );

    return InkWell(
      onTap: enabled ? () => _open(context) : null,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: InputDecorator(
        // Border, radius and insets are the theme's; only the trailing glyph
        // is this widget's own.
        decoration: InputDecoration(
          enabled: enabled,
          suffixIcon: Icon(
            Icons.unfold_more,
            size: AppSize.iconSm,
            color: enabled ? colorScheme.outline : colorScheme.outline.withValues(alpha: AppAlpha.disabled),
          ),
          suffixIconConstraints: const BoxConstraints(minWidth: 28, minHeight: 0),
        ),
        // The label sits above this field, drawn by the caller, so there is
        // never a floating one to make room for.
        isEmpty: false,
        child: value == null
            ? Text(hint, style: valueStyle?.copyWith(color: colorScheme.outline), overflow: TextOverflow.ellipsis)
            : Row(
                children: [
                  if (value.badge != null) ...[
                    _PickerBadge(label: value.badge!, color: value.badgeColor),
                    const SizedBox(width: 8),
                  ],
                  Expanded(child: Text(value.label, style: valueStyle, overflow: TextOverflow.ellipsis)),
                ],
              ),
      ),
    );
  }
}

/// Opens the picker and returns the chosen value, or `null` if dismissed.
///
/// Exposed separately from [SearchablePickerField] for call sites whose
/// trigger is something other than a field — a toolbar button, a menu entry.
Future<T?> showSearchablePicker<T>({
  required BuildContext context,
  required String title,
  required String searchHint,
  required List<PickerOption<T>> options,
  T? selected,
  IconData? icon,
}) {
  return showDialog<T>(
    context: context,
    builder: (_) => _SearchablePickerDialog<T>(
      title: title,
      icon: icon,
      searchHint: searchHint,
      options: options,
      selected: selected,
    ),
  );
}

/// Row heights, fixed so the list can be given an `itemExtent`.
///
/// That is not a cosmetic choice. Without one, a `ListView` must lay out every
/// row from the top to work out where row 400 starts, which is the cost this
/// whole widget exists to remove — jumping to the selected row would put it
/// straight back.
const double _rowExtentSingle = 40;
const double _rowExtentDouble = 54;

class _SearchablePickerDialog<T> extends StatefulWidget {
  const _SearchablePickerDialog({
    required this.title,
    required this.searchHint,
    required this.options,
    required this.selected,
    this.icon,
  });

  final String title;
  final String searchHint;
  final List<PickerOption<T>> options;
  final T? selected;
  final IconData? icon;

  @override
  State<_SearchablePickerDialog<T>> createState() => _SearchablePickerDialogState<T>();
}

class _SearchablePickerDialogState<T> extends State<_SearchablePickerDialog<T>> {
  final TextEditingController _searchCtrl = TextEditingController();
  late ScrollController _scrollCtrl;
  late List<PickerOption<T>> _filtered;
  late final double _rowExtent;

  /// The query the current [_filtered] was computed from.
  ///
  /// Kept because a [TextEditingController] notifies on **selection** changes
  /// as well as text ones, and the search field autofocuses — so the caret
  /// landing in an empty field fires the listener before the user has typed
  /// anything. Refiltering on that is harmless; the `jumpTo(0)` below is not,
  /// and it was throwing away the scroll to the selected row every time the
  /// picker opened.
  String _query = '';

  @override
  void initState() {
    super.initState();
    _filtered = widget.options;
    _rowExtent = widget.options.any((o) => o.secondary != null && o.secondary!.isNotEmpty)
        ? _rowExtentDouble
        : _rowExtentSingle;

    // Open with the current selection in view. A multiplication rather than a
    // walk, which is the point of the fixed extent above; the ScrollPosition
    // clamps an offset past the end for us.
    final index = widget.options.indexWhere((o) => o.value == widget.selected);
    _scrollCtrl = ScrollController(
      initialScrollOffset: index <= 0 ? 0 : (index * _rowExtent - _rowExtent * 2).clamp(0, double.infinity),
    );
    _searchCtrl.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query == _query) return;
    _query = query;

    setState(() {
      _filtered = query.isEmpty
          ? widget.options
          : widget.options.where((o) => o.searchText.contains(query)).toList();
    });
    // A narrowed list is a new list; leaving the viewport where it was would
    // show the user its middle.
    if (_scrollCtrl.hasClients && _scrollCtrl.offset > 0) _scrollCtrl.jumpTo(0);
  }

  void _submitFirst() {
    if (_filtered.isNotEmpty) Navigator.of(context).pop(_filtered.first.value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final media = MediaQuery.sizeOf(context);

    // Tall enough for the whole list where the list is short, and no taller.
    // Measured off the *unfiltered* count on purpose: a height that tracked
    // what is currently on screen would resize the dialog under the pointer on
    // every keystroke, which is worse than a little empty space.
    // search field + its gap + the list's bottom inset + the heading block
    // (icon plate, title, subtitle, rule).
    const chrome = AppSize.control + 8 + 12 + 88;
    final desired = widget.options.length * _rowExtent + chrome;

    return AppDialog(
      icon: widget.icon,
      title: widget.title,
      subtitle: l10n.pickerMatchCount(_filtered.length),
      maxWidth: media.width.clamp(280.0, 480.0),
      maxHeight: desired.clamp(240.0, media.height.clamp(280.0, 560.0)),
      // The list reaches the dialog's edges; the search field brings its own
      // inset.
      contentPadding: EdgeInsets.zero,
      // Committing happens on tap, so there is no footer to dismiss from.
      onClose: () => Navigator.of(context).pop(),
      content: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: SizedBox(
              height: AppSize.control,
              child: AppSearchField(
                controller: _searchCtrl,
                hint: widget.searchHint,
                autofocus: true,
                onSubmitted: (_) => _submitFirst(),
              ),
            ),
          ),
          Expanded(
            child: _filtered.isEmpty
                ? _EmptyState(label: l10n.pickerNoMatches)
                : Scrollbar(
                    controller: _scrollCtrl,
                    child: ListView.builder(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      itemExtent: _rowExtent,
                      itemCount: _filtered.length,
                      itemBuilder: (context, i) {
                        final option = _filtered[i];
                        return _PickerRow<T>(
                          option: option,
                          selected: option.value == widget.selected,
                          onTap: () => Navigator.of(context).pop(option.value),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _PickerRow<T> extends StatelessWidget {
  const _PickerRow({required this.option, required this.selected, required this.onTap});

  final PickerOption<T> option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final secondary = option.secondary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.control),
          child: Ink(
            decoration: BoxDecoration(
              // The accent ladder: a selected thing is a wash with a ring, and
              // its label is the accent's own readable tone. See AppAccent.
              color: selected ? colorScheme.accentTint : null,
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: selected ? Border.all(color: colorScheme.accentRing) : null,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  if (option.badge != null) ...[
                    _PickerBadge(label: option.badge!, color: option.badgeColor),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          option.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(
                            color: selected ? colorScheme.onAccentTint : colorScheme.onSurface,
                            fontWeight: selected ? FontWeight.bold : null,
                          ),
                        ),
                        if (secondary != null && secondary.isNotEmpty)
                          Text(
                            secondary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            // An identifier, not prose — mono so it reads as
                            // the thing you would paste into a config.
                            style: textTheme.labelSmall?.mono.copyWith(color: colorScheme.outline),
                          ),
                      ],
                    ),
                  ),
                  if (selected) ...[
                    const SizedBox(width: 8),
                    Icon(Icons.check, size: AppSize.iconSm, color: colorScheme.onAccentTint),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The channel tag ahead of a name. Same tint/ring pair as `ModelTagChip`,
/// which does the same job for a model's kind.
class _PickerBadge extends StatelessWidget {
  const _PickerBadge({required this.label, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    // The channel's own colour when it has one. Deliberately not the theme
    // accent: this is an identity, and two channels have to stay tellable
    // apart when the user changes seed.
    final tint = color ?? Theme.of(context).colorScheme.outline;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: AppAlpha.tint),
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: tint.withValues(alpha: AppAlpha.ring)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: tint,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off_outlined, size: 32, color: colorScheme.outlineVariant),
          const SizedBox(height: 10),
          Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.outline)),
        ],
      ),
    );
  }
}
