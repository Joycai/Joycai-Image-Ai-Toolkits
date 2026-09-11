import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/app_semantic_colors.dart';
import '../../core/app_theme.dart';
import '../../core/constants.dart';
import '../../core/design_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../screens/prompts/widgets/color_hue_picker.dart';
import '../app_button.dart';
import '../app_dialog.dart';
import '../app_switch.dart';
import '../app_field_size.dart';

/// The shared vocabulary of the add-channel wizard and the channel editor
/// (design `D1b`): one field, one label row, one badge, one note strip, one
/// toggle card, one identity avatar — so the two dialogs that edit the same
/// record cannot drift into two looks for it.

/// The 11/500 tracked caption in the deep ink that heads a section of a
/// channel form (`VENDORS`, `BASIC INFO`, `CONFIGURATION`).
class ChannelSectionLabel extends StatelessWidget {
  const ChannelSectionLabel(this.text, {super.key, this.trailing});

  final String text;

  /// A figure or action on the caption's row — a group's count.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.s6),
      child: Row(
        children: [
          Flexible(
            child: Text(
              // Upper-cased like AppSectionLabel: a no-op on CJK, the spec's
              // caption in the Latin locales.
              text.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    letterSpacing: AppType.trackedLabelSpacing,
                    color: colorScheme.accentText,
                  ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpace.s6),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// The line above a field: its name, an optional badge beside it, and an
/// optional action pinned to the right (`D1b 1c`: `Endpoint URL` ·
/// `Address edited` · `Restore preset value`).
class ChannelFieldLabel extends StatelessWidget {
  const ChannelFieldLabel(this.text, {super.key, this.badge, this.trailing});

  final String text;
  final Widget? badge;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      // The height of a compact text button, so a label row with a trailing
      // action and one without sit their fields at the same offset.
      constraints: const BoxConstraints(minHeight: AppSize.compact),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                if (badge != null) ...[
                  const SizedBox(width: AppSpace.s6),
                  badge!,
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpace.s6),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// A [ChannelFieldLabel] over its field, with an optional 11px note under it.
class ChannelLabelledField extends StatelessWidget {
  const ChannelLabelledField({
    super.key,
    required this.label,
    required this.child,
    this.badge,
    this.trailing,
    this.helper,
  });

  final String label;
  final Widget child;
  final Widget? badge;
  final Widget? trailing;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChannelFieldLabel(label, badge: badge, trailing: trailing),
        const SizedBox(height: AppSpace.s4),
        child,
        if (helper != null) ...[
          const SizedBox(height: AppSpace.s4),
          Text(
            helper!,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w400,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// The form field `D1b` draws everywhere: 32 high, filled with the column
/// colour, a hairline at r10, the accent stroke plus a 3px wash when focused.
///
/// Its own widget rather than `AppTextField` because the design labels fields
/// from a row *above* them (so the row can carry a badge and a restore link),
/// and because `AppTextField` reserves its focus ring inside its own box —
/// which would inset every field 3px from the label over it. Here the ring is
/// painted outside the box and takes no layout.
class ChannelField extends StatefulWidget {
  const ChannelField({
    super.key,
    required this.controller,
    this.hint,
    this.onChanged,
    this.prefixIcon,
    this.errorText,
    this.mono = false,
    this.obscurable = false,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String? hint;
  final ValueChanged<String>? onChanged;
  final IconData? prefixIcon;

  /// Shown under the field in the error ink; also turns the stroke red.
  final String? errorText;

  /// Endpoints, keys and tags are strings the wire sees verbatim.
  final bool mono;

  /// Masks the value behind a visibility toggle — the API key.
  final bool obscurable;

  final bool enabled;

  @override
  State<ChannelField> createState() => _ChannelFieldState();
}

class _ChannelFieldState extends State<ChannelField> {
  static const double _ring = 3;

  bool _focused = false;
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final base = theme.textTheme.bodyMedium ?? const TextStyle();
    final style =
        (widget.mono ? base.mono : base).copyWith(color: colorScheme.onSurface);
    final vertical = pinnedFieldInset(context, style, AppSize.control);
    final hasError = widget.errorText != null;

    OutlineInputBorder stroke(Color color) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: BorderSide(color: color),
        );

    final field = TextField(
      controller: widget.controller,
      enabled: widget.enabled,
      onChanged: widget.onChanged,
      obscureText: widget.obscurable && _obscured,
      style: style,
      textAlignVertical: TextAlignVertical.center,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: colorScheme.surfaceContainerLow,
        constraints: const BoxConstraints.tightFor(height: AppSize.control),
        hintText: widget.hint,
        hintStyle: style.copyWith(color: colorScheme.outline),
        contentPadding: EdgeInsets.fromLTRB(
          widget.prefixIcon == null ? AppSpace.s10 : 0,
          vertical,
          widget.obscurable ? 0 : AppSpace.s10,
          vertical,
        ),
        prefixIcon: widget.prefixIcon == null
            ? null
            : Icon(widget.prefixIcon,
                size: AppSize.iconMd, color: colorScheme.outline),
        prefixIconConstraints:
            const BoxConstraints(minWidth: AppSize.control, minHeight: 0),
        suffixIcon: widget.obscurable
            ? IconButton(
                icon: Icon(_obscured
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined),
                iconSize: AppSize.iconMd,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                    width: AppSize.compact, height: AppSize.compact),
                style: IconButton.styleFrom(
                  foregroundColor: colorScheme.onSurfaceVariant,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => setState(() => _obscured = !_obscured),
              )
            : null,
        suffixIconConstraints:
            const BoxConstraints(minWidth: AppSize.control, minHeight: 0),
        border: stroke(hasError ? colorScheme.error : colorScheme.outlineVariant),
        enabledBorder:
            stroke(hasError ? colorScheme.error : colorScheme.outlineVariant),
        focusedBorder: stroke(hasError ? colorScheme.error : colorScheme.primary),
        disabledBorder: stroke(
            colorScheme.outlineVariant.withValues(alpha: AppAlpha.disabled)),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onFocusChange: (value) {
            if (value != _focused) setState(() => _focused = value);
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              field,
              Positioned(
                left: -_ring,
                top: -_ring,
                right: -_ring,
                bottom: -_ring,
                child: IgnorePointer(
                  child: AnimatedContainer(
                    duration: AppMotion.durationOf(context, AppMotion.hover),
                    curve: AppMotion.quick,
                    decoration: BoxDecoration(
                      borderRadius:
                          BorderRadius.circular(AppRadius.control + _ring),
                      border: Border.all(
                        color: _focused && !hasError
                            ? colorScheme.accentRing
                            : Colors.transparent,
                        width: _ring,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: AppSpace.s4),
          Text(
            widget.errorText!,
            style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.error),
          ),
        ],
      ],
    );
  }
}

/// Which condition a [ChannelBadge] reports.
enum ChannelBadgeTone {
  /// A requirement or a count (`Key only`, `3 ways in`): card fill, grey ink.
  neutral,

  /// Something the next step will ask for (`Needs address`).
  info,

  /// A state worth a second look (`Deprecated`, `Address edited`).
  warning,
}

/// The r4 badge `D1b` hangs on provider rows and field labels.
class ChannelBadge extends StatelessWidget {
  const ChannelBadge(
    this.label, {
    super.key,
    this.tone = ChannelBadgeTone.neutral,
    this.mono = false,
    this.onTint = false,
  });

  final String label;
  final ChannelBadgeTone tone;
  final bool mono;

  /// On a selected row the neutral fill steps up to the panel, or it would
  /// sink into the accent wash behind it.
  final bool onTint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final semantic = context.semantic;
    final (Color background, Color foreground) = switch (tone) {
      ChannelBadgeTone.neutral => (
          onTint ? colorScheme.surface : colorScheme.surfaceContainer,
          colorScheme.onSurfaceVariant,
        ),
      ChannelBadgeTone.info => (semantic.infoContainer, semantic.onInfoContainer),
      ChannelBadgeTone.warning => (
          semantic.warningContainer,
          semantic.onWarningContainer,
        ),
    };
    final slot = theme.textTheme.labelSmall;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s6, vertical: 1),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: (mono ? slot?.mono : slot)?.copyWith(color: foreground),
      ),
    );
  }
}

/// A warning strip on the warning container — the editor's "switching preset
/// overwrites" note, the preview's empty-key note.
class ChannelNoteStrip extends StatelessWidget {
  const ChannelNoteStrip(this.text, {super.key, this.icon = Icons.info_outline});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.s10, vertical: AppSpace.s6 + 2),
      decoration: BoxDecoration(
        color: semantic.warningContainer,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon,
                size: AppSize.iconMd, color: semantic.onWarningContainer),
          ),
          const SizedBox(width: AppSpace.s6 + 2),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: semantic.onWarningContainer),
            ),
          ),
        ],
      ),
    );
  }
}

