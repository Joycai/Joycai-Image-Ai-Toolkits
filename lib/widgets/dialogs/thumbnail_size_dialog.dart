import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../app_button.dart';
import '../app_dialog.dart';

/// Smallest and largest tile the gallery grids will draw, in logical pixels.
const double kMinThumbnailSize = 80;
const double kMaxThumbnailSize = 400;

/// Adjusts the grid's tile size, live.
///
/// Shared by the workbench gallery and the file browser, which had a copy
/// each. Both copies were raw [AlertDialog]s, so neither picked up the app's
/// surface or corner radius, and the workbench one had its value declared
/// inside the [StatefulBuilder] — reinitialised on every rebuild, so the
/// handle sprang back to where the dialog opened while the grid behind it
/// kept resizing.
///
/// [onChanged] fires on every frame of the drag rather than on release: the
/// grid resizing underneath *is* the preview, so there is nothing to confirm
/// and the button only dismisses. [onChangeEnd] is where the value is meant to
/// be persisted — writing it from [onChanged] would put one database write per
/// frame of the drag.
Future<void> showThumbnailSizeDialog(
  BuildContext context, {
  required double initialSize,
  required ValueChanged<double> onChanged,
  VoidCallback? onChangeEnd,
}) {
  final l10n = AppLocalizations.of(context)!;
  // Outside the builder, so it survives the rebuilds the drag causes.
  var size = initialSize.clamp(kMinThumbnailSize, kMaxThumbnailSize);

  return AppDialog.show<void>(
    context,
    title: l10n.thumbnailSize,
    maxWidth: 360,
    content: StatefulBuilder(
      builder: (context, setState) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Slider(
            value: size,
            min: kMinThumbnailSize,
            max: kMaxThumbnailSize,
            onChanged: (v) {
              setState(() => size = v);
              onChanged(v);
            },
            onChangeEnd: (_) => onChangeEnd?.call(),
          ),
          Text('${size.toInt()}px', style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    ),
    actions: [
      AppButton(
        label: l10n.confirm,
        variant: AppButtonVariant.text,
        onPressed: () => Navigator.pop(context),
      ),
    ],
  );
}
