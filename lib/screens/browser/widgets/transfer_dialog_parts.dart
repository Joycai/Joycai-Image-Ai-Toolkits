import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../core/app_semantic_colors.dart';
import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/browser_file.dart';

/// Pieces shared by the file browser's transfer and folder dialogs — the
/// staging paste, the folder move, the folder delete and the AI rename
/// (`B1b 1b`–`1f`). The spec draws the conflict → progress → finished chain as
/// one shell with one set of stat tiles, so the shell lives here once.

/// The mood a plate, badge or note is drawn in.
///
/// Status tones take the opaque semantic containers, never a wash of the
/// status hue: they land on the panel, the column and the card alike.
enum TransferTone {
  /// `--tint` under `--p-deep`, glyph in `--p`.
  accent,

  /// `--ok-bg` / `--ok-ink`.
  ok,

  /// `--warn-bg` / `--warn-ink`.
  warn,

  /// `--info-bg` / `--info-ink`.
  info,

  /// `--err-bg` / `--err-ink`.
  err,

  /// `--card` under `--ink2` — a settled, uncoloured outcome.
  neutral,

  /// `--track` under `--ink2` — a quiet badge.
  track,
}

/// Background, text ink and glyph colour for [tone].
@immutable
class TransferToneColors {
  const TransferToneColors({required this.background, required this.ink, required this.glyph});

  final Color background;
  final Color ink;
  final Color glyph;

  static TransferToneColors of(BuildContext context, TransferTone tone) {
    final scheme = Theme.of(context).colorScheme;
    final semantic = context.semantic;
    return switch (tone) {
      TransferTone.accent =>
        TransferToneColors(background: scheme.accentTint, ink: scheme.onAccentTint, glyph: scheme.primary),
      TransferTone.ok => TransferToneColors(
          background: semantic.successContainer,
          ink: semantic.onSuccessContainer,
          glyph: semantic.success,
        ),
      TransferTone.warn => TransferToneColors(
          background: semantic.warningContainer,
          ink: semantic.onWarningContainer,
          glyph: semantic.warning,
        ),
      TransferTone.info => TransferToneColors(
          background: semantic.infoContainer,
          ink: semantic.onInfoContainer,
          glyph: semantic.info,
        ),
      TransferTone.err => TransferToneColors(
          background: scheme.errorContainer,
          ink: scheme.onErrorContainer,
          glyph: scheme.error,
        ),
      TransferTone.neutral => TransferToneColors(
          background: scheme.surfaceContainer,
          ink: scheme.onSurfaceVariant,
          glyph: scheme.onSurfaceVariant,
        ),
      TransferTone.track => TransferToneColors(
          background: scheme.surfaceContainerHighest,
          ink: scheme.onSurfaceVariant,
          glyph: scheme.onSurfaceVariant,
        ),
    };
  }
}

/// A dialog heading for [AppDialog.titleWidget]: a 44px r10 plate holding a
/// 24px glyph, the 16/600 title, and a subtitle line that is mono by default
/// (counts, routes, elapsed time) with an optional badge after it.
///
/// Exists because `AppDialog`'s own heading derives its plate from a hue at
/// 12%, and these dialogs need the opaque status containers (`ok-bg`,
/// `warn-bg`, `card`) and a mono subtitle.
class TransferDialogHeading extends StatelessWidget {
  const TransferDialogHeading({
    super.key,
    required this.icon,
    required this.tone,
    required this.title,
    this.subtitle,
    this.subtitleMono = true,
    this.subtitleTooltip,
    this.badge,
    this.trailing,
  });

  final IconData icon;
  final TransferTone tone;
  final String title;
  final String? subtitle;
  final bool subtitleMono;

  /// The untruncated subtitle, when [subtitle] is a shortened path.
  final String? subtitleTooltip;

  /// Sits after the subtitle on its line — `across drives`.
  final Widget? badge;

  /// The heading's trailing corner — the rename dialog's close button.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final colors = TransferToneColors.of(context, tone);

    Widget? sub;
    if (subtitle != null) {
      final base = textTheme.bodySmall!.copyWith(color: scheme.onSurfaceVariant);
      Widget text = Text(
        subtitle!,
        style: subtitleMono ? base.mono : base,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
      if (subtitleTooltip != null) text = Tooltip(message: subtitleTooltip!, child: text);
      sub = Row(
        children: [
          Flexible(child: text),
          if (badge != null) ...[const SizedBox(width: AppSpace.s6), badge!],
        ],
      );
    }

    return Row(
      children: [
        Container(
          width: AppSize.touch,
          height: AppSize.touch,
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          child: Icon(icon, size: 24, color: colors.glyph),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: textTheme.titleLarge, maxLines: 2, overflow: TextOverflow.ellipsis),
              if (sub != null) ...[const SizedBox(height: 2), sub],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
      ],
    );
  }
}

/// The 32px hairline close square a large dialog carries in its heading.
class TransferDialogCloseButton extends StatelessWidget {
  const TransferDialogCloseButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      icon: const Icon(Icons.close, size: AppSize.iconMd),
      tooltip: AppLocalizations.of(context)?.close,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: AppSize.iconButton, height: AppSize.iconButton),
      style: IconButton.styleFrom(
        foregroundColor: scheme.onSurfaceVariant,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
    );
  }
}

/// A small r4 status badge — a conflict reason, `across drives`, `Undecided`.
class TransferBadge extends StatelessWidget {
  const TransferBadge({
    super.key,
    required this.label,
    required this.tone,
    this.icon,
    this.outlined = false,
    this.mono = false,
  });

