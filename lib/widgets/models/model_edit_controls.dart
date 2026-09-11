import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_semantic_colors.dart';
import '../../core/app_theme.dart';
import '../../core/design_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../app_switch.dart';

/// The pieces the model editor (design D1c) is built from.
///
/// Private to the editor in spirit: the fields, grids and notices here are
/// sized and coloured for that one form, on the two grounds it renders on —
/// the 920 dialog's panel and the phone page's column.

/// Geometry that differs between the desktop dialog and the phone page.
///
/// D1c draws the same form twice: fields at 32 in the dialog and 44 on the
/// phone, the choice grids at 32 / 40, switch rows at 40 / 48. Carried down
/// the tree rather than passed through every builder so a field cannot be
/// built at the other form's height by mistake.
@immutable
class ModelEditMetrics {
  const ModelEditMetrics._({
    required this.phone,
    required this.onColumnGround,
    required this.fieldHeight,
    required this.gridHeight,
    required this.toggleRowHeight,
    required this.inlineActionHeight,
  });

  /// The dialog (`1a`): a panel ground, fields and cards on the column colour.
  static const desktop = ModelEditMetrics._(
    phone: false,
    onColumnGround: false,
    fieldHeight: AppSize.control,
    gridHeight: AppSize.control,
    toggleRowHeight: AppSize.large,
    inlineActionHeight: AppSize.compact,
  );

  /// The phone page (`1e`): a column ground, fields and cards on the panel.
  static const phoneForm = ModelEditMetrics._(
    phone: true,
    onColumnGround: true,
    fieldHeight: AppSize.touch,
    gridHeight: AppSize.large,
    // `1e` 「能力卡行 48」.
    toggleRowHeight: AppSize.touch + AppSpace.s4,
    inlineActionHeight: AppSize.control,
  );

  /// A dialog on a phone (the add-model dialog): touch heights on a panel.
  static const phoneDialog = ModelEditMetrics._(
    phone: true,
    onColumnGround: false,
    fieldHeight: AppSize.touch,
    gridHeight: AppSize.large,
    toggleRowHeight: AppSize.touch + AppSpace.s4,
    inlineActionHeight: AppSize.control,
  );

  /// Touch geometry, and the phone's own affordances (a bottom sheet in
  /// place of a menu).
  final bool phone;

  /// Whether the form sits on the column colour rather than on a panel.
  final bool onColumnGround;
  final double fieldHeight;
  final double gridHeight;
  final double toggleRowHeight;

  /// 「改回自动」: compact under a dialog field, a touch step taller on phone.
  final double inlineActionHeight;

  /// What a field and a card fill with: a step off whatever they sit on.
  Color fill(ColorScheme scheme) => onColumnGround ? scheme.surface : scheme.surfaceContainerLow;

  static ModelEditMetrics of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_MetricsScope>()?.metrics ?? desktop;
}

class _MetricsScope extends InheritedWidget {
  const _MetricsScope({required this.metrics, required super.child});

  final ModelEditMetrics metrics;

  @override
  bool updateShouldNotify(_MetricsScope oldWidget) => metrics != oldWidget.metrics;
}

/// Sets the editor's field skin and [ModelEditMetrics] for everything below.
///
/// The fill is the form's own (`D1c`: 「字段填充与卡容器 = col」), which is why
/// this is not `FilledFieldScope`: that one fills with the lowest surface for
/// the older D2 forms.
class ModelEditFieldScope extends StatelessWidget {
  const ModelEditFieldScope({super.key, required this.metrics, required this.child});

  final ModelEditMetrics metrics;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        inputDecorationTheme: theme.inputDecorationTheme.copyWith(
          filled: true,
          fillColor: metrics.fill(theme.colorScheme),
          prefixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 0),
        ),
      ),
      child: _MetricsScope(metrics: metrics, child: child),
    );
  }
}

/// A kind's glyph — the one the model card's plate carries (D1a).
IconData modelKindIcon(String tag) {
  switch (tag) {
    case 'image':
      return Icons.image_outlined;
    case 'video':
      return Icons.movie_outlined;
    case 'multimodal':
      return Icons.apps;
    default:
      return Icons.forum_outlined;
  }
}

