import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/app_paths.dart';
import '../../models/llm_channel.dart';
import '../../models/llm_model.dart';
import '../../models/pricing_group.dart';
import '../../models/prompt.dart';
import '../../models/prompt_history_entry.dart';
import '../../models/tag.dart';
import '../../models/task_item.dart';
import '../../models/token_usage.dart';
import '../../models/usage_checkpoint.dart';
import '../llm/channel_routes.dart';
import 'database_migrations.dart';
import 'repositories/cookie_repository.dart';
import 'repositories/image_layer_repository.dart';
import 'repositories/model_repository.dart';
import 'repositories/prompt_repository.dart';
import 'repositories/task_repository.dart';
import 'repositories/usage_repository.dart';

/// Why a backup file was rejected before any data was touched.
enum BackupFormatError {
  /// A prompt-library export was passed to the full-backup restore.
  promptsOnly,

  /// The file carries none of the tables a full backup is made of.
  notABackup,

  /// Written by a newer app whose schema this build cannot read.
  newerSchema,
}

/// Thrown by [DatabaseService.restoreBackup] when a file cannot be restored.
///
/// Raised before the restore transaction opens, so the database is untouched.
class BackupFormatException implements Exception {
  BackupFormatException(this.error, {this.fileVersion, this.appVersion});

  final BackupFormatError error;
  final int? fileVersion;
  final int? appVersion;

