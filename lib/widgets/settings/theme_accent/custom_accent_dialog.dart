part of '../theme_accent_picker.dart';

// ── Custom colour ────────────────────────────────────────────────────────────

/// The custom theme colour flow — design `E1 · 1b`: pick a hue (the ring or a
/// hex value), see the pair derived from it drawn in real components, and the
/// measurements that decided it. Returns the seed to apply, or null.
///
/// The derivation is [CustomAccent.derive]; this only shows it. When white
/// cannot hold on the light half the result is not a failure: the button's
/// label becomes the hue's deep ink, which the banner shows as white struck
/// through and the ink that replaced it.
Future<Color?> showCustomAccentDialog(BuildContext context, {required Color initialSeed}) {
  return showDialog<Color>(
    context: context,
    animationStyle: appDialogAnimation(context),
    builder: (_) => _CustomAccentDialog(initialSeed: initialSeed),
  );
}

class _CustomAccentDialog extends StatefulWidget {
  const _CustomAccentDialog({required this.initialSeed});

  final Color initialSeed;

  @override
  State<_CustomAccentDialog> createState() => _CustomAccentDialogState();
}

class _CustomAccentDialogState extends State<_CustomAccentDialog> {
  late CustomAccentDerivation _derived = CustomAccent.derive(widget.initialSeed);
  late final TextEditingController _hexController = TextEditingController(
    text: CustomAccent.hex(widget.initialSeed),
  );

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  void _setSeed(Color seed, {bool fromField = false}) {
    if (seed.toARGB32() == _derived.seed.toARGB32()) return;
    setState(() => _derived = CustomAccent.derive(seed));
    if (!fromField) _hexController.text = CustomAccent.hex(seed);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final bool failed = _derived.verdict == CustomAccentVerdict.failed;

    return AppDialog(
      icon: Icons.colorize,
      title: l10n.customAccentTitle,
      subtitle: CustomAccent.hex(_derived.seed),
      maxWidth: 520,
      scrollable: true,
      dividedHeading: false,
      onClose: () => Navigator.pop(context),
      content: LayoutBuilder(
        builder: (context, constraints) {
          final Widget picker = _buildPicker(context);
          final Widget result = _buildResult(context, l10n);
          if (constraints.maxWidth < 440) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: SizedBox(width: 150, child: picker)),
                const SizedBox(height: AppSpace.s16),
                result,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 150, child: picker),
              const SizedBox(width: AppSpace.s16),
              Expanded(child: result),
            ],
          );
        },
      ),
      actions: [
        AppButton(
          label: l10n.cancel,
          variant: AppButtonVariant.text,
          onPressed: () => Navigator.pop(context),
        ),
        AppButton(
          label: l10n.apply,
          onPressed: failed ? null : () => Navigator.pop(context, _derived.seed),
        ),
      ],
    );
  }

  Widget _buildPicker(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hexStyle = textTheme.bodySmall?.mono;

    return Column(
      children: [
        _HueRing(
          hue: _derived.hue,
          seed: _derived.seed,
          onChanged: (hue) => _setSeed(CustomAccent.seedForHue(hue)),
        ),
        const SizedBox(height: AppSpace.s10),
        TextField(
          controller: _hexController,
          style: hexStyle,
          textAlignVertical: TextAlignVertical.center,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp('[#0-9a-fA-F]')),
            LengthLimitingTextInputFormatter(7),
          ],
          decoration: InputDecoration(
            filled: true,
            fillColor: colorScheme.surfaceContainerLow,
            isDense: true,
            constraints: const BoxConstraints.tightFor(height: AppSize.control),
            contentPadding: EdgeInsets.symmetric(
              horizontal: 8,
              vertical: pinnedFieldInset(context, hexStyle, AppSize.control),
            ),
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 8, right: 6),
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: _derived.seed,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
              ),
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
          ),
          onChanged: (value) {
            final Color? seed = CustomAccent.parseHex(value);
            if (seed != null && value.replaceAll('#', '').length == 6) {
              _setSeed(seed, fromField: true);
            }
          },
        ),
        const SizedBox(height: AppSpace.s10),
        Text(
          AppLocalizations.of(context)!.customAccentHint,
          textAlign: TextAlign.center,
          style: textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w400,
            color: colorScheme.onSurfaceVariant,
            height: AppType.proseHeight,
          ),
        ),
      ],
    );
  }

  Widget _buildResult(BuildContext context, AppLocalizations l10n) {
    final semantic = context.semantic;
    final colorScheme = Theme.of(context).colorScheme;
    final CustomAccentVerdict verdict = _derived.verdict;

    final (
      Color bannerBg,
      Color bannerInk,
      Color bannerText,
      IconData bannerIcon,
      String message,
    ) = switch (verdict) {
      CustomAccentVerdict.passed => (
        semantic.successContainer,
        semantic.success,
        semantic.onSuccessContainer,
        Icons.check_circle,
        l10n.customAccentPassed,
      ),
      CustomAccentVerdict.inkFallback => (
        semantic.warningContainer,
        semantic.warning,
        semantic.onWarningContainer,
        Icons.warning_amber_rounded,
        l10n.customAccentInkFallback,
      ),
      CustomAccentVerdict.failed => (
        colorScheme.errorContainer,
        colorScheme.error,
        colorScheme.onErrorContainer,
        Icons.error_outline,
        l10n.customAccentFailed,
      ),
    };

    final AccentCheck white = _derived.checks.firstWhere(
      (c) => c.kind == AccentCheckKind.whiteOnAccent,
    );
    final AccentCheck? ink = _derived.checks
        .where((c) => c.kind == AccentCheckKind.inkOnAccent)
        .firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSectionLabel(l10n.customAccentDerived, padding: EdgeInsets.zero),
        const SizedBox(height: AppSpace.s10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _PairPanel(accent: _derived.accent, brightness: Brightness.light),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _PairPanel(accent: _derived.accent, brightness: Brightness.dark),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.s10),
        // What the primary button's label ended up as: white that holds, or
        // white struck out and the deep ink that took its place.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: bannerBg,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(bannerIcon, size: AppSize.iconSm, color: bannerInk),
              ),
              const SizedBox(width: AppSpace.s6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: bannerText,
                        height: AppType.proseHeight,
                      ),
                    ),
                    const SizedBox(height: AppSpace.s6),
                    Wrap(
                      spacing: AppSpace.s6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _CheckChip(check: white),
                        _Ratio(check: white),
                        if (ink != null) ...[
                          Icon(Icons.arrow_forward, size: AppSize.iconSm, color: bannerInk),
                          _CheckChip(check: ink),
                          _Ratio(check: ink),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.s10),
        for (final AccentCheck check in _derived.checks)
          if (check.kind != AccentCheckKind.whiteOnAccent &&
              check.kind != AccentCheckKind.inkOnAccent)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(
                    check.brightness == Brightness.light
                        ? Icons.light_mode_outlined
                        : Icons.dark_mode_outlined,
                    size: AppSize.iconSm,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  _CheckChip(check: check),
                  const Spacer(),
                  _Ratio(check: check),
                ],
              ),
            ),
      ],
    );
  }
}
