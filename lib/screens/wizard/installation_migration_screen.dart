import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../services/files/installation_migration_service.dart';
import '../../state/installation_migration_state.dart';
import '../../widgets/ui/app_button.dart';

/// Rendered before the application's database, watchers or queue are opened.
class InstallationMigrationScreen extends StatelessWidget {
  const InstallationMigrationScreen({super.key, required this.state, required this.onContinue});

  final InstallationMigrationState state;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpace.s28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.installationImportTitle,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: AppSpace.s16),
                    Text(
                      state.imported
                          ? l10n.installationImportSuccess
                          : l10n.installationImportDescription,
                    ),
                    const SizedBox(height: AppSpace.s16),
                    if (!state.imported) ...[
                      AppButton(
                        variant: AppButtonVariant.secondary,
                        label: l10n.installationImportSelect,
                        icon: Icons.folder_open,
                        onPressed: state.busy
                            ? null
                            : () => state.selectSource(l10n.installationImportSelect),
                      ),
                      if (state.source != null) ...[
                        const SizedBox(height: AppSpace.s10),
                        SelectableText(state.source!),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(l10n.installationImportAcknowledge),
                          value: state.acknowledged,
                          onChanged: state.busy
                              ? null
                              : (value) => state.acknowledge(value ?? false),
                        ),
                      ],
                    ],
                    if (state.destination != null) ...[
                      SelectableText(state.destination!),
                      const SizedBox(height: AppSpace.s16),
                    ],
                    if (state.error != null || state.ioError) ...[
                      Text(switch (state.error) {
                        InstallationMigrationError.invalidSource =>
                          l10n.installationImportInvalidSource,
                        InstallationMigrationError.newerSchema =>
                          l10n.installationImportNewerSchema,
                        InstallationMigrationError.sourceChanged =>
                          l10n.installationImportSourceChanged,
                        InstallationMigrationError.invalidDatabase =>
                          l10n.installationImportInvalidDatabase,
                        null => l10n.installationImportIoError,
                      }, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      const SizedBox(height: AppSpace.s10),
                    ],
                    if (state.busy) ...[
                      const LinearProgressIndicator(),
                      const SizedBox(height: AppSpace.s10),
                      Text(l10n.installationImportWorking),
                      const SizedBox(height: AppSpace.s10),
                    ],
                    Wrap(
                      spacing: AppSpace.s10,
                      runSpacing: AppSpace.s10,
                      alignment: WrapAlignment.end,
                      children: [
                        if (!state.imported)
                          AppButton(
                            label: l10n.installationImportStart,
                            onPressed: state.busy || !state.acknowledged || state.source == null
                                ? null
                                : state.importSelected,
                          ),
                        AppButton(
                          label: state.imported
                              ? l10n.installationImportContinue
                              : l10n.installationImportSkip,
                          variant: state.imported
                              ? AppButtonVariant.primary
                              : AppButtonVariant.text,
                          onPressed: state.busy
                              ? null
                              : () async {
                                  if (await state.finish()) onContinue();
                                },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
