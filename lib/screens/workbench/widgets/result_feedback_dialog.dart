import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/app_image.dart';
import '../../../models/result_feedback.dart';
import '../../../widgets/ui/app_button.dart';
import '../../../widgets/ui/app_dialog.dart';
import '../../../widgets/glass/app_glass.dart';
import 'result_feedback_labels.dart';

/// The longest note the dialog accepts, in characters (`3b`: 「0 / 500」).
const int kResultFeedbackMaxLength = 500;

/// The 「反馈给助手」 dialog (`A1 · 3b`): collects the user's verdict on one
/// generated result before it is fed back into the assistant conversation.
///
/// Pure collection — it stages nothing itself. Returns the [ResultFeedback],
/// or null when cancelled, and the caller does the actual
/// `sendResultFeedback`; a dialog that wrote into the session on its own
/// would be a second place the feedback flow lives.
///
/// [runMeta] names the run the verdict is about — model and time — for the
/// heading's second line beside the version; [promptText] is the first line
/// of the prompt that run used, for the recap strip. Either may be null when
/// the record is gone, and the heading and strip fall back to the version
/// and the file name.
Future<ResultFeedback?> showResultFeedbackDialog(
  BuildContext context, {
  required AppImage image,
  required int promptVersion,
  String? runMeta,
  String? promptText,
}) {
  final scheme = Theme.of(context).colorScheme;
  return showDialog<ResultFeedback>(
    context: context,
    animationStyle: appDialogAnimation(context),
    // `3b` keeps `2b`'s scrim at 60%: a verdict is light and reversible in
    // the next turn, not the kind of decision the full scrim is for.
    barrierColor: scheme.scrim.withValues(alpha: scheme.scrim.a * 0.6),
    builder: (_) => ResultFeedbackDialog(
      image: image,
      promptVersion: promptVersion,
      runMeta: runMeta,
      promptText: promptText,
    ),
  );
}

/// The dialog body of [showResultFeedbackDialog], public for the screenshot
/// harness. Everything else opens it through that function.
///
/// `2b`'s shell — float-grade glass at r22 — at 400 wide. Under the heading
/// a recap strip (the result's thumbnail with its version badge, and the
/// prompt that made it) confirms *which* picture is being judged; then two
/// equal tiles, 「满意」 / 「不满意」, one of which must be chosen before the
/// send button wakes. A thumbs down unfolds a row of reason pills (any
/// number, or none). The note under them is optional either way; its
/// placeholder follows the verdict.
class ResultFeedbackDialog extends StatefulWidget {
  const ResultFeedbackDialog({
    super.key,
    required this.image,
    required this.promptVersion,
    this.runMeta,
    this.promptText,
  });

  /// `3b`: 「400 宽」.
  static const double width = 400;

  final AppImage image;
  final int promptVersion;
  final String? runMeta;
  final String? promptText;

  @override
  State<ResultFeedbackDialog> createState() => _ResultFeedbackDialogState();
}

