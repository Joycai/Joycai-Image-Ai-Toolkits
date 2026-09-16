part of '../theme_accent_picker.dart';

/// One brightness of the derived pair, drawn in that brightness's real theme
/// — a primary button, a switch and a selected row are the app's own widgets,
/// so the preview cannot promise what the app would not paint.
class _PairPanel extends StatelessWidget {
  const _PairPanel({required this.accent, required this.brightness});

  final ThemeAccent accent;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ThemeData theme = buildAppTheme(
      accent: accent,
      brightness: brightness,
      fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
    );

    return Theme(
      data: theme,
      child: Builder(builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        final textTheme = Theme.of(context).textTheme;
        return ExcludeFocus(
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.all(AppSpace.s10),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(AppRadius.control),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          brightness == Brightness.light ? l10n.themeLight : l10n.themeDark,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                      Text(
                        _hex(scheme.primary),
                        style: textTheme.labelSmall?.mono.copyWith(
                          fontWeight: FontWeight.w400,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpace.s6),
                  AppButton(
                    label: l10n.processPrompt,
                    size: AppButtonSize.compact,
                    fullWidth: true,
                    onPressed: () {},
                  ),
                  const SizedBox(height: AppSpace.s6),
                  Row(
                    children: [
                      AppSwitch(value: true, onChanged: (_) {}),
                      const SizedBox(width: AppSpace.s6),
                      Expanded(
                        child: Container(
                          height: 24,
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            color: scheme.accentTint,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Text(
                            l10n.custom,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.labelSmall?.copyWith(color: scheme.onAccentTint),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// A check as a picture of its own pairing: a glyph in the foreground on the
/// ground it is measured against — or, for the outline check, a 1.5px ring.
class _CheckChip extends StatelessWidget {
  const _CheckChip({required this.check});

  final AccentCheck check;

  @override
  Widget build(BuildContext context) {
    final bool stroke = check.kind == AccentCheckKind.strokeOnCanvas;
    return Container(
      width: 36,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: check.background,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: stroke
          ? Container(
              width: 20,
              height: 10,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: check.foreground, width: 1.5),
              ),
            )
          : Icon(Icons.text_fields, size: AppSize.iconSm, color: check.foreground),
    );
  }
}

/// A ratio in mono, with a tick or a cross in the success or warning ink.
class _Ratio extends StatelessWidget {
  const _Ratio({required this.check});

  final AccentCheck check;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final Color ink = check.passes ? semantic.onSuccessContainer : semantic.onWarningContainer;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${check.ratio.toStringAsFixed(1)}:1',
          style: Theme.of(context).textTheme.labelSmall?.mono.copyWith(
                fontWeight: FontWeight.w400,
                color: ink,
              ),
        ),
        const SizedBox(width: 2),
        Icon(check.passes ? Icons.check : Icons.close, size: 12, color: ink),
      ],
    );
  }
}