  final String label;
  final TransferTone tone;
  final IconData? icon;

  /// A 1px edge in the tone's glyph colour, for a badge laid on a row that is
  /// already painted in the same container (a conflict row on `err-bg`).
  final bool outlined;

  final bool mono;

  @override
  Widget build(BuildContext context) {
    final colors = TransferToneColors.of(context, tone);
    final style = Theme.of(context).textTheme.labelSmall!.copyWith(color: colors.ink);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s6, vertical: 2),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: outlined ? Border.all(color: colors.glyph.withValues(alpha: AppAlpha.edge)) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: colors.glyph),
            const SizedBox(width: AppSpace.s4),
          ],
          Flexible(
            child: Text(
              label,
              style: mono ? style.mono : style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// A tinted r6 strip carrying one sentence — the cross-drive rollback note,
/// "can be restored from the trash", "restored from the last session".
class TransferNote extends StatelessWidget {
  const TransferNote({
    super.key,
    required this.text,
    required this.tone,
    required this.icon,
    this.compact = false,
  });

  final String text;
  final TransferTone tone;
  final IconData icon;

  /// `4/8` padding and one line, for a note inside a column section.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = TransferToneColors.of(context, tone);
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: compact
          ? const EdgeInsets.symmetric(horizontal: 8, vertical: AppSpace.s4)
          : const EdgeInsets.symmetric(horizontal: AppSpace.s10, vertical: 8),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        crossAxisAlignment: compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: compact ? 0 : 1),
            child: Icon(icon, size: AppSize.iconSm, color: colors.glyph),
          ),
          const SizedBox(width: AppSpace.s6),
          Expanded(
            child: Text(
              text,
              maxLines: compact ? 1 : null,
              overflow: compact ? TextOverflow.ellipsis : null,
              style: (compact ? textTheme.labelSmall : textTheme.bodySmall)!.copyWith(
                color: colors.ink,
                height: compact ? null : AppType.proseHeight,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One of the three counts a transfer ends with (`1c`): r10, pad 10, the
/// number in mono 20/600, an 11px label under it.
///
/// A zero is drawn neutral whatever its tone. An untouched counter in green
/// or red would be as loud as a real result.
class TransferStatCell extends StatelessWidget {
  const TransferStatCell({
    super.key,
    required this.value,
    required this.label,
    required this.tone,
  });

  final int value;
  final String label;
  final TransferTone tone;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = TransferToneColors.of(context, value == 0 ? TransferTone.neutral : tone);

    return Container(
      padding: const EdgeInsets.all(AppSpace.s10),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$value',
            style: textTheme.headlineSmall!.mono.copyWith(color: colors.ink, height: AppType.displayHeight),
          ),
          const SizedBox(height: AppSpace.s4),
          Text(
            label,
            style: textTheme.labelSmall!.copyWith(color: colors.ink),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Transferred · Skipped · Failed, the same three tiles in every state that
/// reports an outcome.
class TransferStatTiles extends StatelessWidget {
  const TransferStatTiles({
    super.key,
    required this.transferred,
    required this.skipped,
    required this.failed,
  });

  final int transferred;
  final int skipped;
  final int failed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TransferStatCell(value: transferred, label: l10n.pasteStatSucceeded, tone: TransferTone.ok),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TransferStatCell(value: skipped, label: l10n.pasteStatSkipped, tone: TransferTone.neutral),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TransferStatCell(value: failed, label: l10n.pasteStatFailed, tone: TransferTone.err),
        ),
      ],
    );
  }
}

/// The 4px track-and-accent progress bar, easing between readings so a burst
/// of small files does not stutter it.
class TransferProgressBar extends StatelessWidget {
  const TransferProgressBar({super.key, required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: fraction.clamp(0.0, 1.0)),
        duration: AppMotion.durationOf(context, AppMotion.state),
        curve: AppMotion.enter,
        builder: (context, value, _) => LinearProgressIndicator(
          value: value,
          minHeight: 4,
          color: scheme.primary,
          backgroundColor: scheme.surfaceContainerHighest,
        ),
      ),
    );
  }
}

/// A file's r6 thumbnail: the picture for an image, the category glyph
/// otherwise. Decoded at twice its size and no more.
class TransferThumb extends StatelessWidget {
  const TransferThumb({super.key, required this.path, this.size = 32, this.imageProvider});

  final String path;
  final double size;

  /// Overrides the provider built from [path] — the staging list passes the
  /// one its [BrowserFile] already holds.
  final ImageProvider? imageProvider;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final category = BrowserFile.categoryOf(path);
    final glyph = Icon(category.icon, size: size * 0.44, color: scheme.onSurfaceVariant);

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Container(
        width: size,
        height: size,
        color: scheme.surfaceContainerHighest,
        child: category == FileCategory.image
            ? Image(
                image: ResizeImage(imageProvider ?? FileImage(File(path)), width: (size * 2).round()),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) => glyph,
              )
            : glyph,
      ),
    );
  }
}

/// Last two segments of a path — a dialog subtitle or a column has no room
/// for the rest, and the leading half is the same for every entry anyway.
String transferShortPath(String path) {
  final parts = p.split(path).where((s) => s.isNotEmpty).toList();
  if (parts.length <= 2) return path;
  return parts.sublist(parts.length - 2).join(' / ');
}