class _ResultFeedbackDialogState extends State<ResultFeedbackDialog> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  bool? _satisfied;
  final Set<ResultFeedbackReason> _reasons = {};

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  bool get _canSend => _satisfied != null;

  void _submit() {
    final satisfied = _satisfied;
    if (satisfied == null) return;
    Navigator.of(context).pop<ResultFeedback>(ResultFeedback(
      satisfied: satisfied,
      reasons: satisfied ? const [] : _reasons.toList(),
      note: _controller.text.trim(),
    ));
  }

  void _rate(bool satisfied) {
    setState(() => _satisfied = satisfied);
    // The note is what most people reach for next.
    _focus.requestFocus();
  }

  void _toggleReason(ResultFeedbackReason reason) {
    setState(() {
      if (!_reasons.remove(reason)) _reasons.add(reason);
    });
  }

  String _hint(AppLocalizations l10n) => switch (_satisfied) {
        true => l10n.optFeedbackHintSatisfied,
        false => l10n.optFeedbackHintUnsatisfied,
        null => l10n.optResultFeedbackHint,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final radius = BorderRadius.circular(appDialogRadius);
    final String subtitle = [
      'v${widget.promptVersion}',
      if (widget.runMeta case final meta? when meta.isNotEmpty) meta,
    ].join(' · ');

    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: radius),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: ResultFeedbackDialog.width),
        // The glass's own shadow, as `2b` settled: a painted shadow shows
        // through a translucent panel as a grey slab on the light theme.
        child: AppGlass(
          grade: GlassGrade.float,
          borderRadius: radius,
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
          child: Material(
            type: MaterialType.transparency,
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.enter, control: true): _submit,
                const SingleActivator(LogicalKeyboardKey.enter, meta: true): _submit,
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Heading(
                    title: l10n.optResultFeedbackAction,
                    subtitle: subtitle,
                    closeTooltip: l10n.close,
                    onClose: () => Navigator.of(context).pop<ResultFeedback>(null),
                  ),
                  const SizedBox(height: 12),
                  _RunRecap(
                    image: widget.image,
                    promptVersion: widget.promptVersion,
                    label: l10n.optFeedbackRunPromptLabel,
                    promptText: widget.promptText ?? widget.image.name,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _VerdictTile(
                          icon: Icons.thumb_up_outlined,
                          selectedIcon: Icons.thumb_up,
                          label: l10n.optFeedbackSatisfied,
                          selected: _satisfied == true,
                          onTap: () => _rate(true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _VerdictTile(
                          icon: Icons.thumb_down_outlined,
                          selectedIcon: Icons.thumb_down,
                          label: l10n.optFeedbackUnsatisfied,
                          selected: _satisfied == false,
                          onTap: () => _rate(false),
                        ),
                      ),
                    ],
                  ),
                  // The reason row unfolds under a thumbs down and folds
                  // away again under a thumbs up (`3b`).
                  AnimatedSize(
                    duration: AppMotion.durationOf(context, AppMotion.reveal),
                    curve: AppMotion.enter,
                    alignment: Alignment.topCenter,
                    child: _satisfied == false
                        ? Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final reason in ResultFeedbackReason.values)
                                  _ReasonPill(
                                    label: resultFeedbackReasonLabel(l10n, reason),
                                    selected: _reasons.contains(reason),
                                    onTap: () => _toggleReason(reason),
                                  ),
                              ],
                            ),
                          )
                        : const SizedBox(width: double.infinity),
                  ),
                  const SizedBox(height: 12),
                  _NoteField(
                    controller: _controller,
                    focusNode: _focus,
                    hint: _hint(l10n),
                    onSubmit: _submit,
                  ),
                  const SizedBox(height: 12),
                  _FooterNote(text: l10n.optFeedbackFooterNote),
                  const SizedBox(height: 12),
                  const _Rule(),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _ShortcutHint(l10n: l10n)),
                      const SizedBox(width: AppSpace.s10),
                      AppButton(
                        label: l10n.cancel,
                        variant: AppButtonVariant.text,
                        onPressed: () => Navigator.of(context).pop<ResultFeedback>(null),
                      ),
                      const SizedBox(width: AppSpace.s4),
                      AppButton(
                        label: l10n.optSendFeedback,
                        icon: Icons.send_rounded,
                        onPressed: _canSend ? _submit : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `3b`: a lens-grade 40px plate carrying the rate_review glyph in the
/// accent, the title, the run under it in mono, and ✕ at the trailing edge.
class _Heading extends StatelessWidget {
  const _Heading({
    required this.title,
    required this.subtitle,
    required this.closeTooltip,
    required this.onClose,
  });

  final String title;
  final String subtitle;
  final String closeTooltip;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final glass = GlassInk.maybeOf(context);
    final ink = glass?.ink ?? scheme.onSurface;
    final ink2 = glass?.ink2 ?? scheme.onSurfaceVariant;

    return Row(
      children: [
        AppGlass(
          grade: GlassGrade.lens,
          borderRadius: BorderRadius.circular(AppRadius.control),
          shadow: false,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(Icons.rate_review_outlined, size: 22, color: scheme.primary),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleMedium!.metricsOnly.copyWith(
                  fontWeight: FontWeight.w600,
                  color: ink,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall!.mono.metricsOnly.copyWith(color: ink2),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpace.s10),
        IconButton(
          icon: const Icon(Icons.close, size: AppSize.iconMd),
          tooltip: closeTooltip,
          onPressed: onClose,
          color: ink2,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(
            width: AppSize.iconButton,
            height: AppSize.iconButton,
          ),
          style: IconButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
          ),
        ),
      ],
    );
  }
}

