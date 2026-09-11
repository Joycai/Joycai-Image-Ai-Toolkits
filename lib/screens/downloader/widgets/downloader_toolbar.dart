import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../state/downloader_state.dart';
import '../../../widgets/app_field_size.dart';
import '../../../widgets/app_switch.dart';
import '../../../widgets/chat_model_selector.dart';
import '../../../widgets/glass/glass_controls.dart';
import 'downloader_inputs.dart';

export 'downloader_advanced_dialog.dart' show showDownloaderAdvancedDialog;

/// The downloader's input bar (`B3 · 1a`, `1c`).
///
/// The fields sit in the order the user acts — address, what to look for, the
/// model — with the primary action at the end of the row. One 88px row when
/// everything fits at its measured minimum; otherwise it folds (`1c`) into a
/// title row carrying the actions over uncaptioned field rows, which fold again
/// one field at a time if a row still does not fit.
class DownloaderToolbar extends StatelessWidget {
  final TextEditingController urlController;
  final TextEditingController requirementController;
  final bool isAnalyzing;
  final VoidCallback onAnalyze;
  final VoidCallback onOpenAdvanced;

  const DownloaderToolbar({
    super.key,
    required this.urlController,
    required this.requirementController,
    required this.isAnalyzing,
    required this.onAnalyze,
    required this.onOpenAdvanced,
  });

  static const double _height = 88;
  static const double _plate = 44;
  static const double _titleMinWidth = 140;
  static const double _modelWidth = 200;
  static const double _foldedModelWidth = 220;

