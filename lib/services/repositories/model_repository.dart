import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../database_service.dart';

class ModelRepository {
  final DatabaseService _dbService = DatabaseService();

  Future<Database> get _db async => await _dbService.database;

  // LLM Models Methods
  Future<int> addModel(Map<String, dynamic> model) async {
    final db = await _db;
    return await db.insert('llm_models', model);
  }

  Future<void> updateModel(int id, Map<String, dynamic> model) async {
    final db = await _db;
    await db.update('llm_models', model, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateModelOrder(List<int> ids) async {
    final db = await _db;
    final batch = db.batch();
    for (int i = 0; i < ids.length; i++) {
      batch.update('llm_models', {'sort_order': i}, where: 'id = ?', whereArgs: [ids[i]]);
    }
    await batch.commit(noResult: true);
  }

  Future<void> deleteModel(int id) async {
    final db = await _db;
    await db.delete('llm_models', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getModels() async {
    final db = await _db;
    return await db.query('llm_models', orderBy: 'sort_order ASC');
  }

  Future<void> updateModelEstimation(int modelPk, double mean, double sd, int tasksSinceUpdate) async {
    final db = await _db;
    await db.update(
      'llm_models',
      {
        'est_mean_ms': mean,
        'est_sd_ms': sd,
        'tasks_since_update': tasksSinceUpdate,
      },
      where: 'id = ?',
      whereArgs: [modelPk],
    );
  }

  // LLM Channels Methods
  Future<int> addChannel(Map<String, dynamic> channel) async {
    final db = await _db;
    return await db.insert('llm_channels', channel);
  }

  Future<void> updateChannel(int id, Map<String, dynamic> channel) async {
    final db = await _db;
    await db.update('llm_channels', channel, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteChannel(int id) async {
    final db = await _db;
    await db.update('llm_models', {'channel_id': null}, where: 'channel_id = ?', whereArgs: [id]);
    await db.delete('llm_channels', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getChannels() async {
    final db = await _db;
    return await db.query('llm_channels');
  }

  Future<Map<String, dynamic>?> getChannel(int id) async {
    final db = await _db;
    final maps = await db.query('llm_channels', where: 'id = ?', whereArgs: [id]);
    return maps.isNotEmpty ? maps.first : null;
  }

  // Fee Groups Methods
  Future<int> addFeeGroup(Map<String, dynamic> group) async {
    final db = await _db;
    return await db.insert('fee_groups', group);
  }

  Future<void> updateFeeGroup(int id, Map<String, dynamic> group) async {
    final db = await _db;
    await db.update('fee_groups', group, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteFeeGroup(int id) async {
    final db = await _db;
    await db.update('llm_models', {'fee_group_id': null}, where: 'fee_group_id = ?', whereArgs: [id]);
    await db.delete('fee_groups', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getFeeGroups() async {
    final db = await _db;
    return await db.query('fee_groups');
  }
}