/// `3b` 运行回顾: the result at 44px with its version badge, and the prompt
/// that produced it on one line, on the glass ink at 6%. What the user checks
/// before judging — 「反馈的是这张」.
class _RunRecap extends StatelessWidget {
  const _RunRecap({
    required this.image,
    required this.promptVersion,
    required this.label,
    required this.promptText,
  });

  final AppImage image;
  final int promptVersion;
  final String label;
  final String promptText;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final glass = GlassInk.maybeOf(context);
    final ink = glass?.ink ?? scheme.onSurface;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: ink.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.lg - 4),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm + 2),
            child: SizedBox.square(
              dimension: 44,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image(image: image.imageProvider, fit: BoxFit.cover),
                  Positioned(
                    top: 3,
                    right: 3,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: AppOverlay.imagePlate,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        'v$promptVersion',
                        style: textTheme.labelSmall!.mono.copyWith(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: AppOverlay.onImagePlate,
                          height: 1.4,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpace.s10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelSmall!.copyWith(
                    color: scheme.accentText,
                    letterSpacing: AppType.trackedLabelSpacing,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  promptText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall!.metricsOnly.copyWith(color: ink),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// `3b` 满意度块: 56 tall at r12. At rest the glass ink at 8%; chosen, the
/// accent tint with a 2px accent ring inside it, the glyph filled in the
/// accent and the label in the deep accent ink.
class _VerdictTile extends StatelessWidget {
  const _VerdictTile({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final glass = GlassInk.maybeOf(context);
    final ink = glass?.ink ?? scheme.onSurface;
    final ink2 = glass?.ink2 ?? scheme.onSurfaceVariant;
    final radius = BorderRadius.circular(AppRadius.lg - 4);

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: AnimatedContainer(
            duration: AppMotion.durationOf(context, AppMotion.state),
            height: 56,
            decoration: BoxDecoration(
              color: selected ? scheme.accentTint : ink.withValues(alpha: 0.08),
              borderRadius: radius,
              border: Border.all(
                width: 2,
                color: selected ? scheme.primary : Colors.transparent,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  selected ? selectedIcon : icon,
                  size: AppSize.iconLg,
                  color: selected ? scheme.primary : ink2,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium!.metricsOnly.copyWith(
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected ? scheme.accentText : ink,
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

/// `3b` 原因标签: a 26px pill. Off, the glass ink at 8%; on, the accent at
/// 22% with a 1px accent ring and the deep accent ink.
class _ReasonPill extends StatelessWidget {
  const _ReasonPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final glass = GlassInk.maybeOf(context);
    final ink = glass?.ink ?? scheme.onSurface;
    final radius = BorderRadius.circular(13);

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: AnimatedContainer(
            duration: AppMotion.durationOf(context, AppMotion.state),
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: selected
                  ? scheme.primary.withValues(alpha: 0.22)
                  : ink.withValues(alpha: 0.08),
              borderRadius: radius,
              border: Border.all(
                color: selected ? scheme.primary : Colors.transparent,
              ),
            ),
            // A Row, not an aligned Container: alignment makes a Container
            // fill its constraints, and under a Wrap that is the whole row.
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: textTheme.bodySmall!.metricsOnly.copyWith(
                    color: selected ? scheme.accentText : ink,
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

/// `3b`: the note at 84 tall and r10, the glass ink at 8% for a fill and a
/// 2px accent ring while focused, the count in the bottom-right corner. The
/// placeholder is drawn here rather than by the field: even a collapsed
/// decoration still draws the theme's outline inside the container.
class _NoteField extends StatelessWidget {
  const _NoteField({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final glass = GlassInk.maybeOf(context);
    final ink = glass?.ink ?? scheme.onSurface;
    final ink2 = glass?.ink2 ?? scheme.onSurfaceVariant;
    final body = textTheme.bodySmall!.metricsOnly.copyWith(height: 1.5);

    return ListenableBuilder(
      listenable: focusNode,
      builder: (context, _) => AnimatedContainer(
        duration: AppMotion.durationOf(context, AppMotion.hover),
        height: 84,
        decoration: BoxDecoration(
          color: ink.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(
            width: 2,
            color: focusNode.hasFocus ? scheme.primary : Colors.transparent,
          ),
        ),
        child: Stack(
          children: [
            Padding(
              // 9/10 inside the 2px ring, plus room under the last line for
              // the count.
              padding: const EdgeInsets.fromLTRB(8, 7, 8, 18),
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                cursorColor: scheme.primary,
                cursorWidth: 1.5,
                style: body.copyWith(color: ink),
                decoration: null,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(kResultFeedbackMaxLength),
                ],
              ),
            ),
            if (controller.text.isEmpty)
              Positioned(
                left: 8,
                top: 7,
                right: 8,
                child: IgnorePointer(
                  child: Text(
                    hint,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: body.copyWith(color: ink2),
                  ),
                ),
              ),
            Positioned(
              right: 8,
              bottom: 5,
              child: Text(
                '${controller.text.characters.length} / $kResultFeedbackMaxLength',
                style: textTheme.labelSmall!.mono.metricsOnly.copyWith(
                  fontWeight: FontWeight.w400,
                  color: ink2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `3b` 页脚: where the verdict goes, beside a history glyph.
class _FooterNote extends StatelessWidget {
  const _FooterNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final glass = GlassInk.maybeOf(context);
    final ink2 = glass?.ink2 ?? scheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.history, size: AppSize.iconSm, color: ink2),
          ),
          const SizedBox(width: AppSpace.s4),
          Expanded(
            child: Text(
              text,
              style: textTheme.labelSmall!.metricsOnly.copyWith(
                fontWeight: FontWeight.w400,
                color: ink2,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 「⌘Enter 发送」 at the footer's leading edge — Ctrl on the platforms
/// without a command key.
class _ShortcutHint extends StatelessWidget {
  const _ShortcutHint({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final glass = GlassInk.maybeOf(context);
    final ink2 = glass?.ink2 ?? scheme.onSurfaceVariant;
    final modifier = Platform.isMacOS || Platform.isIOS ? '⌘' : 'Ctrl+';

    return Text(
      l10n.optFeedbackSendShortcut(modifier),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: textTheme.labelSmall!.metricsOnly.copyWith(
        fontWeight: FontWeight.w400,
        color: ink2,
      ),
    );
  }
}

/// `2b`'s footer rule: a hairline alone, in the glass's secondary ink at a
/// hairline's weight — the refraction edge disappears on light glass.
class _Rule extends StatelessWidget {
  const _Rule();

  @override
  Widget build(BuildContext context) {
    final glass = GlassInk.maybeOf(context);
    final Color color = glass == null || glass.reduced
        ? (glass?.edge ?? Theme.of(context).colorScheme.outlineVariant)
        : glass.ink2.withValues(alpha: 0.2);
    return SizedBox(height: 1, child: ColoredBox(color: color));
  }
}
