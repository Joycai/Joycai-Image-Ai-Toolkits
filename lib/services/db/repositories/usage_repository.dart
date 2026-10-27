import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../models/token_usage.dart';
import '../../../models/usage_checkpoint.dart';
import '../../billing/media_accounting.dart';
import '../database_service.dart';

class UsageRepository {
  UsageRepository({DatabaseService? db}) : _dbService = db ?? DatabaseService();

  final DatabaseService _dbService;

  Future<Database> get _db async => _dbService.database;

  Future<TokenUsage?> usageFor(String taskId) async {
    final rows = await (await _db).query('token_usage', where: 'task_id = ?', whereArgs: [taskId]);
    return rows.isEmpty ? null : TokenUsage.fromMap(rows.single);
  }

  Future<void> recordTokenUsage(TokenUsage usage) async {
    if (usage.accounting != null) {
      await _journal({
        'kind': 'record',
        'row': usage.toMap(),
      }, 'record:${usage.taskId}:${sha256.convert(utf8.encode(usage.accounting!.encode()))}');
      return;
    }
    final db = await _db;
    await db.insert(
      'token_usage',
      usage.toMap(),
      conflictAlgorithm: (usage.taskId?.startsWith('batch:') ?? false)
          ? ConflictAlgorithm.ignore
          : ConflictAlgorithm.abort,
    );
  }

  static int _sequence = 0;

  Future<void> settleMedia(
    String taskId,
    Map<String, dynamic> evidence, {
    double? reportedCost,
    int? version,
  }) => _journal({
    'version': version ?? DateTime.now().microsecondsSinceEpoch,
    'kind': 'settle',
    'taskId': taskId,
    'evidence': evidence,
    'reportedCost': ?reportedCost,
  }, 'settle:$taskId:${jsonEncode(evidence)}:$reportedCost');

  /// Flush before touching SQLite; transaction identity makes a crash between
  /// commit and spool deletion safe. The spool contains no credentials.
  Future<void> _journal(Map<String, dynamic> payload, String id) async {
    File? file;
    Object? journalError;
    try {
      final directory = await _dbService.usageJournalDirectory;
      if (directory != null) {
        await Directory(directory).create(recursive: true);
        final name = '${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';
        final temporary = File('$directory/$name.tmp');
        await temporary.writeAsString(jsonEncode({'id': id, 'payload': payload}), flush: true);
        file = await temporary.rename('$directory/$name.json');
      }
    } catch (e) {
      journalError = e;
    }
    try {
      await _apply(id, payload);
    } catch (e) {
      if (journalError != null) {
        throw StateError('ACCOUNTING RECORD MISSING: database=$e; journal=$journalError');
      }
      rethrow;
    }
    if (file != null && await file.exists()) await file.delete();
  }

  Future<void> _apply(String id, Map<String, dynamic> payload) async {
    final db = await _db;
    await db.transaction((txn) async {
      if ((await txn.query('usage_events', where: 'id = ?', whereArgs: [id])).isNotEmpty) return;
      if (payload['kind'] == 'record') {
        final row = Map<String, dynamic>.from(payload['row'] as Map);
        final existing = await txn.query(
          'token_usage',
          where: 'task_id = ?',
          whereArgs: [row['task_id']],
        );
        if (existing.isEmpty) {
          await txn.insert('token_usage', row);
        } else if ((row['task_id'] as String).startsWith('batch:') &&
            TokenUsage.fromMap(existing.single).costIncomplete) {
          final previous = TokenUsage.fromMap(existing.single).accounting;
          final incoming = TokenUsage.fromMap(row).accounting!;
          final evidence = Map<String, dynamic>.from(incoming.quantities)
            ..removeWhere((key, value) => value == null);
          final merged = previous == null ? incoming : MediaAccounting.settle(previous, evidence);
          await txn.update(
            'token_usage',
            {'accounting': merged.encode(), ...merged.tokenProjection},
            where: 'id = ?',
            whereArgs: [existing.single['id']],
          );
          await txn.delete('usage_checkpoints');
        }
      } else {
        final rows = await txn.query(
          'token_usage',
          where: 'task_id = ?',
          whereArgs: [payload['taskId']],
        );
        if (rows.isEmpty) throw StateError('Usage settlement pending: submit row is missing');
        final row = TokenUsage.fromMap(rows.single);
        final original = row.accounting;
        final evidence = Map<String, dynamic>.from(payload['evidence'] as Map)
          ..removeWhere((key, value) => value == null);
        final version = payload['version'] as int? ?? 0;
        final previousVersion = original?.quantities['settlement_version'] as int? ?? -1;
        if (version < previousVersion) return;
        evidence['settlement_version'] = version;
        // Legacy rows have no full rule snapshot. Never use today's prices.
        final updated = original == null ? null : MediaAccounting.settle(original, evidence);
        final output = updated?.components.where((c) => c.category == 'spec').firstOrNull;
        final input = updated?.components.where((c) => c.meter == 'input_images').firstOrNull;
        final options = updated?.pricing['options'] as Map?;
        final cost = payload['reportedCost'];
        final values = <String, Object?>{
          if (updated != null) 'accounting': updated.encode(),
          if (output != null) ...{
            'output_units': output.quantity,
            'output_unit_price': output.price,
            'output_unit': updated!.pricing['output_unit'],
            'output_spec': jsonEncode({
              'size': updated.quantities['output_size'] ?? options?['imageSize'],
              'quality': updated.quantities['output_quality'] ?? options?['quality'],
              'seconds': updated.quantities['output_seconds'] ?? options?['seconds'],
              'matched': output.price != null,
            }),
          },
          if (input != null) ...{
            'input_images': updated!.quantities['input_images'],
            'input_units': input.quantity,
            'input_unit_price': input.price,
          },
          if (cost is num && cost.isFinite && cost >= 0) 'reported_cost': cost,
        };
        if (values.isNotEmpty) {
          await txn.update(
            'token_usage',
            values,
            where: 'task_id = ?',
            whereArgs: [payload['taskId']],
          );
        }
        await txn.delete('usage_checkpoints');
      }
      await txn.insert('usage_events', {'id': id, 'payload': '{}'});
    });
  }

