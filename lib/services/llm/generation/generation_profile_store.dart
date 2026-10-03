import '../../db/database_service.dart';

/// Optional user choice, stored separately from derived model capabilities.
/// Existing settings participate in backups; no database schema change is needed.
class GenerationProfileStore {
  static String key(int modelRowId) => 'generation_profile.$modelRowId';

  static Future<String?> read(DatabaseService database, int? modelRowId) async {
    if (modelRowId == null) return null;
    final value = await database.getSetting(key(modelRowId));
    return value == null || value.isEmpty ? null : value;
  }

  static Future<void> write(DatabaseService database, int modelRowId, String? profile) =>
      database.saveSetting(key(modelRowId), profile ?? '');
}