/// A token count grouped in threes with a narrow space, as `1d` sets
/// 「200 000 tokens」.
String formatGroupedTokens(int tokens) {
  final digits = tokens.toString();
  final buffer = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// A single-line input at the form's height, with an optional leading glyph.
class ModelEditTextField extends StatelessWidget {
  const ModelEditTextField({
    super.key,
    required this.controller,
    this.onChanged,
    this.icon,
    this.hint,
    this.mono = false,
    this.error = false,
    this.autofocus = false,
    this.keyboardType,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final IconData? icon;
  final String? hint;

  /// Identifiers and numbers the wire sees verbatim.
  final bool mono;

  /// `D1c` 「校验失败 = err 描边」.
  final bool error;
  final bool autofocus;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final metrics = ModelEditMetrics.of(context);
    final base = theme.textTheme.bodyMedium;
    final errorBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.control),
      borderSide: BorderSide(color: scheme.error),
    );

    return TextField(
      controller: controller,
      onChanged: onChanged,
      autofocus: autofocus,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style: mono ? base?.mono : base,
      textAlignVertical: TextAlignVertical.center,
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        constraints: BoxConstraints.tightFor(height: metrics.fieldHeight),
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.s10),
        prefixIcon: icon == null
            ? null
            : Icon(icon, size: AppSize.iconMd, color: scheme.onSurfaceVariant),
        enabledBorder: error ? errorBorder : null,
        focusedBorder: error ? errorBorder : null,
      ),
    );
  }
}

/// One cell of a [ModelEditChoiceGrid].
@immutable
class ModelEditChoice<T> {
  const ModelEditChoice({required this.value, required this.label, this.dotColor});

  final T value;
  final String label;

  /// An identity colour drawn as a 6px dot before the label. It never takes
  /// the accent, selected or not — the kind's hue is the kind's.
  final Color? dotColor;
}

/// Equal cells in one row: the kind picker and the context-window modes.
///
/// Selected is the accent's wash with a `primary` stroke and the deep ink at
/// 600; a dot keeps its identity colour either way.
class ModelEditChoiceGrid<T> extends StatelessWidget {
  const ModelEditChoiceGrid({
    super.key,
    required this.choices,
    required this.value,
    required this.onChanged,
  });

  final List<ModelEditChoice<T>> choices;
  final T? value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (int i = 0; i < choices.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpace.s6),
          Expanded(
            child: _ChoiceCell<T>(
              choice: choices[i],
              selected: choices[i].value == value,
              onTap: () => onChanged(choices[i].value),
            ),
          ),
        ],
      ],
    );
  }
}

class _ChoiceCell<T> extends StatelessWidget {
  const _ChoiceCell({required this.choice, required this.selected, required this.onTap});