/// A setting that is one switch: a column-coloured card with a hairline, a
/// 600 title, an 11px description and the switch (`D1b 1d` 启用模型发现卡).
class ChannelToggleCard extends StatelessWidget {
  const ChannelToggleCard({
    super.key,
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(
          AppSpace.s10 + 2, AppSpace.s10, AppSpace.s10, AppSpace.s10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w400,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.s10),
          AppSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// A channel's or provider's identity: the first letter of [label], white, on
/// an identity colour. Identity colours never follow the accent.
class ChannelIdentityAvatar extends StatelessWidget {
  const ChannelIdentityAvatar({
    super.key,
    required this.label,
    required this.color,
    this.size = 28,
    this.radius = AppRadius.sm,
  });

  final String label;
  final Color color;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final trimmed = label.trim();
    final TextStyle? slot = size >= 40
        ? textTheme.titleLarge
        : size >= 30
            ? textTheme.titleSmall
            : size >= 26
                ? textTheme.labelMedium
                : textTheme.labelSmall;

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: trimmed.isEmpty
          ? Icon(Icons.cloud_queue, size: size * 0.55, color: Colors.white)
          : Text(
              trimmed.characters.first.toUpperCase(),
              style: slot?.metricsOnly.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                height: 1,
              ),
            ),
    );
  }
}

