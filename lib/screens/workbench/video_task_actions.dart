import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../state/app_state.dart';
import '../../widgets/ui/app_snackbar.dart';

/// Shared presentation for all result-to-workbench entrances. Route choice and
/// source ownership stay in AppState; no entry silently chooses a paid model.
Future<void> openVideoTask(BuildContext context, String path, String mode) async {
  final app = context.read<AppState>();
  final feedbackContext = Navigator.of(context, rootNavigator: true).context;
  final l10n = AppLocalizations.of(context)!;
  try {
    final supported = await app.openVideoInTaskMode(path: path, mode: mode);
    if (!supported && feedbackContext.mounted) {
      final models = app.videoModels
          .where((model) {
            final contract = app.generationSchemaForModel(model).contract;
            return mode == 'edit' ? contract.videoEdit != null : contract.videoExtend != null;
          })
          .map((m) => m.modelName)
          .join(', ');
      AppSnackBar.warning(
        feedbackContext,
        l10n.modelDoesNotSupportVideoEdit(models.isEmpty ? l10n.noModelsConfigured : models),
      );
    }
  } catch (error) {
    if (feedbackContext.mounted) AppSnackBar.error(feedbackContext, l10n.importFailed('$error'));
  }
}