  final ModelEditChoice<T> choice;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final metrics = ModelEditMetrics.of(context);
    final radius = BorderRadius.circular(AppRadius.control);

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: AnimatedContainer(
            duration: AppMotion.durationOf(context, AppMotion.hover),
            curve: AppMotion.quick,
            height: metrics.gridHeight,
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.s6),
            decoration: BoxDecoration(
              color: selected ? scheme.accentTint : metrics.fill(scheme),
              borderRadius: radius,
              border: Border.all(color: selected ? scheme.primary : scheme.outlineVariant),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (choice.dotColor != null) ...[
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(color: choice.dotColor, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: AppSpace.s6),
                ],
                Flexible(
                  child: Text(
                    choice.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected ? scheme.onAccentTint : scheme.onSurface,
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
}

/// A wrap of 28px capsules — the reasoning-effort ladder.
///
/// Disabled, the whole row goes to the muted ink and stops taking taps but
/// keeps its selection (`1a`: 「不支持时整段 ink3 且保留」).
class ModelEditPillChips<T> extends StatelessWidget {
  const ModelEditPillChips({
    super.key,
    required this.choices,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final List<ModelEditChoice<T>> choices;
  final T? value;
  final ValueChanged<T> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radius = BorderRadius.circular(AppRadius.pill);

    return Wrap(
      spacing: AppSpace.s6,
      runSpacing: AppSpace.s6,
      children: [
        for (final choice in choices)
          Builder(builder: (context) {
            final selected = choice.value == value;
            final Color border;
            final Color ink;
            if (!enabled) {
              border = selected ? scheme.outline : scheme.outlineVariant;
              ink = scheme.outline;
            } else {
              border = selected ? scheme.primary : scheme.outlineVariant;
              ink = selected ? scheme.onAccentTint : scheme.onSurfaceVariant;
            }
            return Semantics(
              button: true,
              selected: selected,
              enabled: enabled,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: radius,
                  onTap: enabled ? () => onChanged(choice.value) : null,
                  child: AnimatedContainer(
                    duration: AppMotion.durationOf(context, AppMotion.hover),
                    curve: AppMotion.quick,
                    height: AppSize.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected && enabled ? scheme.accentTint : Colors.transparent,
                      borderRadius: radius,
                      border: Border.all(color: border),
                    ),
                    child: Text(
                      choice.label,
                      maxLines: 1,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                        color: ink,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }
}

/// The form's card: the column colour, a hairline, r10.
class ModelEditCard extends StatelessWidget {
  const ModelEditCard({super.key, required this.child, this.padding = const EdgeInsets.all(AppSpace.s10)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: ModelEditMetrics.of(context).fill(scheme),
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: child,
    );
  }
}

/// A switch row inside a [ModelEditCard].
///
/// [description] is drawn under the title; [tooltip] instead keeps a row at
/// its 40px (`1a`'s capability rows carry only the title) without dropping
/// the explanation the row used to print.
class ModelEditToggleRow extends StatelessWidget {
  const ModelEditToggleRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.description,
    this.tooltip,
    this.emphasized = false,
    this.dimmed = false,
  });

  final String title;
  final String? description;
  final String? tooltip;
  final bool value;
  final ValueChanged<bool>? onChanged;

  /// 600 rather than 500 — a card holding a single setting (`1a` 代理行为).
  final bool emphasized;

  /// Inert because something else overrides it; the value is kept.
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final metrics = ModelEditMetrics.of(context);

    Widget titleText = Text(
      title,
      style: theme.textTheme.bodyMedium?.copyWith(
        fontWeight: emphasized ? FontWeight.w600 : FontWeight.w500,
      ),
    );
    if (tooltip != null) titleText = Tooltip(message: tooltip!, child: titleText);

    return AnimatedOpacity(
      opacity: dimmed ? AppAlpha.edge : 1,
      duration: AppMotion.durationOf(context, AppMotion.state),
      curve: AppMotion.enter,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: description == null ? metrics.toggleRowHeight : 0),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  titleText,
                  if (description != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      description!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w400,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpace.s10),
            AppSwitch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

/// How loud a [ModelEditNotice] is. None of these is the accent.
enum ModelEditTone {
  /// A fact worth knowing: unrecognised id, streaming not used.
  info,

  /// Likely to go wrong, still allowed: images through a chat format.
  warning,

  /// Nothing will run: the channel has no interface for the kind.
  error,
}

/// A notice strip under a section (`1b` ③ ④, `1d`): opaque status container,
/// r6, a 14px glyph and 11px copy in the container's ink.
class ModelEditNotice extends StatelessWidget {
  const ModelEditNotice({super.key, required this.tone, required this.text, this.icon});

  final ModelEditTone tone;
  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantic = context.semantic;
    final (Color bg, Color ink, IconData glyph) = switch (tone) {
      ModelEditTone.info => (semantic.infoContainer, semantic.onInfoContainer, Icons.info_outline),
      ModelEditTone.warning => (
          semantic.warningContainer,
          semantic.onWarningContainer,
          Icons.warning_amber_rounded
        ),
      ModelEditTone.error => (scheme.errorContainer, scheme.onErrorContainer, Icons.error_outline),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10, vertical: 7),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.sm)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon ?? glyph, size: AppSize.iconSm, color: ink),
          ),
          const SizedBox(width: AppSpace.s6),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w400, color: ink),
            ),
          ),
        ],
      ),
    );
  }
}