/// The 44px accent plate a dialog heading leads with (`add_link`,
/// `fact_check`).
class ChannelIconPlate extends StatelessWidget {
  const ChannelIconPlate(this.icon, {super.key});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: AppSize.touch,
      height: AppSize.touch,
      decoration: BoxDecoration(
        color: colorScheme.accentTint,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Icon(icon, size: 24, color: colorScheme.primary),
    );
  }
}

/// A channel dialog's heading: a 44 leading plate or avatar, the 16/600 title
/// over a quieter line, and the 32 close button.
///
/// The dialogs change what leads the heading per step (the wizard shows the
/// chosen provider's avatar once there is one), which `AppDialog`'s icon slot
/// cannot express — so this goes in as its `titleWidget`.
class ChannelDialogHeader extends StatelessWidget {
  const ChannelDialogHeader({
    super.key,
    required this.leading,
    required this.title,
    this.subtitle,
    this.monoSubtitle = false,
    this.onClose,
  });

  final Widget leading;
  final String title;
  final String? subtitle;
  final bool monoSubtitle;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final subtitleSlot = monoSubtitle
        ? theme.textTheme.labelSmall?.mono
        : theme.textTheme.bodySmall;

    return Row(
      children: [
        leading,
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge,
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: subtitleSlot?.copyWith(
                      color: colorScheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
        if (onClose != null) ...[
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.close, size: AppSize.iconMd),
            tooltip: AppLocalizations.of(context)?.close,
            onPressed: onClose,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(
              width: AppSize.iconButton,
              height: AppSize.iconButton,
            ),
            style: IconButton.styleFrom(
              foregroundColor: colorScheme.onSurfaceVariant,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.control),
                side: BorderSide(color: colorScheme.outlineVariant),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// The channel as the models screen's channel column draws it (`D1a` 渠道行,
/// 56 high): a 32 r6 identity avatar, the name, and a sub-line pairing the
/// tag on its own colour with a mono model count.
///
/// Drawn at rest, which is how a newly added channel first appears in the
/// column.
class ChannelListRowPreview extends StatelessWidget {
  const ChannelListRowPreview({
    super.key,
    required this.name,
    required this.tag,
    required this.color,
    required this.subline,
    this.namePlaceholder,
  });

  final String name;
  final String tag;
  final Color color;
  final String subline;

  /// Shown in the quiet ink while [name] is empty.
  final String? namePlaceholder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final showPlaceholder = name.trim().isEmpty && namePlaceholder != null;

    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.s10, 0, 8, 0),
        child: Row(
          children: [
            ChannelIdentityAvatar(
              label: tag.isNotEmpty ? tag : name,
              color: color,
              size: AppSize.control,
            ),
            const SizedBox(width: AppSpace.s10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    showPlaceholder ? namePlaceholder! : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelLarge?.copyWith(
                      color: showPlaceholder
                          ? colorScheme.outline
                          : colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (tag.isNotEmpty) ...[
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpace.s6, vertical: 1),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.18),
                              borderRadius:
                                  BorderRadius.circular(AppRadius.xs),
                            ),
                            child: Text(
                              tag,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.labelSmall?.mono
                                  .copyWith(color: colorScheme.onSurface),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpace.s6),
                      ],
                      Text(
                        subline,
                        maxLines: 1,
                        style: textTheme.labelSmall?.mono
                            .copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The tag-colour row: round swatches from [AppConstants.tagColors], then a
/// "More colors" pill that reveals the rest of the palette in place and a
/// "Custom color" pill that opens the hue wheel.
///
/// The current colour is always one of the swatches drawn: when it came from
/// the wheel it takes the leading slot, because a row that cannot show the
/// selection reads as "nothing is selected".
class ChannelTagColorPicker extends StatefulWidget {
  const ChannelTagColorPicker({
    super.key,
    required this.l10n,
    required this.selectedColor,
    required this.onColorChanged,
    this.inlineCount = 10,
    this.swatchSize = 28,
  });

  final AppLocalizations l10n;
  final int selectedColor;
  final ValueChanged<int> onColorChanged;

  /// Swatches shown before "More colors" is opened (`1d`: 10, `1e`: 8).
  final int inlineCount;

  /// Diameter of each swatch and the height of the two pills.
  final double swatchSize;

  @override
  State<ChannelTagColorPicker> createState() => _ChannelTagColorPickerState();
}

class _ChannelTagColorPickerState extends State<ChannelTagColorPicker> {
  bool _showAll = false;

  List<int> _visibleColors() {
    final palette = AppConstants.tagColors.map((c) => c.toARGB32()).toList();
    final shown = _showAll ? palette : palette.take(widget.inlineCount).toList();
    if (shown.contains(widget.selectedColor)) return shown;
    return [
      widget.selectedColor,
      ...(_showAll ? shown : shown.take(math.max(0, shown.length - 1))),
    ];
  }

  Future<void> _openCustom() async {
    final picked = await ChannelColorPickerDialog.show(
      context,
      l10n: widget.l10n,
      initialColor: widget.selectedColor,
    );
    if (picked != null) widget.onColorChanged(picked);
  }

  Widget _pill({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Material(
      color: Colors.transparent,
      shape: StadiumBorder(side: BorderSide(color: colorScheme.outlineVariant)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: widget.swatchSize,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    size: AppSize.iconSm, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: AppSpace.s4),
                Text(
                  label,
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpace.s6,
      runSpacing: AppSpace.s6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final color in _visibleColors())
          ChannelColorSwatch(
            color: Color(color),
            selected: color == widget.selectedColor,
            size: widget.swatchSize,
            onTap: () => widget.onColorChanged(color),
          ),
        _pill(
          icon: _showAll ? Icons.expand_less : Icons.add,
          label: widget.l10n.moreColors,
          onTap: () => setState(() => _showAll = !_showAll),
        ),
        _pill(
          icon: Icons.colorize,
          label: widget.l10n.customColor,
          onTap: _openCustom,
        ),
      ],
    );
  }
}

/// One round colour swatch. Selected: a 2px accent ring separated from the
/// colour by a 2px gap of the panel behind it — a ring set off from the disc
/// rather than drawn on it, so the picked swatch does not read as smaller.
class ChannelColorSwatch extends StatelessWidget {
  const ChannelColorSwatch({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
    this.size = 28,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: size,
          height: size,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? null : color,
              border: selected
                  ? Border.all(color: colorScheme.primary, width: 2)
                  : null,
            ),
            child: selected
                ? Padding(
                    padding: const EdgeInsets.all(AppSpace.s4),
                    child: DecoratedBox(
                      decoration:
                          BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

/// The full palette behind the "Custom color" pill: every preset swatch, the
/// hue wheel, and a hex field, committed with Apply.
class ChannelColorPickerDialog extends StatefulWidget {
  final AppLocalizations l10n;
  final int initialColor;

  const ChannelColorPickerDialog({
    super.key,
    required this.l10n,
    required this.initialColor,
  });

  /// Returns the chosen colour, or null when dismissed.
  static Future<int?> show(
    BuildContext context, {
    required AppLocalizations l10n,
    required int initialColor,
  }) {
    return showDialog<int>(
      context: context,
      builder: (_) => ChannelColorPickerDialog(
        l10n: l10n,
        initialColor: initialColor,
      ),
    );
  }

  @override
  State<ChannelColorPickerDialog> createState() =>
      _ChannelColorPickerDialogState();
}

class _ChannelColorPickerDialogState extends State<ChannelColorPickerDialog> {
  late int _color = widget.initialColor;
  late final TextEditingController _hexCtrl =
      TextEditingController(text: _hexOf(_color));

  static String _hexOf(int argb) =>
      '#${argb.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

  @override
  void dispose() {
    _hexCtrl.dispose();
    super.dispose();
  }

  void _select(int argb) {
    setState(() {
      _color = argb;
      // The field is an input *and* a readout; letting it lag makes Apply
      // look like it committed something other than what is highlighted.
      _hexCtrl.text = _hexOf(argb);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;

    return AppDialog(
      icon: Icons.colorize,
      title: l10n.customColor,
      maxWidth: 380,
      maxHeight: 640,
      scrollable: true,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: AppSpace.s6,
            runSpacing: AppSpace.s6,
            children: [
              for (final preset in AppConstants.tagColors)
                ChannelColorSwatch(
                  color: preset,
                  selected: preset.toARGB32() == _color,
                  onTap: () => _select(preset.toARGB32()),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.s16),
          Center(
            child: ColorHuePicker(
              initialColor: Color(_color),
              onColorChanged: _select,
            ),
          ),
          const SizedBox(height: AppSpace.s16),
          Row(
            children: [
              Container(
                width: AppSize.control,
                height: AppSize.control,
                decoration: BoxDecoration(
                  color: Color(_color),
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
              ),
              const SizedBox(width: AppSpace.s10),
              Expanded(
                child: ChannelField(
                  controller: _hexCtrl,
                  mono: true,
                  hint: '#RRGGBB',
                  onChanged: (v) {
                    final parsed = _parseHex(v);
                    if (parsed != null) setState(() => _color = parsed);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        AppButton(
          label: l10n.cancel,
          variant: AppButtonVariant.text,
          onPressed: () => Navigator.pop(context),
        ),
        AppButton(
          label: l10n.apply,
          onPressed: () => Navigator.pop(context, _color),
        ),
      ],
    );
  }

  /// `#RRGGBB` or `#AARRGGBB`; null for anything still half-typed, so the
  /// preview holds its last valid value rather than flickering.
  static int? _parseHex(String input) {
    final raw = input.trim();
    if (!raw.startsWith('#')) return null;
    final body = raw.substring(1);
    if (body.length != 6 && body.length != 8) return null;
    return int.tryParse(body.length == 6 ? 'FF$body' : body, radix: 16);
  }
}