  /// The line under the title: what the screen is doing right now.
  String? _subtitle(AppLocalizations l10n, DownloaderState state) {
    if (isAnalyzing) return l10n.analyzing;
    if (state.isManualHtml) {
      if (state.manualHtml.isEmpty) return l10n.manualHtmlMode;
      return '${l10n.manualHtmlMode} · ${(state.manualHtml.length / 1024).toStringAsFixed(1)} KB';
    }
    final found = state.discoveredImages.length;
    if (found == 0) return null;
    return l10n.downloaderFoundCount(found);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = context.watch<DownloaderState>();
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final subtitle = _subtitle(l10n, state);
    final titleStyle = textTheme.titleLarge!;
    final subtitleStyle = textTheme.bodySmall!.mono.copyWith(
      color: isAnalyzing ? scheme.accentText : scheme.onSurfaceVariant,
      fontWeight: isAnalyzing ? FontWeight.w600 : FontWeight.w400,
    );
    // Monospace: an address, not prose — a typo in a long path is something
    // you can see in fixed widths.
    final urlStyle = textTheme.bodySmall!.mono;
    final bodyStyle = textTheme.bodySmall!;

    final urlField = TextField(
      controller: urlController,
      style: urlStyle,
      keyboardType: TextInputType.url,
      textAlignVertical: TextAlignVertical.center,
      decoration: downloaderFieldDecoration(
        context,
        style: urlStyle,
        hint: l10n.websiteUrlHint,
        icon: Icons.link,
      ),
    );

    final requirementField = TextField(
      controller: requirementController,
      style: bodyStyle,
      textAlignVertical: TextAlignVertical.center,
      onSubmitted: (_) {
        if (!isAnalyzing) onAnalyze();
      },
      decoration: downloaderFieldDecoration(context, style: bodyStyle, hint: l10n.whatToFindHint),
    );

    final modelSelector = ChatModelSelector(
      selectedModelId: state.selectedModelDbId,
      label: l10n.analysisModel,
      size: AppFieldSize.regular,
      decoration: InputDecoration(filled: true, fillColor: scheme.surface),
      onChanged: (v) => state.setState(selectedModelDbId: v),
    );

    final gear = DownloaderActionButton(
      icon: Icons.settings_outlined,
      tooltip: l10n.advancedOptions,
      height: AppSize.large,
      iconSize: AppSize.iconLg,
      foreground: scheme.onSurfaceVariant,
      onPressed: onOpenAdvanced,
    );

    final title = _TitleBlock(
      title: l10n.imageDownloader,
      subtitle: subtitle,
      titleStyle: titleStyle,
      subtitleStyle: subtitleStyle,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final available = constraints.maxWidth - 2 * kDownloaderGutter;
          double measure(String text, TextStyle style) => measureGlassText(context, text, style);

          final titleWidth = math
              .max(
                _titleMinWidth,
                math.max(
                  measure(l10n.imageDownloader, titleStyle),
                  subtitle == null ? 0.0 : measure(subtitle, subtitleStyle),
                ),
              )
              .ceilToDouble();
          final findWidth = _FindImagesButton.widthFor(context);
          // A field is squeezed past use once its own hint no longer fits.
          final urlMin = AppSize.control + measure(l10n.websiteUrlHint, urlStyle) + AppSpace.s10;
          final whatMin = AppSpace.s10 + measure(l10n.whatToFindHint, bodyStyle) + AppSpace.s10;

          final oneRow = _plate +
              titleWidth +
              urlMin +
              whatMin +
              _modelWidth +
              findWidth +
              AppSize.large +
              kDownloaderGap * 6;

          if (oneRow <= available) {
            // The buttons drop by the caption's height so their centres meet
            // the input boxes' centres (`margin-top 14`), measured rather than
            // pinned so a larger text scale keeps them aligned.
            final captionBlock = downloaderLineHeight(context, downloaderCaptionStyle(context)) + AppSpace.s4;
            return Container(
              constraints: const BoxConstraints(minHeight: _height),
              padding: const EdgeInsets.symmetric(horizontal: kDownloaderGutter, vertical: AppSpace.s10),
              alignment: Alignment.center,
              child: Row(
                children: [
                  const _TitlePlate(size: _plate, glyph: 24),
                  const SizedBox(width: kDownloaderGap),
                  SizedBox(width: titleWidth, child: title),
                  const SizedBox(width: kDownloaderGap),
                  Expanded(flex: 7, child: _CaptionedField(caption: l10n.websiteUrl, child: urlField)),
                  const SizedBox(width: kDownloaderGap),
                  Expanded(flex: 5, child: _CaptionedField(caption: l10n.whatToFind, child: requirementField)),
                  const SizedBox(width: kDownloaderGap),
                  SizedBox(
                    width: _modelWidth,
                    child: _CaptionedField(caption: l10n.analysisModel, child: modelSelector),
                  ),
                  const SizedBox(width: kDownloaderGap),
                  Padding(
                    padding: EdgeInsets.only(top: captionBlock),
                    child: _FindImagesButton(analyzing: isAnalyzing, onPressed: onAnalyze),
                  ),
                  const SizedBox(width: kDownloaderGap),
                  Padding(padding: EdgeInsets.only(top: captionBlock), child: gear),
                ],
              ),
            );
          }

          // Folded (`1c`): 12 + 40 + 10 + 32 + 12.
          final labelledFind = AppSize.large +
                  AppSpace.s10 +
                  measure(l10n.imageDownloader, titleStyle) +
                  kDownloaderGap +
                  findWidth +
                  AppSpace.s6 +
                  AppSize.large <=
              available;

          Widget sized(Widget child) => SizedBox(height: AppSize.control, child: child);
          const gap = SizedBox(width: kDownloaderGap);
          final rows = <Widget>[];
          if (urlMin + whatMin + _foldedModelWidth + 2 * kDownloaderGap <= available) {
            rows.add(sized(Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 7, child: urlField),
                gap,
                Expanded(flex: 5, child: requirementField),
                gap,
                SizedBox(width: _foldedModelWidth, child: modelSelector),
              ],
            )));
          } else if (whatMin + _foldedModelWidth + kDownloaderGap <= available) {
            rows
              ..add(sized(urlField))
              ..add(sized(Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: requirementField),
                  gap,
                  SizedBox(width: _foldedModelWidth, child: modelSelector),
                ],
              )));
          } else {
            rows
              ..add(sized(urlField))
              ..add(sized(requirementField))
              ..add(sized(modelSelector));
          }

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: kDownloaderGutter, vertical: kDownloaderGap),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: AppSize.large,
                  child: Row(
                    children: [
                      const _TitlePlate(size: AppSize.large, glyph: AppSize.iconLg),
                      const SizedBox(width: AppSpace.s10),
                      Expanded(child: title),
                      const SizedBox(width: kDownloaderGap),
                      _FindImagesButton(
                        analyzing: isAnalyzing,
                        onPressed: onAnalyze,
                        iconOnly: !labelledFind,
                      ),
                      const SizedBox(width: AppSpace.s6),
                      gear,
                    ],
                  ),
                ),
                for (final row in rows) ...[
                  const SizedBox(height: AppSpace.s10),
                  row,
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The screen's glyph on the accent wash (`44 r10 tint cloud_download`).
class _TitlePlate extends StatelessWidget {
  const _TitlePlate({required this.size, required this.glyph});

  final double size;
  final double glyph;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: scheme.accentTint,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Icon(Icons.cloud_download_outlined, size: glyph, color: scheme.primary),
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({
    required this.title,
    required this.subtitle,
    required this.titleStyle,
    required this.subtitleStyle,
  });

  final String title;
  final String? subtitle;
  final TextStyle titleStyle;
  final TextStyle subtitleStyle;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: titleStyle),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: subtitleStyle,
          ),
        ],
      ],
    );
  }
}

