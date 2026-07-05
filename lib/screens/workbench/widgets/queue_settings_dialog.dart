import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../state/app_state.dart';
import 'safety_settings_section.dart';

/// Queue/output settings dialog shared by the image and video workbenches:
/// concurrency, retry count, filename prefix and Gemini safety thresholds.
Future<void> showQueueSettingsDialog(BuildContext context) {
  final prefixController = TextEditingController(
    text: Provider.of<AppState>(context, listen: false).imagePrefix,
  );

  return showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) {
        final appState = Provider.of<AppState>(context);
        final l10n = AppLocalizations.of(context)!;
        return AlertDialog(
          title: Text(l10n.queueSettings),
          content: SizedBox(
            width: 340,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.concurrencyLimit(appState.concurrencyLimit)),
                  Slider(
                    value: appState.concurrencyLimit.toDouble(),
                    min: 1,
                    max: 8,
                    divisions: 7,
                    onChanged: (v) {
                      appState.setConcurrency(v.toInt());
                      setDialogState(() {});
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(l10n.retryCount(appState.retryCount)),
                  Slider(
                    value: appState.retryCount.toDouble(),
                    min: 0,
                    max: 5,
                    divisions: 5,
                    onChanged: (v) {
                      appState.setRetryCount(v.toInt());
                      setDialogState(() {});
                    },
                  ),
                  const Divider(),
                  const SizedBox(height: 8),
                  Text(l10n.filenamePrefix,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: prefixController,
                    decoration: InputDecoration(
                      isDense: true,
                      border: const OutlineInputBorder(),
                      hintText: l10n.prefixHint,
                    ),
                    onChanged: (v) => appState.setImagePrefix(v),
                  ),
                  const SizedBox(height: 8),
                  const Divider(),
                  const SizedBox(height: 8),
                  const SafetySettingsSection(),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.close),
            ),
          ],
        );
      },
    ),
  ).then((_) => prefixController.dispose());
}
