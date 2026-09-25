part of '../channel_wizard_dialog.dart';

/// The wizard's frame: the dialog and the phone page, the heading, the
/// step rail, the footer, and the body that slides between steps.
extension _WizardChrome on _ChannelWizardDialogState {
  Widget _buildDialog(AppLocalizations l10n) {
    // The body claims what the window can spare, between a floor that keeps
    // the provider list scrollable and a ceiling that stops the dialog
    // stretching on a tall display. Heading, footer and the dialog's own
    // vertical inset account for the subtracted band.
    final bodyHeight = (MediaQuery.sizeOf(context).height - 230).clamp(320.0, 580.0);

    return AppDialog(
      titleWidget: _buildHeader(l10n),
      maxWidth: 760,
      dividedHeading: true,
      contentPadding: EdgeInsets.zero,
      content: SizedBox(
        height: bodyHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // The rail is 200 and the form needs ~320 before its two-column
            // rows stop being usable; below that the footer's counter still
            // says where the user is.
            final showRail = constraints.maxWidth >= 520;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showRail) SizedBox(width: 200, child: _buildStepRail(l10n)),
                Expanded(child: _buildStepBody(l10n)),
              ],
            );
          },
        ),
      ),
      actionsOverride: _buildFooter(l10n),
    );
  }

  Widget _buildPage(AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final steps = _steps;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(l10n.addChannel),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: l10n.close,
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.s16,
              AppSpace.s4,
              AppSpace.s16,
              AppSpace.s10,
            ),
            child: Row(
              children: [
                for (final (i, step) in steps.indexed) ...[
                  if (i > 0) const SizedBox(width: AppSpace.s4),
                  _StepDot(number: i + 1, done: i < _stepIndex, current: step == _step),
                ],
                const SizedBox(width: AppSpace.s10),
                Expanded(
                  child: Text(
                    _stepName(l10n, _step),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleSmall?.copyWith(color: colorScheme.onSurface),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildStepBody(l10n)),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.s16,
                  vertical: AppSpace.s10,
                ),
                child: _buildFooter(l10n),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The heading follows the step: the add-channel plate and catalogue count
  /// while choosing, then the chosen provider's own avatar and what this step
  /// is about.
  Widget _buildHeader(AppLocalizations l10n) {
    final preset = _preset;
    final title = channelProviderTitle(l10n, preset.id);
    final avatar = ChannelIdentityAvatar(
      label: title,
      color: channelPresetIdentityColor(preset),
      size: AppSize.touch,
      radius: AppRadius.control,
    );

    return switch (_step) {
      _WizardStep.provider => ChannelDialogHeader(
        leading: const ChannelIconPlate(Icons.add_link),
        title: l10n.addChannel,
        subtitle: l10n.providerCountSummary(
          kListedChannelProviderPresets.length,
          ChannelProviderGroup.values.length,
        ),
        monoSubtitle: true,
        onClose: () => Navigator.pop(context),
      ),
      _WizardStep.variant => ChannelDialogHeader(
        leading: avatar,
        title: '$title · ${_stepName(l10n, _WizardStep.variant)}',
        subtitle: channelProviderVariantHint(l10n, preset.id),
        onClose: () => Navigator.pop(context),
      ),
      final step => ChannelDialogHeader(
        leading: avatar,
        title: '$title · ${_stepName(l10n, step)}',
        subtitle:
            '${channelProviderGroupHint(l10n, preset.group)}'
            ' · ${channelProviderNeedLabel(l10n, preset.need)}',
        onClose: () => Navigator.pop(context),
      ),
    };
  }

  Widget _buildStepRail(AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    final steps = _steps;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(right: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, AppSpace.s10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, step) in steps.indexed) ...[
                    if (i > 0) const SizedBox(height: 2),
                    _buildStepRow(l10n, i, step),
                  ],
                ],
              ),
            ),
          ),
          // Why the rail just grew or shrank: the provider decides whether a
          // "way in" step exists.
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.s22, 0, 14, 14),
            child: Text(
              l10n.wizardStepsAdaptNote,
              style: Theme.of(context).textTheme.labelSmall?.mono.copyWith(
                fontWeight: FontWeight.w400,
                color: colorScheme.outline,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepRow(AppLocalizations l10n, int index, _WizardStep step) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final done = index < _stepIndex;
    final current = index == _stepIndex;

    return Material(
      color: current ? colorScheme.accentTint : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.control),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // A finished step can be revisited; a future one has to be reached
        // through Next, which is where its checks run.
        onTap: done ? () => _rebuild(() => _stepIndex = index) : null,
        child: SizedBox(
          height: AppSize.large,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10),
            child: Row(
              children: [
                _StepDot(number: index + 1, done: done, current: current),
                const SizedBox(width: AppSpace.s10),
                Expanded(
                  child: Text(
                    _stepName(l10n, step),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.metricsOnly.copyWith(
                      fontWeight: current ? FontWeight.w600 : FontWeight.w500,
                      color: current
                          ? colorScheme.onAccentTint
                          : done
                          ? colorScheme.onSurface
                          : colorScheme.onSurfaceVariant,
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

  Widget _buildFooter(AppLocalizations l10n) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(
          l10n.wizardStepCounter(_stepIndex + 1, _steps.length),
          style: theme.textTheme.labelSmall?.mono.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        AppButton(
          label: l10n.back,
          variant: AppButtonVariant.text,
          onPressed: _stepIndex == 0 ? null : _back,
        ),
        const SizedBox(width: AppSpace.s6),
        AppButton(label: _nextLabel(l10n), loading: _submitting, onPressed: _next),
      ],
    );
  }

  Widget _buildStepBody(AppLocalizations l10n) {
    final step = _step;
    const formPadding = EdgeInsets.fromLTRB(16, 14, 16, 16);

    final Widget body = switch (step) {
      _WizardStep.provider => _buildProviderStep(l10n),
      _WizardStep.variant => SingleChildScrollView(
        padding: formPadding,
        child: _buildVariantStep(l10n),
      ),
      _WizardStep.connection => SingleChildScrollView(
        padding: formPadding,
        child: _buildConnectionStep(l10n),
      ),
      _WizardStep.appearance => SingleChildScrollView(
        padding: formPadding,
        child: _buildAppearanceStep(l10n),
      ),
    };

    final shown = _shownStep;
    if (shown != null && shown != step) {
      _stepSerial++;
      _serialDirection[_stepSerial] = step.index > shown.index ? 1 : -1;
    }
    _shownStep = step;
    final current = _stepSerial;

    // Forward, the next step comes in from the right and the last one leaves
    // to the left; back, the other way round. A plain cross-fade looked the
    // same both ways, and only the step dots said which way the wizard went.
    return AnimatedSwitcher(
      duration: AppMotion.durationOf(context, AppMotion.state),
      switchInCurve: AppMotion.enter,
      switchOutCurve: AppMotion.enter,
      transitionBuilder: (child, animation) {
        // The outgoing body runs the same animation in reverse, so its
        // `begin` is where it leaves to — the way of the move that replaced
        // it, the serial after its own.
        final serial = (child.key! as ValueKey<int>).value;
        final double shift = serial == current
            ? (_serialDirection[serial] ?? 1) * _ChannelWizardDialogState._stepShift
            : -(_serialDirection[serial + 1] ?? 1) * _ChannelWizardDialogState._stepShift;
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(begin: Offset(shift, 0), end: Offset.zero).animate(animation),
            child: child,
          ),
        );
      },
      child: KeyedSubtree(key: ValueKey<int>(current), child: body),
    );
  }
}

/// A step's 20px marker: a filled check once done, an accent ring on the
/// current step, a hairline ring with the step's number ahead.
class _StepDot extends StatelessWidget {
  const _StepDot({required this.number, required this.done, required this.current});

  final int number;
  final bool done;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AnimatedContainer(
      duration: AppMotion.durationOf(context, AppMotion.state),
      curve: AppMotion.enter,
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? colorScheme.primary : Colors.transparent,
        border: done
            ? null
            : Border.all(
                color: current ? colorScheme.primary : colorScheme.outlineVariant,
                width: current ? 2 : 1.5,
              ),
      ),
      child: done
          ? Icon(Icons.check, size: AppSize.iconSm, color: colorScheme.onPrimary)
          : Text(
              '$number',
              style: theme.textTheme.labelSmall?.mono.copyWith(
                fontWeight: FontWeight.w600,
                height: 1,
                color: current ? colorScheme.onAccentTint : colorScheme.onSurfaceVariant,
              ),
            ),
    );
  }
}