/// A helper sentence: 11px, `onSurfaceVariant` — never `outline`, which makes
/// an explanation read as disabled (`D1c` 颜色角色).
class ModelEditHelperText extends StatelessWidget {
  const ModelEditHelperText(this.text, {super.key, this.muted = false});

  final String text;

  /// The muted ink, only for copy belonging to a greyed-out section.
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.labelSmall?.copyWith(
        fontWeight: FontWeight.w400,
        color: muted ? theme.colorScheme.outline : theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// The indented parameter summary under the request method: a 2px hairline
/// guide, 12px in, 「Parameters」 and a wrap of r4 mono chips.
class ModelEditParamBlock extends StatelessWidget {
  const ModelEditParamBlock({super.key, required this.items});

  /// In the surface's fixed order. Empty prints the "no specific parameters"
  /// sentence instead.
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final chipStyle = theme.textTheme.labelSmall?.mono.copyWith(
      fontWeight: FontWeight.w400,
      color: scheme.onSurface,
    );

    return Padding(
      padding: const EdgeInsetsDirectional.only(start: AppSpace.s6),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsetsDirectional.only(start: 12, top: 2, bottom: 2),
        decoration: BoxDecoration(
          border: BorderDirectional(start: BorderSide(color: scheme.outlineVariant, width: 2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ModelEditHelperText(l10n.protocolParamsLabel),
            const SizedBox(height: AppSpace.s4),
            if (items.isEmpty)
              ModelEditHelperText(l10n.protocolParamsNone)
            else
              Wrap(
                spacing: AppSpace.s4,
                runSpacing: AppSpace.s4,
                children: [
                  for (final item in items)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s6, vertical: 1),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                      ),
                      child: Text(item, style: chipStyle),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// 「改回自动」: right-aligned, compact, deep ink, directly under the pinned
/// field (`1b` ②).
class ModelEditBackToAuto extends StatelessWidget {
  const ModelEditBackToAuto({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final metrics = ModelEditMetrics.of(context);
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: TextButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.undo, size: AppSize.iconSm),
        label: Text(AppLocalizations.of(context)!.protocolBackToAuto),
        style: TextButton.styleFrom(
          minimumSize: Size(0, metrics.inlineActionHeight),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.s6),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}

/// A save-blocking problem under the field it belongs to (`1d` 「保存校验」):
/// r10, the error stroke, a glyph, a 600 title in the error ink and an
/// optional 11px explanation.
class ModelEditValidationNote extends StatelessWidget {
  const ModelEditValidationNote({super.key, required this.title, this.description});

  final String title;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.s10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: scheme.error),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.error_outline, size: AppSize.iconSm, color: scheme.error),
          ),
          const SizedBox(width: AppSpace.s6),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: scheme.onErrorContainer,
                  ),
                ),
                if (description != null) ...[
                  const SizedBox(height: 2),
                  ModelEditHelperText(description!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The request-method field when the channel has no interface for the kind
/// (`1b` ④): the error stroke, `block` and 「不可用」, nothing to open.
class ModelEditUnavailableField extends StatelessWidget {
  const ModelEditUnavailableField({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final metrics = ModelEditMetrics.of(context);

    return Container(
      height: metrics.fieldHeight,
      padding: EdgeInsets.symmetric(horizontal: metrics.phone ? 12 : AppSpace.s10),
      decoration: BoxDecoration(
        color: metrics.fill(scheme),
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: scheme.error),
      ),
      child: Row(
        children: [
          Icon(Icons.block, size: AppSize.iconMd, color: scheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              AppLocalizations.of(context)!.protocolUnavailable,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
                color: scheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The stroke a [ModelEditMenuField] wears.
enum ModelEditFieldEmphasis { normal, accent, error }

/// One row of a [ModelEditMenuField]'s menu.
@immutable
class ModelEditMenuEntry<T> {
  const ModelEditMenuEntry({
    required this.value,
    required this.label,
    this.description,
    this.trailing,
    this.leading,
  });

  final T value;
  final String label;
  final String? description;

  /// Mono, at the row's end — an endpoint path.
  final String? trailing;
  final Widget? leading;
}

/// A select-shaped box whose closed face is arbitrary content, opening a
/// menu of [entries] — or calling [onTap] instead (the phone's bottom sheet).
///
/// Exists because the request method's closed field is two type styles in
/// one line (「Auto」 at 500, the resolution in mono) and a kind needs its
/// dot, neither of which a `DropdownButton`'s selected item can carry.
class ModelEditMenuField<T> extends StatefulWidget {
  const ModelEditMenuField({
    super.key,
    required this.child,
    this.entries = const [],
    this.selected,
    this.onSelected,
    this.onTap,
    this.leading,
    this.emphasis = ModelEditFieldEmphasis.normal,
    this.autoHeight = false,
  });

  final Widget child;
  final List<ModelEditMenuEntry<T>> entries;
  final T? selected;
  final ValueChanged<T>? onSelected;

  /// Replaces the menu.
  final VoidCallback? onTap;
  final Widget? leading;
  final ModelEditFieldEmphasis emphasis;

  /// Grows past the field height for a two-line face (`1e`).
  final bool autoHeight;

  @override
  State<ModelEditMenuField<T>> createState() => _ModelEditMenuFieldState<T>();
}

class _ModelEditMenuFieldState<T> extends State<ModelEditMenuField<T>> {
  final MenuController _controller = MenuController();

  /// The narrowest a menu gets, so an entry's description still wraps to two
  /// lines at most beside a narrow field.
  static const double _minMenuWidth = 260;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final metrics = ModelEditMetrics.of(context);
    final radius = BorderRadius.circular(AppRadius.control);
    final stroke = switch (widget.emphasis) {
      ModelEditFieldEmphasis.normal => scheme.outlineVariant,
      ModelEditFieldEmphasis.accent => scheme.primary,
      ModelEditFieldEmphasis.error => scheme.error,
    };

    Widget face(VoidCallback? onTap) => Material(
          color: metrics.fill(scheme),
          shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: stroke)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: widget.autoHeight
                  ? BoxConstraints(minHeight: metrics.fieldHeight)
                  : BoxConstraints.tightFor(height: metrics.fieldHeight - 2),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: metrics.phone ? 12 : AppSpace.s10,
                  vertical: widget.autoHeight ? AppSpace.s10 : 0,
                ),
                child: Row(
                  children: [
                    if (widget.leading != null) ...[
                      widget.leading!,
                      const SizedBox(width: 8),
                    ],
                    Expanded(child: widget.child),
                    const SizedBox(width: AppSpace.s6),
                    Icon(Icons.expand_more, size: AppSize.iconMd, color: scheme.outline),
                  ],
                ),
              ),
            ),
          ),
        );

    if (widget.onTap != null) return face(widget.onTap);

    return LayoutBuilder(builder: (context, constraints) {
      // The menu's padding (6) and each row's (10) come out of the field's
      // width, so the open menu lines up with the box it dropped from.
      final rowWidth = (constraints.maxWidth < _minMenuWidth ? _minMenuWidth : constraints.maxWidth) -
          2 * AppSpace.s6 -
          2 * AppSpace.s10;

      return MenuAnchor(
        controller: _controller,
        alignmentOffset: const Offset(0, AppSpace.s4),
        menuChildren: [
          for (final entry in widget.entries)
            MenuItemButton(
              onPressed: () => widget.onSelected?.call(entry.value),
              style: MenuItemButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10, vertical: AppSpace.s6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                backgroundColor: entry.value == widget.selected ? scheme.accentTint : null,
              ),
              child: SizedBox(
                width: rowWidth,
                child: Row(
                  children: [
                    if (entry.leading != null) ...[
                      entry.leading!,
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                              color: entry.value == widget.selected ? scheme.onAccentTint : scheme.onSurface,
                            ),
                          ),
                          if (entry.description != null)
                            Text(
                              entry.description!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w400,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (entry.trailing != null) ...[
                      const SizedBox(width: 12),
                      Text(
                        entry.trailing!,
                        style: textTheme.labelSmall?.mono.copyWith(color: scheme.outline),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
        builder: (context, controller, _) => face(() {
          controller.isOpen ? controller.close() : controller.open();
        }),
      );
    });
  }
}
