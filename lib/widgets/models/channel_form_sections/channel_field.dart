import 'package:flutter/material.dart';

import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../ui/app_field_size.dart';

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
