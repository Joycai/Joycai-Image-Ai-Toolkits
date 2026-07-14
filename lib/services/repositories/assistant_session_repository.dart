import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../database_service.dart';
import '../llm/llm_types.dart';
import '../prompt_optimizer_agent.dart';

/// Metadata row of a persisted assistant conversation.
class AssistantSessionMeta {
  final String id;
  final String? title;
  final AssistantMode mode;
  final List<Map<String, String>> refImages; // {path, name}
  final DateTime createdAt;
  final DateTime updatedAt;

  const AssistantSessionMeta({
    required this.id,
    this.title,
    required this.mode,
    this.refImages = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  static AssistantSessionMeta fromRow(Map<String, dynamic> row) {
    List<Map<String, String>> images = [];
    try {
      images = [
        for (final e in (jsonDecode(row['ref_images'] as String? ?? '[]') as List))
          if (e is Map) e.map((k, v) => MapEntry(k.toString(), v.toString())),
      ];
    } catch (_) {}
    return AssistantSessionMeta(
      id: row['id'] as String,
      title: row['title'] as String?,
      mode: AssistantMode.values.asNameMap()[row['mode']] ?? AssistantMode.systemPrompt,
      refImages: images,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int? ?? 0),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int? ?? 0),
    );
  }
}

/// One persisted message (raw LLM history entry) of a conversation.
class StoredAssistantMessage {
  final int seq;
  final LLMMessage message;
  final bool compacted;
  final bool isSummary;

  const StoredAssistantMessage({
    required this.seq,
    required this.message,
    this.compacted = false,
    this.isSummary = false,
  });
}

/// SQLite persistence for prompt-assistant conversations.
///
/// Messages are stored as one JSON blob per row ([LLMMessage.toJson]);
/// attachments round-trip as file paths only. Rows that were folded into a
/// compaction summary keep `compacted = 1` so the full history stays
/// inspectable while replay skips them.
class AssistantSessionRepository {
  final DatabaseService _dbService = DatabaseService();

  Future<Database> _getDb() async => await _dbService.database;

  Future<void> upsertSession({
    required String id,
    String? title,
    required AssistantMode mode,
    required List<Map<String, String>> refImages,
  }) async {
    final db = await _getDb();
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = await db.query('assistant_sessions', where: 'id = ?', whereArgs: [id], limit: 1);
    if (existing.isEmpty) {
      await db.insert('assistant_sessions', {
        'id': id,
        'title': title,
        'mode': mode.name,
        'ref_images': jsonEncode(refImages),
        'created_at': now,
        'updated_at': now,
      });
    } else {
      await db.update(
        'assistant_sessions',
        {
          if (title != null) 'title': title,
          'ref_images': jsonEncode(refImages),
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  /// Appends [messages] starting at [startSeq] (the session's message count
  /// before this batch). Also bumps the session's updated_at.
  Future<void> appendMessages(String sessionId, int startSeq, List<LLMMessage> messages) async {
    if (messages.isEmpty) return;
    final db = await _getDb();
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    for (int i = 0; i < messages.length; i++) {
      batch.insert(
        'assistant_messages',
        {
          'session_id': sessionId,
          'seq': startSeq + i,
          'message': jsonEncode(messages[i].toJson()),
          'created_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    batch.update('assistant_sessions', {'updated_at': now}, where: 'id = ?', whereArgs: [sessionId]);
    await batch.commit(noResult: true);
  }

  /// Compaction: flags every currently active row as `compacted`, then
  /// appends [active] (summary first, then the kept tail) as fresh rows.
  /// Replay reads only non-compacted rows in seq order, so it sees exactly
  /// the new in-memory history; the flagged rows remain for full-history
  /// inspection.
  Future<void> compactAll(String sessionId, List<LLMMessage> active) async {
    final db = await _getDb();
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      await txn.update(
        'assistant_messages',
        {'compacted': 1},
        where: 'session_id = ? AND compacted = 0',
        whereArgs: [sessionId],
      );
      final rows = await txn.rawQuery(
        'SELECT MAX(seq) AS m FROM assistant_messages WHERE session_id = ?',
        [sessionId],
      );
      int seq = ((rows.first['m'] as int?) ?? -1) + 1;
      for (int i = 0; i < active.length; i++) {
        await txn.insert('assistant_messages', {
          'session_id': sessionId,
          'seq': seq + i,
          'message': jsonEncode(active[i].toJson()),
          'compacted': 0,
          'is_summary': i == 0 ? 1 : 0,
          'created_at': now,
        });
      }
      await txn.update('assistant_sessions', {'updated_at': now}, where: 'id = ?', whereArgs: [sessionId]);
    });
  }

  Future<List<AssistantSessionMeta>> listSessions() async {
    final db = await _getDb();
    final rows = await db.query('assistant_sessions', orderBy: 'updated_at DESC');
    return rows.map(AssistantSessionMeta.fromRow).toList();
  }

  Future<AssistantSessionMeta?> getSession(String id) async {
    final db = await _getDb();
    final rows = await db.query('assistant_sessions', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : AssistantSessionMeta.fromRow(rows.first);
  }

  /// Messages for replay: compacted rows excluded, summary rows included.
  /// Individually corrupt rows are dropped with a debug log — a damaged
  /// message must not make the whole conversation unopenable.
  Future<List<StoredAssistantMessage>> loadMessages(String sessionId, {bool includeCompacted = false}) async {
    final db = await _getDb();
    final rows = await db.query(
      'assistant_messages',
      where: includeCompacted ? 'session_id = ?' : 'session_id = ? AND compacted = 0',
      whereArgs: [sessionId],
      orderBy: 'seq ASC',
    );
    final result = <StoredAssistantMessage>[];
    for (final row in rows) {
      try {
        result.add(StoredAssistantMessage(
          seq: row['seq'] as int,
          message: LLMMessage.fromJson(
              (jsonDecode(row['message'] as String) as Map).cast<String, dynamic>()),
          compacted: row['compacted'] == 1,
          isSummary: row['is_summary'] == 1,
        ));
      } catch (e) {
        debugPrint('assistant_messages: dropping corrupt row seq=${row['seq']}: $e');
      }
    }
    return result;
  }

  /// Highest stored seq + 1 (i.e. the next free sequence number).
  Future<int> nextSeq(String sessionId) async {
    final db = await _getDb();
    final rows = await db.rawQuery(
      'SELECT MAX(seq) AS m FROM assistant_messages WHERE session_id = ?',
      [sessionId],
    );
    final max = rows.first['m'] as int?;
    return (max ?? -1) + 1;
  }

  Future<void> renameSession(String id, String title) async {
    final db = await _getDb();
    await db.update('assistant_sessions', {'title': title}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteSession(String id) async {
    final db = await _getDb();
    await db.delete('assistant_messages', where: 'session_id = ?', whereArgs: [id]);
    await db.delete('assistant_sessions', where: 'id = ?', whereArgs: [id]);
  }

  /// Keeps the [keep] most recently updated sessions, deleting the rest.
  Future<void> enforceRetention(int keep) async {
    if (keep <= 0) return;
    final db = await _getDb();
    final rows = await db.query('assistant_sessions', orderBy: 'updated_at DESC', columns: ['id']);
    for (final row in rows.skip(keep)) {
      await deleteSession(row['id'] as String);
    }
  }
}
