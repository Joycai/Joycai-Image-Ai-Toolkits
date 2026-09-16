import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../database_service.dart';

/// How long the downloader remembers a site's cookies (S3).
///
/// Cookies are session credentials, kept unencrypted in the local database,
/// so how long they linger is the user's call rather than forever by default.
enum CookieRetention {
  /// Nothing is written; switching to this forgets what was kept.
  off('off', null),
  week('7d', Duration(days: 7)),
  month('30d', Duration(days: 30)),

  /// Kept until the user removes them.
  untilCleared('forever', null);

  const CookieRetention(this.id, this.lifetime);

  /// Stored in `settings` under [CookieRepository.retentionKey].
  final String id;

  /// How long after its last use a row is dropped, or null for never.
  final Duration? lifetime;

  static CookieRetention fromId(String? id) => CookieRetention.values
      .firstWhere((r) => r.id == id, orElse: () => CookieRepository.defaultRetention);
}

/// The downloader's remembered cookies (`downloader_cookies`): the last few
/// hosts, their cookie strings and when each was last used — under the
/// retention the user chose.
class CookieRepository {
  CookieRepository({DatabaseService? db}) : _dbService = db ?? DatabaseService();

  final DatabaseService _dbService;

  static const String retentionKey = 'downloader_cookie_retention';
  static const CookieRetention defaultRetention = CookieRetention.month;

  /// Hosts kept at most, newest first.
  static const int maxHosts = 5;

  Future<Database> get _db async => _dbService.database;

  Future<CookieRetention> retention() async =>
      CookieRetention.fromId(await _dbService.getSetting(retentionKey));

  /// Stores [retention]; turning remembering off forgets every row now.
  Future<void> setRetention(CookieRetention retention) async {
    await _dbService.saveSetting(retentionKey, retention.id);
    if (retention == CookieRetention.off) await clear();
  }

  /// Remembers [cookies] for [host], unless the user asked not to.
  Future<void> save(String host, String cookies, {DateTime? now}) async {
    if (host.isEmpty || cookies.isEmpty) return;
    if (await retention() == CookieRetention.off) return;
    final db = await _db;
    await db.insert('downloader_cookies', {
      'host': host,
      'cookies': cookies,
      'last_used': (now ?? DateTime.now()).toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    final all = await db.query('downloader_cookies', columns: ['host'], orderBy: 'last_used DESC');
    for (final row in all.skip(maxHosts)) {
      await db.delete('downloader_cookies', where: 'host = ?', whereArgs: [row['host']]);
    }
  }

  /// The remembered hosts, newest first, after dropping any past their
  /// retention.
  Future<List<Map<String, dynamic>>> list({DateTime? now}) async {
    await _prune(now ?? DateTime.now());
    final db = await _db;
    return db.query('downloader_cookies', orderBy: 'last_used DESC');
  }

  /// The cookie string remembered for [host], or null.
  Future<String?> lookup(String host, {DateTime? now}) async {
    if (host.isEmpty) return null;
    await _prune(now ?? DateTime.now());
    final db = await _db;
    final rows = await db.query('downloader_cookies',
        columns: ['cookies'], where: 'host = ?', whereArgs: [host]);
    final value = rows.isEmpty ? null : rows.first['cookies'] as String?;
    return (value == null || value.isEmpty) ? null : value;
  }

  Future<void> delete(String host) async {
    final db = await _db;
    await db.delete('downloader_cookies', where: 'host = ?', whereArgs: [host]);
  }

  Future<void> clear() async {
    final db = await _db;
    await db.delete('downloader_cookies');
  }

  Future<void> _prune(DateTime now) async {
    final lifetime = (await retention()).lifetime;
    if (lifetime == null) return;
    final db = await _db;
    // ISO-8601 strings in one zone order like the instants they name.
    await db.delete('downloader_cookies',
        where: 'last_used < ?', whereArgs: [now.subtract(lifetime).toIso8601String()]);
  }

  /// [parameters] as a task row may store them: without the `cookies` a
  /// download was queued with. The running task keeps its copy in memory;
  /// a download restored after a restart asks [lookup] for its host instead.
  ///
  /// An *empty* value stays: it records that the user queued the download
  /// without cookies, and a restored task must not fill them in from the
  /// history.
  static String withoutCookies(String parametersJson) {
    try {
      final decoded = jsonDecode(parametersJson);
      if (decoded is! Map) return parametersJson;
      final cookies = decoded['cookies'];
      if (cookies == null || (cookies is String && cookies.isEmpty)) return parametersJson;
      return jsonEncode(Map<String, dynamic>.from(decoded)..remove('cookies'));
    } on FormatException {
      return parametersJson;
    }
  }
}