/// An 11px caption over a 32px box.
class _CaptionedField extends StatelessWidget {
  const _CaptionedField({required this.caption, required this.child});

  final String caption;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          caption,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: downloaderCaptionStyle(context),
        ),
        const SizedBox(height: AppSpace.s4),
        SizedBox(height: AppSize.control, child: child),
      ],
    );
  }
}

/// `查找图片`: the screen's one solid accent, 40 at r10 with a ring-coloured
/// drop. While analyzing it is the track under secondary ink with a 14px
/// spinner, and does nothing.
///
/// Sized to the wider of its two labels so the row does not reflow when an
/// analysis starts.
class _FindImagesButton extends StatelessWidget {
  const _FindImagesButton({
    required this.analyzing,
    required this.onPressed,
    this.iconOnly = false,
  });

  final bool analyzing;
  final VoidCallback onPressed;
  final bool iconOnly;

  static const double _pad = AppSpace.s16;
  static const double _glyph = 18;
  static const double _glyphGap = 8;

  static TextStyle _labelStyle(BuildContext context) =>
      Theme.of(context).textTheme.labelLarge!.metricsOnly.copyWith(fontWeight: FontWeight.w600);

  static double widthFor(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final style = _labelStyle(context);
    final text = math.max(
      measureGlassText(context, l10n.findImages, style),
      measureGlassText(context, l10n.analyzing, style),
    );
    return (_pad + _glyph + _glyphGap + text + _pad).ceilToDouble();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final enabled = !analyzing;
    final Color ground = enabled ? scheme.primary : scheme.surfaceContainerHighest;
    final Color ink = enabled ? scheme.onPrimary : scheme.onSurfaceVariant;
    final label = analyzing ? l10n.analyzing : l10n.findImages;
    final radius = BorderRadius.circular(AppRadius.control);

    final glyph = SizedBox.square(
      dimension: _glyph,
      child: analyzing
          ? Center(
              child: SizedBox.square(
                dimension: AppSize.iconSm,
                child: CircularProgressIndicator(strokeWidth: 2, color: ink),
              ),
            )
          : Icon(Icons.travel_explore, size: _glyph, color: ink),
    );

    final Widget content = iconOnly
        ? SizedBox.square(dimension: AppSize.large, child: Center(child: glyph))
        : SizedBox(
            width: widthFor(context),
            height: AppSize.large,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: _pad),
              child: Row(
                children: [
                  glyph,
                  const SizedBox(width: _glyphGap),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: _labelStyle(context).copyWith(color: ink),
                    ),
                  ),
                ],
              ),
            ),
          );

    Widget button = AnimatedContainer(
      duration: AppMotion.durationOf(context, AppMotion.state),
      curve: AppMotion.enter,
      decoration: BoxDecoration(
        color: ground,
        borderRadius: radius,
        boxShadow: enabled
            ? [BoxShadow(color: scheme.accentRing, blurRadius: 12, offset: const Offset(0, 4))]
            : const [],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: radius,
          hoverColor: ink.withValues(alpha: 0.08),
          splashColor: ink.withValues(alpha: 0.12),
          child: content,
        ),
      ),
    );
    if (iconOnly) button = Tooltip(message: label, child: button);
    return Semantics(
      button: true,
      enabled: enabled,
      label: iconOnly ? label : null,
      child: button,
    );
  }
}

