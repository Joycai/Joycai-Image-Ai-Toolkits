import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../database_service.dart';

/// One stored sub-agent research note.
class AssistantNote {
  final int id;
  final String sessionId;
  final String slug;
  final String title;
  final String content;
  final DateTime createdAt;

  const AssistantNote({
    required this.id,
    required this.sessionId,
    required this.slug,
    required this.title,
    required this.content,
    required this.createdAt,
  });

  static AssistantNote fromRow(Map<String, dynamic> row) => AssistantNote(
        id: row['id'] as int,
        sessionId: row['session_id'] as String,
        slug: row['slug'] as String? ?? '',
        title: row['title'] as String? ?? '',
        content: row['content'] as String? ?? '',
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int? ?? 0),
      );
}

/// SQLite store for knowledge sub-agent findings (`assistant_notes`, v34).
///
/// Notes are **session-scoped**: they are commissioned by one conversation,
/// read back only by that conversation, and die with it. This is the app's
/// form of the playbook's "findings go to disk, the tool result carries a
/// digest + a reference" — SQLite session scope instead of an on-disk task
/// workspace because there is no pause/resume to survive yet; the two designs
/// are compatible if that ever changes.
class AssistantNoteRepository {
  /// [dbProvider] exists for tests (an in-memory database); production code
  /// uses the default [DatabaseService].
  AssistantNoteRepository({Future<Database> Function()? dbProvider})
      : _dbProvider = dbProvider;

  final Future<Database> Function()? _dbProvider;

  Future<Database> _getDb() async =>
      _dbProvider != null ? await _dbProvider() : await DatabaseService().database;

  /// Hard cap on stored note content. Sub-agent digests are typically a few
  /// KB; anything beyond this is stored truncated **with a visible marker**
  /// rather than rejected — the note is derived data (the knowledge base
  /// itself remains re-readable), so losing its tail is an acceptable cost
  /// while silently failing to store anything is not.
  static const int maxContentChars = 64000;

  /// Keeps letters/digits in any script plus `-`; everything else becomes
  /// `-`. An ASCII whitelist here would collapse every CJK title into the
  /// same empty slug. Truncated by code points so a surrogate pair is never
  /// split.
  @visibleForTesting
  static String sanitizeSlug(String raw) {
    final cleaned = raw
        .replaceAll(RegExp(r'[^\p{L}\p{N}-]+', unicode: true), '-')
        .replaceAll(RegExp(r'-{2,}'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final runes = cleaned.runes.toList();
    final capped = runes.length > 60 ? String.fromCharCodes(runes.take(60)) : cleaned;
    return capped.isEmpty ? 'note' : capped;
  }

  /// Stores a note and returns it (with its assigned id and final slug).
  ///
  /// Slug collisions within the session get a `-2` / `-3` suffix — never an
  /// overwrite, and the caller sees the name that actually stuck.
  Future<AssistantNote> insert({
    required String sessionId,
    required String title,
    required String content,
  }) async {
    final db = await _getDb();
    final base = sanitizeSlug(title);
    final existing = await db.query(
      'assistant_notes',
      columns: ['slug'],
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
    final taken = {for (final row in existing) row['slug'] as String};
    var slug = base;
    for (var n = 2; taken.contains(slug); n++) {
      slug = '$base-$n';
    }

    final storedContent = content.length > maxContentChars
        ? '${content.substring(0, maxContentChars)}\n\n'
            '[note truncated at $maxContentChars characters]'
        : content;

    final now = DateTime.now();
    final id = await db.insert('assistant_notes', {
      'session_id': sessionId,
      'slug': slug,
      'title': title,
      'content': storedContent,
      'created_at': now.millisecondsSinceEpoch,
    });
    return AssistantNote(
      id: id,
      sessionId: sessionId,
      slug: slug,
      title: title,
      content: storedContent,
      createdAt: now,
    );
  }

  /// The note with [id] — but only if it belongs to [sessionId]. A note id
  /// pointing into another session returns null rather than content: reading
  /// a note nobody in this conversation commissioned is worse than not
  /// finding it (same rule the playbook applies to cross-task note refs).
  Future<AssistantNote?> get(int id, {required String sessionId}) async {
    final db = await _getDb();
    final rows = await db.query(
      'assistant_notes',
      where: 'id = ? AND session_id = ?',
      whereArgs: [id, sessionId],
      limit: 1,
    );
    return rows.isEmpty ? null : AssistantNote.fromRow(rows.first);
  }

  /// Notes of one session, oldest first (stable order for listings).
  Future<List<AssistantNote>> listForSession(String sessionId) async {
    final db = await _getDb();
    final rows = await db.query(
      'assistant_notes',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'id ASC',
    );
    return rows.map(AssistantNote.fromRow).toList();
  }

  /// Removes a session's notes. Called by
  /// `AssistantSessionRepository.deleteSession` so retention GC covers notes
  /// without a second policy.
  Future<void> deleteForSession(String sessionId) async {
    final db = await _getDb();
    await db.delete('assistant_notes',
        where: 'session_id = ?', whereArgs: [sessionId]);
  }
}
