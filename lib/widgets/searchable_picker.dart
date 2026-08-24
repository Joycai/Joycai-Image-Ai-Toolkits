import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/design_tokens.dart';
import '../l10n/app_localizations.dart';
import 'app_dialog.dart';
import 'app_empty_state.dart';
import 'app_search_field.dart';
import 'models/channel_avatar.dart';
import 'models/model_tag_chip.dart';

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
/// with a uniform extent, so opening costs the same whether the channel serves
/// ten models or two thousand.
/// How a [SearchablePickerField] draws the badge of whatever is selected.
///
/// The design gives a channel three forms, and the field's width is what
/// decides between them.
enum PickerBadge {
  /// The tag written out, capped at a third of the field. Where there is room
  /// for the word and the word is worth reading.
  chip,

  /// A 20px disc carrying the tag's first letter. For a field that is
  /// *restating* which channel this is rather than offering a choice among
  /// several — the model editor's channel field.
  avatar,

  /// An 8px dot in the tag's colour and nothing else, as `A1 16a` draws the
  /// workbench's channel field. The two pickers share one row at ~150px each;
  /// a chip there had its tag ellipsized down to an empty coloured box, which
  /// says less than a dot and takes six times the width to say it.
  dot,
}

class SearchablePickerField<T> extends StatefulWidget {
  const SearchablePickerField({
    super.key,
    required this.selected,
    required this.optionsBuilder,
    required this.onChanged,
    required this.hint,
    required this.searchHint,
    this.dialogTitle,
    this.dialogIcon,
    this.decoration = const InputDecoration(),
    this.enabled = true,
    this.badgeStyle = PickerBadge.chip,
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

  /// The field's decoration, before this widget adds its own trailing glyph
  /// and enabled state.
  ///
  /// Bare by default, which is to say whatever
  /// [ThemeData.inputDecorationTheme] gives every other input in the app —
  /// the workbench's two pickers draw their captions above themselves and
  /// want nothing more. Call sites that carry a `labelText` (or a prefix
  /// glyph, or a panel-specific border) pass one instead of this widget
  /// growing a parameter per slot of [InputDecoration].
  final InputDecoration decoration;

  final bool enabled;

  /// How the selected option's badge is drawn. See [PickerBadge].
  ///
  /// Applies to this field only — the rows inside the picker it opens are
  /// chips whatever this says, because there the tag is what the user is
  /// reading the row for.
  final PickerBadge badgeStyle;

  @override
  State<SearchablePickerField<T>> createState() => _SearchablePickerFieldState<T>();
}

class _SearchablePickerFieldState<T> extends State<SearchablePickerField<T>> {
  /// Held only so they can be handed to [InputDecorator], which draws the
  /// theme's `focusedBorder` and hover fill from them and otherwise assumes
  /// both are false. [InkWell] already makes this reachable and activatable by
  /// keyboard; without these it was the one input in the app where tabbing
  /// onto it looked the same as tabbing past it.
  bool _focused = false;
  bool _hovered = false;

  Future<void> _open() async {
    final options = widget.optionsBuilder();
    if (options.isEmpty) return;

    final picked = await showSearchablePicker<T>(
      context: context,
      title: widget.dialogTitle ?? widget.hint,
      icon: widget.dialogIcon,
      searchHint: widget.searchHint,
      options: options,
      selected: widget.selected?.value,
    );
    // The dialog can outlive this element: the workbench moves its config
    // panel into a drawer when the window crosses the tablet breakpoint, which
    // unmounts us with the picker still up. [SearchablePickerField.onChanged]
    // reaches for the panel's Provider, so calling it then throws on a
    // deactivated ancestor — the `!mounted` bail `DropdownButton` did for us.
    if (picked != null && mounted) widget.onChanged(picked.value);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final value = widget.selected;
    final enabled = widget.enabled;

    // bodySmall, matching the dense config panels these sit in and the
    // dropdowns they replace.
    final valueStyle = textTheme.bodySmall?.copyWith(
      color: enabled ? colorScheme.onSurface : colorScheme.onSurface.withValues(alpha: AppAlpha.disabled),
    );
    // Disabled *and* empty is the common state of these fields — they are
    // empty precisely when there is nothing to choose from — so the hint has
    // to dim with the border and the glyph instead of keeping its enabled tone.
    final outline =
        enabled ? colorScheme.outline : colorScheme.outline.withValues(alpha: AppAlpha.disabled);

    return Semantics(
      button: true,
      enabled: enabled,
      value: value?.label ?? widget.hint,
      child: InkWell(
        onTap: enabled ? _open : null,
        onFocusChange: (v) => setState(() => _focused = v),
        onHover: (v) => setState(() => _hovered = v),
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: InputDecorator(
          // Border, radius and insets are the caller's decoration or, by
          // default, the theme's; only the trailing glyph is this widget's own.
          decoration: widget.decoration.copyWith(
            enabled: enabled,
            // expand_more, not unfold_more: the design draws a single
            // downward chevron on every select-like field, and this is the one
            // widget behind all of them.
            suffixIcon: Icon(Icons.expand_more, size: AppSize.iconSm, color: outline),
            suffixIconConstraints: const BoxConstraints(minWidth: 28, minHeight: 0),
          ),
          isFocused: _focused,
          isHovering: _hovered,
          // Never "empty", even with nothing selected: this field always draws
          // something in its content area — the value or [hint] — so a
          // decoration that carries a `labelText` must float it rather than
          // lay it over the top.
          isEmpty: false,
          child: value == null
              ? Text(widget.hint, style: valueStyle?.copyWith(color: outline), overflow: TextOverflow.ellipsis)
              : LayoutBuilder(
                  builder: (context, constraints) => Row(
                    children: [
                      if (value.badge != null) ...[
                        if (widget.badgeStyle == PickerBadge.dot)
                          // No cap needed: a dot is a dot.
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: value.badgeColor ?? colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                          )
                        else if (widget.badgeStyle == PickerBadge.avatar)
                          // Fixed-size, so the free-text cap below does not
                          // apply: a disc shows one letter no matter how long
                          // the tag is.
                          TagAvatar(value.badge!, color: value.badgeColor, size: 20)
                        else
                          ConstrainedBox(
                            // A third of the field, at most. The channel tag is
                            // free text with no length limit, and unbounded it
                            // took the whole row at mobile width and left
                            // `Expanded` nothing — a RenderFlex overflow with
                            // the name ellipsized away to start with.
                            constraints: BoxConstraints(maxWidth: constraints.maxWidth / 3),
                            child: ModelTagChip(value.badge!, color: value.badgeColor, uppercase: false),
                          ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(child: Text(value.label, style: valueStyle, overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

/// What a picker returned, wrapping the chosen value.
///
/// A bare `T?` cannot say whether the user chose or dismissed once `T` is
/// itself nullable, and one of these pickers has `null` as a real answer: the
/// knowledge-base sub-agent's "follow the main model" row. Without the wrapper
/// that choice is indistinguishable from pressing Escape, and the field
/// silently snaps back to what it was showing.
class PickerResult<T> {
  const PickerResult(this.value);

  final T value;
}

/// Opens the picker and returns the choice, or `null` if it was dismissed.
///
/// Exposed separately from [SearchablePickerField] for call sites whose
/// trigger is something other than a field — a toolbar button, a menu entry.
Future<PickerResult<T>?> showSearchablePicker<T>({
  required BuildContext context,
  required String title,
  required String searchHint,
  required List<PickerOption<T>> options,
  T? selected,
  IconData? icon,
}) {
  return showDialog<PickerResult<T>>(
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

/// The vertical space a row spends on anything but type: [_PickerRow]'s 2px
/// bottom gap, its 6px symmetric inset, and the 1px ring the *selected* row
/// draws top and bottom.
///
/// The ring is counted for every row because `itemExtent` is uniform — the
/// extent has to fit the tallest row the list can produce, and leaving those
/// two pixels out overflowed the selected row alone, at every text scale.
const double _rowChrome = 2 + 12 + 2;

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
  late final bool _hasSecondary;
  late final bool _hasBadge;

  /// Every row's height, and so the list's `itemExtent`.
  ///
  /// Measured from the real text metrics rather than fixed, because
  /// `itemExtent` hands the row a **tight** box: a constant sized at 1.0 text
  /// scale stripes every visible row at once when the OS text-size slider
  /// moves, and a fixed-extent list has no way to absorb it. Zero until the
  /// first [didChangeDependencies], which always runs before the first build.
  double _rowExtent = 0;

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
    _hasSecondary = widget.options.any((o) => o.secondary != null && o.secondary!.isNotEmpty);
    _hasBadge = widget.options.any((o) => o.badge != null && o.badge!.isNotEmpty);
    _searchCtrl.addListener(_onQueryChanged);
  }

  /// Lays out one line in each of the roles [_PickerRow] uses and adds the
  /// chrome around them.
  ///
  /// Measured rather than derived from a multiplier because the fonts are the
  /// user's: the settings screen can swap the whole app onto HarmonyOS Sans or
  /// MiSans, whose line metrics are not the default's. A [TextPainter] answers
  /// for whatever is actually installed, once per open.
  double _measureRowExtent() {
    final textTheme = Theme.of(context).textTheme;
    final scaler = MediaQuery.textScalerOf(context);

    double lineHeight(TextStyle? style) => (TextPainter(
          // Ascender and descender both, so the measurement is the font's full
          // line box rather than the tallest glyph in some particular name.
          text: TextSpan(text: 'Ag', style: style),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
          maxLines: 1,
        )..layout())
            .height;

    final text = lineHeight(textTheme.bodySmall) +
        (_hasSecondary ? lineHeight(textTheme.labelSmall?.mono) : 0);
    // A chip is taller than the single line it sits beside — its own padding
    // and ring on top of `labelSmall` — so a row of channels, which carries a
    // tag and no second line, is sized by the chip rather than by its name.
    // Left out, the chip was silently squeezed instead of the row growing.
    final badge =
        _hasBadge ? lineHeight(textTheme.labelSmall) + ModelTagChip.chromeHeight : 0.0;

    return (math.max(text, badge) + _rowChrome).ceilToDouble();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final extent = _measureRowExtent();
    if (extent == _rowExtent) return;

    final isFirstMeasure = _rowExtent == 0;
    _rowExtent = extent;
    // Only the first measurement seeds the scroll offset. A later one means
    // the text scale changed under an open picker, which should re-lay the
    // rows but not yank the viewport back to where it opened.
    if (!isFirstMeasure) return;

    // Open with the current selection in view. A multiplication rather than a
    // walk, which is the point of the uniform extent; the ScrollPosition
    // clamps an offset past the end for us.
    final index = widget.options.indexWhere((o) => o.value == widget.selected);
    _scrollCtrl = ScrollController(
      initialScrollOffset:
          index <= 0 ? 0.0 : (index * _rowExtent - _rowExtent * 2).clamp(0.0, double.infinity),
    );
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
    if (_scrollCtrl.hasClients) _scrollCtrl.jumpTo(0);
  }

  /// Enter takes the top match — which only means anything once a query has
  /// narrowed the list.
  ///
  /// With an empty query `_filtered` is still every option, so submitting its
  /// first entry would replace the user's selection with an unrelated model
  /// and persist it. The search field autofocuses, so that was one reflexive
  /// keypress away on every open.
  void _submitFirst() {
    if (_query.isEmpty || _filtered.isEmpty) return;
    Navigator.of(context).pop(PickerResult<T>(_filtered.first.value));
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
      // inset. Full-bleed means the rows' ink and the selected row's filled
      // box would paint square across the dialog's rounded corners, so the
      // body has to be clipped to them.
      contentPadding: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
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
            // The list stays mounted with nothing in it and the empty state
            // lies over the top, rather than the two swapping places.
            // Swapping disposed the ScrollPosition, so `hasClients` went false
            // and the reset in `_onQueryChanged` was skipped; the list that
            // remounted on the next matching keystroke then re-applied
            // `initialScrollOffset` and opened at the bottom of the results.
            child: Stack(
              children: [
                Scrollbar(
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
                        onTap: () => Navigator.of(context).pop(PickerResult<T>(option.value)),
                      );
                    },
                  ),
                ),
                if (_filtered.isEmpty)
                  Positioned.fill(
                    child: AppEmptyState(
                      icon: Icons.search_off_outlined,
                      label: l10n.pickerNoMatches,
                      compact: true,
                    ),
                  ),
              ],
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
                    ConstrainedBox(
                      // Bounded for the same reason as the collapsed field's:
                      // a long channel tag would otherwise take the row and
                      // leave `Expanded` nothing to put the name in.
                      constraints: const BoxConstraints(maxWidth: 120),
                      child: ModelTagChip(option.badge!, color: option.badgeColor, uppercase: false),
                    ),
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
                            fontWeight: selected ? FontWeight.w600 : null,
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
