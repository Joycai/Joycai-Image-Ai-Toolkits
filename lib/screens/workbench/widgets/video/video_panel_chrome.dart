part of '../video_config_panel.dart';

/// A card in the right column (`A2 · 1a`): the panel's ground, a hairline,
/// r16, inset 10 — the image column's card, restated.
class _PanelCard extends StatelessWidget {
  const _PanelCard({
    required this.child,
    this.padding = const EdgeInsets.all(_kCardPadding),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Material, not a decorated Container, so the ink of the buttons and
    // fields inside lands on it.
    return Material(
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: double.infinity,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// The prompt editor's frame (`1a`): the column's ground, r10, a hairline.
class _EditorWell extends StatelessWidget {
  const _EditorWell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// A request toggle (`A2 · 1a` 「开关卡」): the label, its hint inline in the
/// secondary ink, and the switch at the end of a 36px row.
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    required this.hint,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    // Merged so the switch is announced with the words that name it.
    return MergeSemantics(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _kToggleRowHeight),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.s4),
          child: Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: title, style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurface)),
                      const WidgetSpan(child: SizedBox(width: AppSpace.s6)),
                      TextSpan(
                        text: hint,
                        style: textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppSpace.s10),
              AppSwitch(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}

/// `1b` 「琥珀提示条」: 11px warning ink on the warning container, r6, with a
/// 14px warning glyph.
class _WarningNotice extends StatelessWidget {
  const _WarningNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: AppSpace.s4),
      decoration: BoxDecoration(
        color: semantic.warningContainer,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.warning_amber_rounded, size: AppSize.iconSm, color: semantic.warning),
          ),
          const SizedBox(width: AppSpace.s4),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: semantic.onWarningContainer),
            ),
          ),
        ],
      ),
    );
  }
}

/// Reports its child's laid-out height after the frame, whenever it changes.
class _ExtentReporter extends SingleChildRenderObjectWidget {
  const _ExtentReporter({required this.onExtent, required super.child});

  final ValueChanged<double> onExtent;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderExtentReporter(onExtent);

  @override
  void updateRenderObject(BuildContext context, _RenderExtentReporter renderObject) {
    renderObject.onExtent = onExtent;
  }
}

class _RenderExtentReporter extends RenderProxyBox {
  _RenderExtentReporter(this.onExtent);

  ValueChanged<double> onExtent;
  double? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final double extent = size.height;
    if (extent == _reported) return;
    _reported = extent;
    WidgetsBinding.instance.addPostFrameCallback((_) => onExtent(extent));
  }
}