  @override
  String toString() => 'BackupFormatException(${error.name})';
}

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();

  /// Per-instance, not static: the default instance holds the app's one real
  /// database, while a [DatabaseService.forDatabase] holds only what it was
  /// handed. Static fields here would make that seam a no-op.
  Database? _database;
  Future<Database>? _databaseFuture;

  /// Schema version of this build. Also stamped into full backups so a file
  /// from a newer app can be rejected instead of failing mid-restore.
  static const int dbVersion = 47;

  /// Settings holding absolute paths from the machine that made the backup.
  /// Excluded when the user opts out of directories.
  static const Set<String> _directorySettingKeys = {
    'output_directory',
    'browser_source_directories',
    'browser_active_directories',
    'result_cache_directory',
  };

  /// Settings holding a credential. Blanked on export, like channel keys and
  /// cookies, and kept from the live database on restore when the file's copy
  /// is blank.
  static const Set<String> secretSettingKeys = {'proxy_password'};

  /// Table keys that only a full backup carries.
  static const Set<String> _backupTableKeys = {
    'settings',
    'llm_channels',
    'llm_models',
    'fee_groups',
    'downloader_cookies',
    'token_usage',
    'source_directories',
  };

  factory DatabaseService() => _instance;

  DatabaseService._internal();

  /// A service over a database the caller already opened — the seam every
  /// injectable state class, service and repository ultimately reaches.
  ///
  /// The default instance is process-wide *and* sits on one real file, so two
  /// test files running at once (`flutter test` gives each its own isolate,
  /// all sharing the filesystem) contend for the same write lock; that race is
  /// why `test/support/private_data_dir.dart` exists. A test that builds its
  /// own database and hands it here touches no file at all:
  ///
  /// ```dart
  /// final db = await openTestDatabase();  // test/support/in_memory_database.dart
  /// final state = TaskListState(database: db);
  /// ```
  ///
  /// [database] is returned as-is and never opened, migrated or closed by this
  /// object — the caller owns its lifetime.
  @visibleForTesting
  DatabaseService.forDatabase(Database database) : _database = database;

  // Each repository is built over *this* service, not over the default one.
  // A facade that built a `ModelRepository()` per call would send every
  // delegated query to the app's real file however this service was built,
  // which is exactly the seam [DatabaseService.forDatabase] exists to open.
  // Lazy, so constructing a service opens nothing.
  late final ModelRepository _models = ModelRepository(db: this);
  late final PromptRepository _prompts = PromptRepository(db: this);
  late final TaskRepository _tasks = TaskRepository(db: this);
  late final UsageRepository _usage = UsageRepository(db: this);
  late final CookieRepository _cookies = CookieRepository(db: this);
  late final ImageLayerRepository _layers = ImageLayerRepository(db: this);

  Future<Database> get database async {
    if (_database != null) return _database!;
    _databaseFuture ??= () async {
      final db = await _initDatabase();
      _database = db;
      await syncPresets();
      await _tasks.scrubStoredCookies();
      await _layers.loadPaths();
      return db;
    }();
    return _databaseFuture!;
  }

  Future<Database> _initDatabase() async {
    String dbPath;

    final dataDir = await AppPaths.getDataDirectory();
    final newPath = join(dataDir, 'joycai_workbench.db');

    // Legacy migration check (Only for non-portable mode or first transition)  
    if (!await AppPaths.isPortableMode()) {
      final docsDir = await getApplicationDocumentsDirectory();
      final oldPath = join(docsDir.path, 'joycai_workbench.db');

      if (await File(oldPath).exists() && !await File(newPath).exists()) {      
        try {
          final dir = Directory(dataDir);
          if (!await dir.exists()) {
            await dir.create(recursive: true);
          }
          await File(oldPath).rename(newPath);
        } catch (_) {}
      }
    }

    dbPath = newPath;
    Database db;

    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      db = await databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: dbVersion,
          onCreate: _onCreate,
          onUpgrade: _onUpgrade,
        ),
      );
    } else {
      // On macOS, iOS, and Android, use standard sqflite (non-FFI)
      // This avoids the 'native_assets' Null check operator bug on Flutter 3.38+ macOS Debug
      db = await openDatabase(
        dbPath,
        version: dbVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
    }
    await db.execute('PRAGMA foreign_keys = ON');
    await restrictToOwner(dbPath, directory: await AppPaths.isPortableMode() ? null : dataDir);
    return db;
  }

  /// Makes the database — and, outside portable mode, the data folder —
  /// readable and writable by the signed-in user only, on macOS and Linux.
  ///
  /// The API keys and the proxy password in it are not encrypted (an OS
  /// keychain does not survive this app's ad-hoc macOS signing, a Linux
  /// desktop without a keyring daemon, or a portable copy), so this is the
  /// protection the file itself gets: other accounts on the machine cannot
  /// read it. A default umask leaves both world-readable on Linux. SQLite
  /// creates its journal files with the database's own mode, so they follow.
  /// Windows profiles are already private to their user; mobile apps are
  /// sandboxed. A portable folder sits beside the executable and is the
  /// user's to arrange, so only the file is tightened there. Best effort: a
  /// failure is logged, never fatal.
  @visibleForTesting
  static Future<void> restrictToOwner(String file, {String? directory}) async {
    if (!(Platform.isMacOS || Platform.isLinux)) return;
    try {
      // `Process.run` reports a failed chmod through its exit code, not by
      // throwing — a filesystem that ignores Unix modes, a file owned by
      // someone else.
      for (final (mode, path) in [if (directory != null) ('700', directory), ('600', file)]) {
        final result = await Process.run('chmod', [mode, path]);
        if (result.exitCode != 0) {
          debugPrint('Could not restrict $path to $mode: ${result.stderr}');
        }
      }
    } catch (e) {
      debugPrint('Could not restrict data file permissions: $e');
    }
  }

  Future<String> getDatabasePath() async {
    return AppPaths.getDataDirectory();
  }

  Future<void> _onCreate(Database db, int version) async {
    await DatabaseMigration.onCreate(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {  
    await DatabaseMigration.migrate(db, oldVersion, newVersion);
  }

  /// Synchronize preset prompts from asset files into the database.
  /// This checks for missing presets and inserts them if they don't exist by title.
  Future<void> syncPresets() async {
    final db = await database;

    // 1. Sync System Prompts
    try {
      final String systemJsonString = await rootBundle.loadString('assets/presets/prompts/system_prompts.json');
      final List<dynamic> systemPresets = jsonDecode(systemJsonString);

      for (var preset in systemPresets) {
        final existing = await db.query(
          'system_prompts',
          where: 'title = ? AND type = ?',
          whereArgs: [preset['title'], preset['type']]
        );
        if (existing.isEmpty) {
          await db.insert('system_prompts', preset);
        }
      }
    } catch (e) {
      // ignore
    }

    // 2. Sync User Prompts
    try {
      final String userJsonString = await rootBundle.loadString('assets/presets/prompts/user_prompts.json');
      final List<dynamic> userPresets = jsonDecode(userJsonString);

      for (var preset in userPresets) {
        final existing = await db.query(
          'prompts',
          where: 'title = ?',
          whereArgs: [preset['title']]
        );
        if (existing.isEmpty) {
          await db.insert('prompts', preset);
        }
      }
    } catch (e) {
      // ignore
    }
  }

  // Task History Methods
  Future<void> saveTask(TaskItem task) => _tasks.saveTask(task);
  Future<List<TaskItem>> getRecentTasks(int limit) => _tasks.getRecentTasks(limit);
  Future<void> deleteTask(String id) => _tasks.deleteTask(id);        
  Future<void> cleanupStuckTasks() => _tasks.cleanupStuckTasks();     
  Future<List<double>> getTaskDurations(int modelDbId, int limit) => _tasks.getTaskDurations(modelDbId, limit);

  // Token Usage Methods
  Future<void> recordTokenUsage(TokenUsage usage) => _usage.recordTokenUsage(usage);
  Future<int> updateSpecBilling(String taskId, UsageSpecBilling billing) =>
      _usage.updateSpecBilling(taskId, billing);
  Future<void> clearTokenUsage({String? modelId}) => _usage.clearTokenUsage(modelId: modelId);
  Future<List<TokenUsage>> getTokenUsage({List<String>? modelIds, DateTime? start, DateTime? end, int? limit, int? offset})
      => _usage.getTokenUsage(modelIds: modelIds, start: start, end: end, limit: limit, offset: offset);

  Future<void> saveUsageCheckpoint(UsageCheckpoint checkpoint) => _usage.saveUsageCheckpoint(checkpoint);
  Future<UsageCheckpoint?> getLatestUsageCheckpoint() => _usage.getLatestUsageCheckpoint();

  // --- MODEL BASED METHODS ---

  // Prompts Methods
  Future<int> addPrompt(Prompt prompt, {List<int>? tagIds}) => _prompts.addPrompt(prompt, tagIds: tagIds);
  /// Writes [prompt] over row [id] — except its place in the list, which
  /// belongs to [updatePromptOrder].
  Future<void> updatePrompt(int id, Prompt prompt, {List<int>? tagIds}) => _prompts.updatePrompt(id, prompt, tagIds: tagIds);
  Future<void> deletePrompt(int id) => _prompts.deletePrompt(id);     
  Future<void> deletePrompts(List<int> ids) => _prompts.deletePrompts(ids);
  Future<void> updatePromptsTags(List<int> promptIds, List<int> tagIds) => _prompts.updatePromptsTags(promptIds, tagIds);
  Future<List<Prompt>> getPrompts() => _prompts.getPrompts();
  Future<void> updatePromptOrder(List<int> ids) => _prompts.updatePromptOrder(ids);

  // Prompt History Methods
  Future<List<PromptHistoryEntry>> getPromptHistory(PromptHistoryType type) => _prompts.getPromptHistory(type);
  Future<void> addPromptHistory(PromptHistoryType type, String content) => _prompts.addPromptHistory(type, content);
  Future<void> clearPromptHistory(PromptHistoryType type) => _prompts.clearPromptHistory(type);

  // LLM Models Methods
  Future<int> addModel(LLMModel model) => _models.addModel(model);
  /// Writes [model] over row [id] — except its place in the list and its ETA
  /// estimate, which belong to [updateModelOrder] and [updateModelEstimation].
  Future<void> updateModel(int id, LLMModel model) => _models.updateModel(id, model);
  Future<void> updateModelOrder(List<int> ids) => _models.updateModelOrder(ids);
  Future<void> deleteModel(int id) => _models.deleteModel(id);        
  Future<List<LLMModel>> getModels() => _models.getModels();
  Future<void> updateModelEstimation(int modelDbId, double mean, double sd, int tasksSinceUpdate)
      => _models.updateModelEstimation(modelDbId, mean, sd, tasksSinceUpdate);

  // Settings Methods
  Future<void> saveSetting(String key, String value) async {
    final db = await database;
    await db.insert('settings', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> getSetting(String key) async {
    final db = await database;
    final maps = await db.query('settings', where: 'key = ?', whereArgs: [key]);
    return maps.isNotEmpty ? maps.first['value'] as String : null;
  }

  Future<void> resetAllSettings() async {
    final db = await database;
    await db.transaction((txn) async {
      await clearAllData(txn, includePrompts: true);
    });
  }

  // Downloader Cookies History — see [CookieRepository] for retention.
  Future<void> saveDownloaderCookie(String host, String cookies) => _cookies.save(host, cookies);
  Future<List<Map<String, dynamic>>> getDownloaderCookies() => _cookies.list();

  // Source Directories Methods
  Future<void> addSourceDirectory(String path) async {
    final db = await database;
    await db.insert('source_directories', {'path': path, 'is_selected': 1}, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> removeSourceDirectory(String path) async {
    final db = await database;
    await db.delete('source_directories', where: 'path = ?', whereArgs: [path]);
  }

  /// Re-keys a registered source directory after the folder itself was
  /// renamed or moved. Keeps its selection flag.
  Future<void> renameSourceDirectory(String from, String to) async {
    final db = await database;
    await db.update('source_directories', {'path': to}, where: 'path = ?', whereArgs: [from]);
  }

  Future<void> updateDirectorySelection(String path, bool isSelected) async {   
    final db = await database;
    await db.update('source_directories', {'is_selected': isSelected ? 1 : 0}, where: 'path = ?', whereArgs: [path]);
  }

  Future<List<Map<String, dynamic>>> getSourceDirectories() async {
    final db = await database;
    return db.query('source_directories');
  }

  // Pricing Groups Methods
  Future<int> addPricingGroup(PricingGroup group) => _models.addPricingGroup(group);
  Future<void> updatePricingGroup(int id, PricingGroup group) => _models.updatePricingGroup(id, group);
  Future<void> deletePricingGroup(int id) => _models.deletePricingGroup(id);
  Future<List<PricingGroup>> getPricingGroups() => _models.getPricingGroups();
  Future<void> updatePricingGroupOrder(List<int> orderedIds) => _models.updatePricingGroupOrder(orderedIds);

  // LLM Channels Methods
  Future<int> addChannel(LLMChannel channel) => _models.addChannel(channel);
  Future<void> updateChannel(int id, LLMChannel channel) => _models.updateChannel(id, channel);
  Future<void> deleteChannel(int id) => _models.deleteChannel(id);    
  Future<List<LLMChannel>> getChannels() => _models.getChannels();    
  Future<LLMChannel?> getChannel(int id) => _models.getChannel(id);   
  Future<void> updateChannelOrder(List<int> orderedIds) => _models.updateChannelOrder(orderedIds);

  // Prompt Tags Methods
  Future<int> addPromptTag(PromptTag tag) => _prompts.addPromptTag(tag);
  /// Writes [tag] over row [id] — except its place in the list, which
  /// belongs to [updateTagOrder].
  Future<void> updatePromptTag(int id, PromptTag tag) => _prompts.updatePromptTag(id, tag);
  Future<void> deletePromptTag(int id) => _prompts.deletePromptTag(id);
  Future<List<PromptTag>> getPromptTags() => _prompts.getPromptTags();
  Future<void> updateTagOrder(List<int> ids) => _prompts.updateTagOrder(ids);

  // System Prompts Methods
  Future<int> addSystemPrompt(SystemPrompt prompt, {List<int>? tagIds}) => _prompts.addSystemPrompt(prompt, tagIds: tagIds);
  /// Writes [prompt] over row [id] — except its place in the list, which
  /// belongs to [updateSystemPromptOrder].
  Future<void> updateSystemPrompt(int id, SystemPrompt prompt, {List<int>? tagIds}) => _prompts.updateSystemPrompt(id, prompt, tagIds: tagIds);
  Future<void> deleteSystemPrompt(int id) => _prompts.deleteSystemPrompt(id);
  Future<void> deleteSystemPrompts(List<int> ids) => _prompts.deleteSystemPrompts(ids);
  Future<void> updateSystemPromptsTags(List<int> promptIds, List<int> tagIds) => _prompts.updateSystemPromptsTags(promptIds, tagIds);
  Future<List<SystemPrompt>> getSystemPrompts({String? type}) => _prompts.getSystemPrompts(type: type);
  Future<void> updateSystemPromptOrder(List<int> ids) => _prompts.updateSystemPromptOrder(ids);

  // Standalone Prompt Data
  Future<Map<String, dynamic>> getPromptDataRaw() async => promptLibraryExport(
        tags: await getPromptTags(),
        userPrompts: await getPrompts(),
        systemPrompts: await getSystemPrompts(),
      );

  // Backup & Restore (Now with optional prompt inclusion)
  Future<Map<String, dynamic>> getAllDataRaw({
    bool includePrompts = true,
    bool includeUsage = true,
    bool includeDirectories = true,
  }) async {
    final db = await database;

    // Filter settings if directories are excluded
    final settingsRows = await db.query('settings');
    var filteredSettings = [
      for (final row in settingsRows)
        secretSettingKeys.contains(row['key'])
            ? (Map<String, Object?>.from(row)..['value'] = '') // Redact on export
            : row,
    ];
    if (!includeDirectories) {
      filteredSettings = filteredSettings.where((row) => !_directorySettingKeys.contains(row['key'])).toList();
    }

    final channels = await db.query('llm_channels');
    final sanitizedChannels = channels.map((row) {
      final map = Map<String, dynamic>.from(row);
      if (map.containsKey('api_key')) {
        map['api_key'] = ''; // Redact key on backup export
      }
      return map;
    }).toList();

    final cookies = await db.query('downloader_cookies');
    final sanitizedCookies = cookies.map((row) {
      final map = Map<String, dynamic>.from(row);
      if (map.containsKey('cookies')) {
        map['cookies'] = ''; // Redact cookies on backup export
      }
      return map;
    }).toList();

    final Map<String, dynamic> data = {
      'export_type': 'full_backup',
      'schema_version': dbVersion,
      'settings': filteredSettings,
      'llm_channels': sanitizedChannels,
      'llm_models': await db.query('llm_models'),
      'fee_groups': await db.query('fee_groups'),
      'downloader_cookies': sanitizedCookies,
    };

    if (includeUsage) {
      data['token_usage'] = await db.query('token_usage');
      data['usage_checkpoints'] = await db.query('usage_checkpoints');
    }

    if (includeDirectories) {
      data['source_directories'] = await db.query('source_directories');        
    }

    if (includePrompts) {
      data.addAll(await getPromptDataRaw());
    }

    return data;
  }

  Future<void> clearAllData(DatabaseExecutor txn, {
    bool includePrompts = true,
    bool includeUsage = true,
    bool includeDirectories = true,
  }) async {
    await txn.delete('settings');

    // llm_models references both llm_channels and fee_groups without a cascade,
    // so children must go first or `PRAGMA foreign_keys = ON` aborts the delete.
    await txn.delete('llm_models');
    await txn.delete('llm_channels');
    await txn.delete('fee_groups');

    // `tasks` and `downloader_cookies` are deliberately kept. Both are local
    // data no backup carries -- task history is never exported, and cookies are
    // redacted on export -- so clearing them destroys what no restore replaces.

    if (includeUsage) {
      await txn.delete('token_usage');
      await txn.delete('usage_checkpoints');
    }

    if (includeDirectories) {
      await txn.delete('source_directories');
    }

    if (includePrompts) {
      await txn.delete('prompts');
      await txn.delete('system_prompts');
      await txn.delete('prompt_tag_refs');
      await txn.delete('system_prompt_tag_refs');
      await txn.delete('prompt_tags');
    }
  }

  /// Reject a file that cannot be restored, before the database is touched.
  void _validateBackup(Map<String, dynamic> data) {
    if (data['export_type'] == 'prompts_only') {
      throw BackupFormatException(BackupFormatError.promptsOnly);
    }
    if (!_backupTableKeys.any(data.containsKey)) {
      throw BackupFormatException(BackupFormatError.notABackup);
    }
    final fileVersion = data['schema_version'];
    if (fileVersion is int && fileVersion > dbVersion) {
      throw BackupFormatException(
        BackupFormatError.newerSchema,
        fileVersion: fileVersion,
        appVersion: dbVersion,
      );
    }
  }

  /// Restore a full backup produced by [getAllDataRaw].
  ///
  /// Throws [BackupFormatException] if [data] is not a full backup this build
  /// can read; the database is left untouched in that case.
  Future<void> restoreBackup(Map<String, dynamic> data, {
    bool includePrompts = true,
    bool includeUsage = true,
    bool includeDirectories = true,
  }) async {
    _validateBackup(data);

    final db = await database;

    await db.transaction((txn) async {
      await restoreBackupInto(txn, data,
        includePrompts: includePrompts,
        includeUsage: includeUsage,
        includeDirectories: includeDirectories,
      );
    });
  }

  /// Body of [restoreBackup], split out so it can run against any executor.
  ///
  /// Callers are responsible for the surrounding transaction and for validating
  /// [data] first; [restoreBackup] does both.
  @visibleForTesting
  Future<void> restoreBackupInto(DatabaseExecutor txn, Map<String, dynamic> data, {
    bool includePrompts = true,
    bool includeUsage = true,
    bool includeDirectories = true,
  }) async {
    // API keys are redacted on export, so carry the live ones across the wipe
    // rather than overwriting working keys with the blanks from the file.
    final preservedKeys = await _collectChannelKeys(txn);
    final preservedSecrets = {
      for (final row in await txn.query('settings',
          where: 'key IN (${List.filled(secretSettingKeys.length, '?').join(', ')})',
          whereArgs: secretSettingKeys.toList()))
        if ((row['value'] as String? ?? '').isNotEmpty) row['key'] as String: row['value'] as String,
    };

    await clearAllData(txn,
      includePrompts: includePrompts,
      includeUsage: includeUsage,
      includeDirectories: includeDirectories,
    );

    // Fee groups before channels: a channel's default group is a group id,
    // renumbered on the way in like the models' own.
    final pricingGroupIdMap = await _importPricingGroups(txn, data['fee_groups']);
    final channelIdMap = await _importChannels(txn, data['llm_channels'], preservedKeys, pricingGroupIdMap);
    final modelIdMap = await _importModels(txn, data['llm_models'], channelIdMap, pricingGroupIdMap);

    if (data['downloader_cookies'] != null) {
      await _importCookies(txn, data['downloader_cookies']);
    }

    if (includeUsage && data['token_usage'] != null) {
      await _importTokenUsage(txn, data['token_usage'], modelIdMap);
    }

    if (includeUsage && data['usage_checkpoints'] != null) {
      final checkpoints = (data['usage_checkpoints'] as List<dynamic>).map((row) {
        return Map<String, dynamic>.from(row)..remove('id');
      }).toList();
      await _importSimpleTable(txn, 'usage_checkpoints', checkpoints);
    }

    if (includePrompts) {
      final tagIdMap = await _importPromptTags(txn, data['prompt_tags'] ?? data['tags']);
      await _importPrompts(txn, data['prompts'] ?? data['user_prompts'], tagIdMap);
      await _importSystemPrompts(txn, data['system_prompts'], tagIdMap);
    }

    if (data['settings'] != null) {
      final List<dynamic> settingsRows = data['settings'];
      var filteredSettings = settingsRows;
      if (!includeDirectories) {
        filteredSettings = settingsRows.where((row) => !_directorySettingKeys.contains(row['key'])).toList();
      }
      await _importSimpleTable(txn, 'settings', filteredSettings);
    }
    // A redacted credential in the file does not blank the one this machine
    // has — the same rule as the channel keys above.
    for (final entry in preservedSecrets.entries) {
      final current = await txn.query('settings', where: 'key = ?', whereArgs: [entry.key]);
      if (current.isNotEmpty && (current.first['value'] as String? ?? '').isNotEmpty) continue;
      await txn.insert('settings', {'key': entry.key, 'value': entry.value},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }

    if (includeDirectories && data['source_directories'] != null) {
      await _importSimpleTable(txn, 'source_directories', data['source_directories']);
    }
  }

  Future<void> importPromptData(Map<String, dynamic> data, {bool replace = false}) async {
    final db = await database;
    await db.transaction((txn) async {
      await importPromptDataInto(txn, data, replace: replace);
    });
  }

  /// Body of [importPromptData], split out so it can run against any executor.
  ///
  /// Every row is filtered to the columns this database has before it is
  /// inserted. A prompt-library file carries no `schema_version` — unlike a
  /// full backup, which [_validateBackup] turns away when it is from a later
  /// build — so a file written after a column was added arrives here with a key
  /// this build has never heard of. `insert` names its columns, so that one key
  /// fails the statement, and the failure is inside this transaction: the tags
  /// and the prompts that came with it go down with it. Dropping the key gets
  /// the rest of the library in. What the key said is lost, which is the honest
  /// outcome when there is nowhere here to put it.
  @visibleForTesting
  Future<void> importPromptDataInto(DatabaseExecutor txn, Map<String, dynamic> data, {bool replace = false}) async {
    final tagColumns = await _columnsOf(txn, 'prompt_tags');
    final promptColumns = await _columnsOf(txn, 'prompts');
    final systemPromptColumns = await _columnsOf(txn, 'system_prompts');

    if (replace) {
      // `prompts.tag_id` references `prompt_tags`, so prompts must go first.
      await txn.delete('prompts');
      await txn.delete('prompt_tag_refs');
      await txn.delete('system_prompts');
      await txn.delete('prompt_tags');
    }

    // Import Tags first to get new IDs
    final Map<int, int> tagIdMap = {};
    if (data['tags'] != null) {
      for (var t in data['tags']) {
        final oldId = t['id'] as int;
        final Map<String, dynamic> row = Map.from(t)..remove('id');
        // Check if tag exists by name
        final existing = await txn.query('prompt_tags', where: 'name = ?', whereArgs: [row['name']]);
        if (existing.isNotEmpty) {
          tagIdMap[oldId] = existing.first['id'] as int;
        } else {
          final newId = await txn.insert('prompt_tags', _knownColumnsOnly(row, tagColumns));
          tagIdMap[oldId] = newId;
        }
      }
    }

    // Import User Prompts
    if (data['user_prompts'] != null) {
      for (var p in data['user_prompts']) {
        final Map<String, dynamic> row = Map.from(p)..remove('id');
        final List<dynamic>? tags = row['tags'];
        final originalTagId = row['tag_id'] as int?;
        row.remove('tags');
        row.remove('tag_name');
        row.remove('tag_color');
        row.remove('tag_is_system');
        // Legacy column with a live foreign key: remap onto this database's
        // tags, dropping the link when the tag did not come across.
        row['tag_id'] = originalTagId == null ? null : tagIdMap[originalTagId];

        final newPromptId = await txn.insert('prompts', _knownColumnsOnly(row, promptColumns));
        if (tags != null) {
          for (var t in tags) {
            final oldTagId = t['id'] as int;
            final newTagId = tagIdMap[oldTagId];
            if (newTagId != null) {
              await txn.insert('prompt_tag_refs', {'prompt_id': newPromptId, 'tag_id': newTagId});
            }
          }
        }
      }
    }

    // Import System Prompts
    if (data['system_prompts'] != null) {
      for (var p in data['system_prompts']) {
        final Map<String, dynamic> row = _systemPromptRow(p);
        final List<dynamic>? tags = row['tags'];
        row.remove('tags');

        final existing = await txn.query('system_prompts', where: 'title = ? AND type = ?', whereArgs: [row['title'], row['type']]);
        if (existing.isNotEmpty) {
          if (!replace) continue;
          // Delete existing prompt and its tag refs when replacing
          final existingId = existing.first['id'] as int;
          await txn.delete('system_prompt_tag_refs', where: 'prompt_id = ?', whereArgs: [existingId]);
          await txn.delete('system_prompts', where: 'id = ?', whereArgs: [existingId]);
        }

        final newPromptId =
            await txn.insert('system_prompts', _knownColumnsOnly(row, systemPromptColumns));
        if (tags != null) {
          for (var t in tags) {
            final oldTagId = t['id'] as int;
            final newTagId = tagIdMap[oldTagId];
            if (newTagId != null) {
              await txn.insert('system_prompt_tag_refs', {'prompt_id': newPromptId, 'tag_id': newTagId});
            }
          }
        }
      }
    }
  }

  Future<void> _importTokenUsage(DatabaseExecutor txn, List<dynamic>? rows, Map<int, int> modelIdMap) async {
    if (rows == null || rows.isEmpty) return;
    final batch = txn.batch();
    for (var row in rows) {
      final Map<String, dynamic> map = Map.from(row)..remove('id');
      if (map['model_pk'] != null) {
        map['model_pk'] = modelIdMap[map['model_pk']];
      }
      batch.insert('token_usage', map);
    }
    await batch.commit(noResult: true);
  }

  Future<Map<int, int>> _importModels(DatabaseExecutor txn, List<dynamic>? rows, Map<int, int> channelIdMap, Map<int, int> pricingGroupIdMap) async {
    final Map<int, int> idMap = {};
    if (rows == null) return idMap;
    for (var m in rows) {
      final oldId = m['id'] as int;
      final Map<String, dynamic> row = Map.from(m)..remove('id');
      // Pre-v32 backups carry the dropped llm_models.type column.
      row.remove('type');
      if (row['channel_id'] != null) row['channel_id'] = channelIdMap[row['channel_id']];
      if (row['fee_group_id'] != null) row['fee_group_id'] = pricingGroupIdMap[row['fee_group_id']];
      final newId = await txn.insert('llm_models', row);
      idMap[oldId] = newId;
    }
    return idMap;
  }

  Future<Map<int, int>> _importPromptTags(DatabaseExecutor txn, List<dynamic>? rows) async {
    final Map<int, int> idMap = {};
    if (rows == null) return idMap;
    for (var t in rows) {
      final oldId = t['id'] as int;
      final Map<String, dynamic> row = Map.from(t)..remove('id');
      try {
        final newId = await txn.insert('prompt_tags', row);
        idMap[oldId] = newId;
      } catch (e) {
        final existing = await txn.query('prompt_tags', where: 'name = ?', whereArgs: [row['name']]);
        if (existing.isNotEmpty) {
          idMap[oldId] = existing.first['id'] as int;
        }
      }
    }
    return idMap;
  }

  Future<void> _importPrompts(DatabaseExecutor txn, List<dynamic>? rows, Map<int, int> tagIdMap) async {
    if (rows == null) return;
    for (var p in rows) {
      final Map<String, dynamic> row = Map.from(p)..remove('id');
      final originalTagId = row['tag_id'] as int?;

      final List<dynamic>? tagsFromData = row['tags'];
      row.remove('tags');
      row.remove('tag_name');
      row.remove('tag_color');
      row.remove('tag_is_system');

      // `tag_id` is a legacy column with a live foreign key. The exporter's tag
      // ids are meaningless here, so remap them; an unknown tag becomes null
      // rather than a dangling reference that would abort the restore.
      if (originalTagId != null) {
        row['tag_id'] = tagIdMap[originalTagId];
      }

      final newPromptId = await txn.insert('prompts', row);

      if (tagsFromData != null) {
        for (var t in tagsFromData) {
          final oldTagId = t['id'] as int;
          final newTagId = tagIdMap[oldTagId];
          if (newTagId != null) {
            await txn.insert('prompt_tag_refs', {'prompt_id': newPromptId, 'tag_id': newTagId});
          }
        }
      } else if (originalTagId != null) {
        final newTagId = tagIdMap[originalTagId];
        if (newTagId != null) {
          await txn.insert('prompt_tag_refs', {'prompt_id': newPromptId, 'tag_id': newTagId});
        }
      }
    }
  }

  /// The columns [table] actually has in this database.
  static Future<Set<String>> _columnsOf(DatabaseExecutor txn, String table) async {
    final info = await txn.rawQuery('PRAGMA table_info($table)');
    return {for (final column in info) column['name'] as String};
  }

  /// [row] reduced to the keys [columns] names — see [importPromptDataInto].
  static Map<String, dynamic> _knownColumnsOnly(
      Map<String, dynamic> row, Set<String> columns) {
    return {
      for (final entry in row.entries)
        if (columns.contains(entry.key)) entry.key: entry.value,
    };
  }

  /// A `system_prompts` row out of an import file, ready to insert. A null
  /// `output_kind` is dropped so the column's default stands in for it: the
  /// column is NOT NULL, and one such row would roll the whole import back.
  static Map<String, dynamic> _systemPromptRow(dynamic source) {
    final Map<String, dynamic> row = Map.from(source as Map)..remove('id');
    if (row['output_kind'] == null) row.remove('output_kind');
    return row;
  }

  Future<void> _importSystemPrompts(DatabaseExecutor txn, List<dynamic>? rows, Map<int, int> tagIdMap) async {
    if (rows == null) return;
    for (var p in rows) {
      final Map<String, dynamic> row = _systemPromptRow(p);
      final List<dynamic>? tagsFromData = row['tags'];
      row.remove('tags');

      final newPromptId = await txn.insert('system_prompts', row);

      if (tagsFromData != null) {
        for (var t in tagsFromData) {
          final oldTagId = t['id'] as int;
          final newTagId = tagIdMap[oldTagId];
          if (newTagId != null) {
            await txn.insert('system_prompt_tag_refs', {'prompt_id': newPromptId, 'tag_id': newTagId});
          }
        }
      }
    }
  }

  Future<void> _importSimpleTable(DatabaseExecutor txn, String table, List<dynamic>? rows) async {
    if (rows == null || rows.isEmpty) return;
    final batch = txn.batch();
    for (var row in rows) {
      batch.insert(table, row as Map<String, dynamic>);
    }
    await batch.commit(noResult: true);
  }

  /// Identity of a channel across a wipe, since primary keys are reassigned.
  ///
  /// NUL-separated, as an escape rather than a literal byte: the literal made
  /// every text tool treat this file as binary.
  ///
  /// The type and endpoint are read *normalized* — the primary route's vendor
  /// and address — so a row written before routes and the same channel
  /// written after (whose flat endpoint may have been canonicalized on save)
  /// still recognize each other.
  String _channelIdentity(Map<String, dynamic> row) {
    final routes = ChannelRoutes.resolve(
      row['type'] as String? ?? '',
      row['endpoint'] as String? ?? '',
      row['routes'] as String?,
    );
    return '${routes.primaryVendorId}\u0000${routes.primaryAddress}'
        '\u0000${row['display_name']}';
  }

  /// Snapshot the API keys currently in the database, keyed by channel identity.
  Future<Map<String, String>> _collectChannelKeys(DatabaseExecutor txn) async {
    final rows = await txn.query('llm_channels',
        columns: ['display_name', 'endpoint', 'type', 'api_key', 'routes']);
    final Map<String, String> keys = {};
    for (final row in rows) {
      final apiKey = row['api_key'] as String? ?? '';
      if (apiKey.isEmpty) continue;
      keys[_channelIdentity(row)] = apiKey;
    }
    return keys;
  }

  Future<Map<int, int>> _importChannels(
    DatabaseExecutor txn,
    List<dynamic>? rows,
    Map<String, String> preservedKeys,
    Map<int, int> pricingGroupIdMap,
  ) async {
    final Map<int, int> idMap = {};
    if (rows == null) return idMap;
    for (var c in rows) {
      final oldId = c['id'] as int;
      final Map<String, dynamic> row = Map.from(c)..remove('id');
      // Redacted export: fall back to the key this machine already had.
      if ((row['api_key'] as String? ?? '').isEmpty) {
        row['api_key'] = preservedKeys[_channelIdentity(row)] ?? '';
      }
      // A group the file does not carry is no default, not a dangling id.
      if (row['default_fee_group_id'] != null) {
        row['default_fee_group_id'] = pricingGroupIdMap[row['default_fee_group_id']];
      }
      final newId = await txn.insert('llm_channels', row);
      idMap[oldId] = newId;
    }
    return idMap;
  }

  /// Merge cookies from a backup, keeping existing ones where the file is
  /// redacted. `host` is a natural key, so rows are upserted rather than wiped.
  Future<void> _importCookies(DatabaseExecutor txn, List<dynamic>? rows) async {
    if (rows == null || rows.isEmpty) return;
    final batch = txn.batch();
    for (var r in rows) {
      final Map<String, dynamic> row = Map<String, dynamic>.from(r as Map);
      if ((row['cookies'] as String? ?? '').isEmpty) continue;
      batch.insert('downloader_cookies', row,
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<Map<int, int>> _importPricingGroups(DatabaseExecutor txn, List<dynamic>? rows) async {
    final Map<int, int> idMap = {};
    if (rows == null) return idMap;
    for (var g in rows) {
      final oldId = g['id'] as int;
      final Map<String, dynamic> row = Map.from(g)..remove('id');
      final newId = await txn.insert('fee_groups', row);
      idMap[oldId] = newId;
    }
    return idMap;
  }
}
