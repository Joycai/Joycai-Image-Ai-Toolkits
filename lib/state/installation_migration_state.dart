import 'package:flutter/foundation.dart';

import '../services/files/directory_access_service.dart';
import '../services/files/installation_migration_service.dart';

/// Bootstrap state, deliberately independent of AppState and its live database.
class InstallationMigrationState extends ChangeNotifier {
  InstallationMigrationState({
    InstallationMigrationService? service,
    DirectoryAccessService? access,
  }) : service = service ?? InstallationMigrationService(),
       _access = access ?? DirectoryAccessService.instance;

  final InstallationMigrationService service;
  final DirectoryAccessService _access;
  bool busy = false;
  bool acknowledged = false;
  bool imported = false;
  String? source;
  String? destination;
  InstallationMigrationError? error;
  bool ioError = false;

  void acknowledge(bool value) {
    acknowledged = value;
    notifyListeners();
  }

  Future<void> selectSource(String title) async {
    if (busy || imported) return;
    busy = true;
    error = null;
    ioError = false;
    notifyListeners();
    try {
      // Explicit system selection grants only the chosen source. The native
      // session retains it through copying, including reading the SQLite WAL.
      final picked = await _access.pickDirectory(dialogTitle: title, readOnly: true);
      if (picked != null) {
        source = picked;
        acknowledged = false;
      }
    } catch (_) {
      ioError = true;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> importSelected() async {
    if (busy || imported || !acknowledged || source == null) return;
    busy = true;
    error = null;
    ioError = false;
    notifyListeners();
    try {
      destination = await service.importDirectory(source!);
      imported = true;
    } on InstallationMigrationException catch (exception) {
      error = exception.reason;
    } catch (_) {
      // Do not expose SQLite errors or file contents (credentials) in UI/logs.
      ioError = true;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<bool> finish() async {
    if (busy) return false;
    busy = true;
    notifyListeners();
    try {
      await service.finishChoice();
      return true;
    } catch (_) {
      ioError = true;
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
