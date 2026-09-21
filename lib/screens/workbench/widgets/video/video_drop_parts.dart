part of 'video_config_panel.dart';

/// How long a drop's confirmation note stays (`00d` 确认 「一条 ok 说明条」).
/// Not a motion token: nothing moves for this long, it is read.
const Duration _kDropNoteHold = Duration(seconds: 2);

/// Whether an in-app drag carries a picture a slot takes. Gallery cards drag
/// videos too, and those are refused with a reason rather than ignored.
bool _isDroppableImage(Object? payload) => payload is AppImage && AppConstants.isImageFile(payload.path);

/// Reads a drop's result out, as its note says it (`00d` 无障碍).
void _announceDrop(BuildContext context, String message) {
  SemanticsService.sendAnnouncement(View.of(context), message, Directionality.of(context));
}

/// A drop place with nothing in it (`00d · 1c` 投放槽 / 投放区): the zone
/// ladder's ground and dashed edge, a glyph, the slot's name and a hint.
///
/// The words degrade by measuring, not by width thresholds: the hint goes
/// first, then the glyph; a name that would not fit its two lines is left out
/// rather than cut mid-word, so a narrow cell keeps its glyph alone. What was
/// left out is still read to screen readers.
class _DropSlot extends StatelessWidget {
  const _DropSlot({
    required this.state,
    required this.icon,
    this.title,
    this.hint,
    this.onTap,
  });

  final AppDropZoneState state;

  /// The resting glyph; hover, reject and full bring their own.
  final IconData icon;

  /// The slot's name at rest, or what a release does, or why it will not.
  final String? title;

  /// A second line at rest: the other way to fill the slot.
  final String? hint;

  final VoidCallback? onTap;

  static const double _padding = AppSpace.s6;
  static const double _gap = AppSpace.s4;
  static const int _maxLines = 2;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final radius = BorderRadius.circular(AppRadius.control);

    final IconData glyph = switch (state) {
      AppDropZoneState.hover => Icons.download,
      AppDropZoneState.reject => Icons.block,
      AppDropZoneState.full => Icons.layers_outlined,
      AppDropZoneState.rest || AppDropZoneState.armed => icon,
    };
    final Color glyphInk = state == AppDropZoneState.rest ? colorScheme.outline : state.edge(context);
    final TextStyle titleStyle = theme.textTheme.labelMedium!.copyWith(color: state.ink(context));
    final TextStyle hintStyle = theme.textTheme.labelSmall!.copyWith(
      fontWeight: FontWeight.w400,
      color: colorScheme.outline,
    );

    return AppDropZoneFrame(
      state: state,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: LayoutBuilder(
            builder: (context, box) {
              final double width = math.max(0, box.maxWidth - _padding * 2);
              final double room = box.maxHeight - _padding * 2;
              final double? titleHeight = _fittedTextHeight(context, title, titleStyle, width, maxLines: _maxLines);
              final double? hintHeight = _fittedTextHeight(context, hint, hintStyle, width, maxLines: _maxLines);

              double stacked({required bool glyph, required bool name, required bool second}) {
                final parts = <double>[
                  if (glyph) AppSize.iconLg,
                  if (name && titleHeight != null) titleHeight,
                  if (second && hintHeight != null) hintHeight,
                ];
                if (parts.isEmpty) return 0;
                return parts.reduce((a, b) => a + b) + _gap * (parts.length - 1);
              }

              bool withTitle = titleHeight != null;
              bool withHint = hintHeight != null;
              bool withGlyph = true;
              if (withHint && stacked(glyph: true, name: withTitle, second: true) > room) withHint = false;
              if (stacked(glyph: true, name: withTitle, second: withHint) > room) withGlyph = false;
              if (withTitle && stacked(glyph: false, name: true, second: withHint) > room) {
                withTitle = false;
                withGlyph = true;
              }

              return Semantics(
                label: title,
                hint: hint,
                excludeSemantics: true,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(_padding),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (withGlyph) Icon(glyph, size: AppSize.iconLg, color: glyphInk),
                        if (withTitle) ...[
                          if (withGlyph) const SizedBox(height: _gap),
                          Text(
                            title!,
                            textAlign: TextAlign.center,
                            maxLines: _maxLines,
                            overflow: TextOverflow.ellipsis,
                            style: titleStyle,
                          ),
                        ],
                        if (withHint) ...[
                          if (withGlyph || withTitle) const SizedBox(height: _gap),
                          Text(
                            hint!,
                            textAlign: TextAlign.center,
                            maxLines: _maxLines,
                            overflow: TextOverflow.ellipsis,
                            style: hintStyle,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The height [text] takes at [width] within [maxLines], or null when it would
/// not fit them — how drop copy decides what to leave out, by measuring rather
/// than by width thresholds.
double? _fittedTextHeight(
  BuildContext context,
  String? text,
  TextStyle style,
  double width, {
  int maxLines = 2,
}) {
  if (text == null) return null;
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textAlign: TextAlign.center,
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: maxLines,
  )..layout(maxWidth: width);
  final double? height = painter.didExceedMaxLines ? null : painter.height;
  painter.dispose();
  return height;
}

/// Drop copy laid over a picture: on the fixed image plate, since the design
/// never lays `--tint` over an image (`00d` 颜色角色). The [hint] line joins
/// only where it fits the room the plate is given.
class _PlateLabel extends StatelessWidget {
  const _PlateLabel(this.text, {this.hint});

  final String text;
  final String? hint;

  static const EdgeInsets _padding = EdgeInsets.symmetric(horizontal: AppSpace.s6, vertical: 2);
  static const double _gap = 2;
  static const int _maxLines = 2;

  @override
  Widget build(BuildContext context) {
    final TextStyle textStyle = Theme.of(context).textTheme.labelSmall!.copyWith(color: AppOverlay.onImagePlate);
    final TextStyle hintStyle = textStyle.copyWith(fontWeight: FontWeight.w400);

    return LayoutBuilder(
      builder: (context, box) {
        final double width = math.max(0, box.maxWidth - _padding.horizontal);
        final double? textHeight = _fittedTextHeight(context, text, textStyle, width, maxLines: _maxLines);
        final double? hintHeight = _fittedTextHeight(context, hint, hintStyle, width, maxLines: _maxLines);
        final bool withHint = textHeight != null &&
            hintHeight != null &&
            _padding.vertical + textHeight + _gap + hintHeight <= box.maxHeight;

        return DecoratedBox(
          decoration: BoxDecoration(
            color: AppOverlay.imagePlate,
            borderRadius: BorderRadius.circular(AppRadius.xs),
          ),
          child: Padding(
            padding: _padding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  text,
                  textAlign: TextAlign.center,
                  maxLines: _maxLines,
                  overflow: TextOverflow.ellipsis,
                  style: textStyle,
                ),
                if (withHint) ...[
                  const SizedBox(height: _gap),
                  Text(
                    hint!,
                    textAlign: TextAlign.center,
                    maxLines: _maxLines,
                    overflow: TextOverflow.ellipsis,
                    style: hintStyle,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A round close button on the fixed image plate, for a control laid over the
/// user's own picture.
class _PlateCloseButton extends StatelessWidget {
  const _PlateCloseButton({required this.size, required this.tooltip, required this.onPressed});

  final double size;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onPressed,
            child: Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: AppOverlay.imagePlate, shape: BoxShape.circle),
              child: const Icon(Icons.close, size: AppSize.iconSm, color: AppOverlay.onImagePlate),
            ),
          ),
        ),
      ),
    );
  }
}