/// The 40px strip under the toolbar (`B3 · 1a`, `1c`): manual-HTML mode with
/// its paste and clear, save-origin-HTML, and the logs switch at the far end.
///
/// Paste and clear are always drawn and disabled while manual mode is off, so
/// the strip does not reflow under the pointer when it is switched. The three
/// actions give up their labels, by measurement, before anything else goes.
class DownloaderOptionsStrip extends StatelessWidget {
  final bool isAnalyzing;
  final bool showLogs;
  final VoidCallback onToggleLogs;
  final VoidCallback onSaveHtml;
  final VoidCallback onPasteHtml;

  const DownloaderOptionsStrip({
    super.key,
    required this.isAnalyzing,
    required this.showLogs,
    required this.onToggleLogs,
    required this.onSaveHtml,
    required this.onPasteHtml,
  });

  static const double height = AppSize.large;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = context.watch<DownloaderState>();
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final manual = state.isManualHtml;

    final manualStyle = textTheme.bodySmall!.copyWith(
      color: manual ? scheme.accentText : scheme.onSurfaceVariant,
      fontWeight: manual ? FontWeight.w500 : FontWeight.w400,
    );
    final logsStyle = textTheme.bodySmall!.copyWith(color: scheme.onSurfaceVariant);

    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: kDownloaderGutter),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          double action(String label) =>
              DownloaderActionButton.widthFor(context, label: label, height: AppSize.compact);
          final fullWidth = measureGlassText(context, l10n.manualHtmlMode, manualStyle.copyWith(fontWeight: FontWeight.w500)) +
              AppSpace.s6 +
              AppSwitch.size.width +
              kDownloaderGap +
              action(l10n.pasteFromClipboard) +
              AppSpace.s4 +
              action(l10n.clear) +
              AppSpace.s10 * 2 +
              1 +
              action(l10n.saveOriginHtml) +
              AppSpace.s16 +
              measureGlassText(context, l10n.logs, logsStyle) +
              AppSpace.s6 +
              AppSwitch.size.width;
          final labels = fullWidth <= constraints.maxWidth;

          return Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        l10n.manualHtmlMode,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: manualStyle,
                      ),
                    ),
                    const SizedBox(width: AppSpace.s6),
                    AppSwitch(
                      value: manual,
                      onChanged: (v) => state.setState(isManualHtml: v),
                    ),
                    const SizedBox(width: kDownloaderGap),
                    DownloaderActionButton(
                      icon: Icons.content_paste,
                      label: labels ? l10n.pasteFromClipboard : null,
                      tooltip: labels ? null : l10n.pasteFromClipboard,
                      height: AppSize.compact,
                      onPressed: manual ? onPasteHtml : null,
                    ),
                    const SizedBox(width: AppSpace.s4),
                    DownloaderActionButton(
                      icon: Icons.clear,
                      label: labels ? l10n.clear : null,
                      tooltip: labels ? null : l10n.clear,
                      height: AppSize.compact,
                      outlined: false,
                      foreground: scheme.error,
                      onPressed: manual && state.manualHtml.isNotEmpty
                          ? () => state.setState(manualHtml: '')
                          : null,
                    ),
                    const SizedBox(width: AppSpace.s10),
                    SizedBox(width: 1, height: 20, child: ColoredBox(color: scheme.outlineVariant)),
                    const SizedBox(width: AppSpace.s10),
                    DownloaderActionButton(
                      icon: Icons.html,
                      label: labels ? l10n.saveOriginHtml : null,
                      tooltip: labels ? null : l10n.saveOriginHtml,
                      height: AppSize.compact,
                      onPressed: isAnalyzing ? null : onSaveHtml,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.s16),
              Text(l10n.logs, maxLines: 1, style: logsStyle),
              const SizedBox(width: AppSpace.s6),
              // Disabled until there is something to read.
              AppSwitch(
                value: showLogs && state.logs.isNotEmpty,
                onChanged: state.logs.isEmpty ? null : (_) => onToggleLogs(),
              ),
            ],
          );
        },
      ),
    );
  }
}