  Future<void> replayPending() async {
    final directory = await _dbService.usageJournalDirectory;
    if (directory == null || !await Directory(directory).exists()) return;
    final files = await Directory(directory).list().where((f) => f.path.endsWith('.json')).toList();
    files.sort((a, b) => a.path.compareTo(b.path));
    final events = <(File, Map<String, dynamic>)>[];
    for (final entry in files.whereType<File>()) {
      try {
        events.add((
          entry,
          Map<String, dynamic>.from(jsonDecode(await entry.readAsString()) as Map),
        ));
      } catch (e) {
        debugPrint('Unreadable accounting recovery event ${entry.path}: $e');
      }
    }
    // A settlement may have reached the spool while its submit was still
    // failing. Restore all submissions before applying their terminal evidence.
    for (final kind in ['record', 'settle']) {
      for (final (entry, event) in events) {
        final payload = Map<String, dynamic>.from(event['payload'] as Map);
        if (payload['kind'] != kind) continue;
        try {
          await _apply(event['id'] as String, payload);
          if (await entry.exists()) await entry.delete();
        } catch (e) {
          debugPrint('Accounting recovery pending ${entry.path}: $e');
        }
      }
    }
  }

  /// Re-prices the usage row recorded under [taskId] at [billing]; returns
  /// how many rows matched (0 for a row written before ids were durable).
  Future<int> updateSpecBilling(String taskId, UsageSpecBilling billing) async {
    final db = await _db;
    return db.update(
      'token_usage',
      billing.toOutputMap(),
      where: 'task_id = ?',
      whereArgs: [taskId],
    );
  }

  /// Writes what the provider itself said the job recorded under [taskId]
  /// cost — `reported_cost` alone, the one column a terminal video poll
  /// learns; the fee group's snapshot stays on the row beside it
  /// (`TokenUsage.snapshotCost`). Returns how many rows matched.
  Future<int> updateReportedCost(String taskId, double cost) async {
    final db = await _db;
    return db.update(
      'token_usage',
      {'reported_cost': cost},
      where: 'task_id = ?',
      whereArgs: [taskId],
    );
  }

  /// Points every usage row and task row recorded against a key of [idMap]
  /// at its value — a channel merge folding one model into another, so the
  /// history follows the model rather than reading "deleted model".
  Future<void> remapModels(Map<int, int> idMap) async {
    if (idMap.isEmpty) return;
    final db = await _db;
    await db.transaction((txn) async {
      for (final e in idMap.entries) {
        for (final table in const ['token_usage', 'tasks']) {
          await txn.update(table, {'model_pk': e.value}, where: 'model_pk = ?', whereArgs: [e.key]);
        }
      }
    });
  }

  /// How many usage and task rows name one of [ids].
  Future<int> countModelRows(Iterable<int> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return 0;
    final db = await _db;
    final marks = List.filled(list.length, '?').join(',');
    var n = 0;
    for (final table in const ['token_usage', 'tasks']) {
      final rows = await db.rawQuery(
        'SELECT COUNT(*) AS n FROM $table WHERE model_pk IN ($marks)',
        list,
      );
      n += rows.first['n'] as int? ?? 0;
    }
    return n;
  }

  Future<void> clearTokenUsage({String? modelId}) async {
    final db = await _db;
    if (modelId != null) {
      await db.delete('token_usage', where: 'model_id = ?', whereArgs: [modelId]);
    } else {
      await db.delete('token_usage');
    }
  }

  Future<List<TokenUsage>> getTokenUsage({
    List<String>? modelIds,
    DateTime? start,
    DateTime? end,
    int? limit,
    int? offset,
  }) async {
    final db = await _db;
    await replayPending();
    String where = '1=1';
    final List<dynamic> args = [];

    if (modelIds != null && modelIds.isNotEmpty) {
      where += " AND model_id IN (${modelIds.map((_) => '?').join(',')})";
      args.addAll(modelIds);
    }

    if (start != null) {
      where += ' AND timestamp >= ?';
      args.add(start.toIso8601String());
    }

    if (end != null) {
      where += ' AND timestamp <= ?';
      args.add(end.toIso8601String());
    }

    final rows = await db.query(
      'token_usage',
      where: where,
      whereArgs: args,
      orderBy: 'timestamp DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(TokenUsage.fromMap).toList();
  }

  Future<void> saveUsageCheckpoint(UsageCheckpoint checkpoint) async {
    final db = await _db;
    await db.insert('usage_checkpoints', checkpoint.toMap());
  }

  Future<UsageCheckpoint?> getLatestUsageCheckpoint() async {
    final db = await _db;
    final results = await db.query('usage_checkpoints', orderBy: 'timestamp DESC', limit: 1);
    if (results.isEmpty) return null;
    return UsageCheckpoint.fromMap(results.first);
  }
}
