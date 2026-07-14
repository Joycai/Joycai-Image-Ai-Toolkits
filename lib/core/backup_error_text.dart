import '../l10n/app_localizations.dart';
import '../services/database_service.dart';

/// User-facing text for a failed backup import.
///
/// Turns the typed [BackupFormatException] rejections into actionable messages
/// and falls back to the raw error for anything unexpected. Shared by the
/// settings screen and the setup wizard so both explain a bad file the same way.
String backupImportErrorText(AppLocalizations l10n, Object error) {
  if (error is BackupFormatException) {
    switch (error.error) {
      case BackupFormatError.promptsOnly:
        return l10n.importErrorPromptsOnly;
      case BackupFormatError.notABackup:
        return l10n.importErrorNotABackup;
      case BackupFormatError.newerSchema:
        return l10n.importErrorNewerSchema;
    }
  }
  return l10n.importFailed(error.toString());
}
