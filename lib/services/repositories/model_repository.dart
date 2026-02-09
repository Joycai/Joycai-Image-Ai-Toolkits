import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../models/fee_group.dart';
import '../../models/llm_channel.dart';
import '../../models/llm_model.dart';
import '../database_service.dart';

class ModelRepository {
  final DatabaseService _dbService = DatabaseService();

  Future<Database> get _db async => await _dbService.database;

  // LLM Models Methods
  Future<int> addModel(LLMModel model) async {
    final db = await _db;
    return await db.insert('llm_models', model.toMap());
  }

  Future<void> updateModel(int id, LLMModel model) async {
    final db = await _db;
    await db.update('llm_models', model.toMap(), where: 'id = ?', whereArgs: [id]);
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

  Future<List<LLMModel>> getModels() async {
    final db = await _db;
    final maps = await db.query('llm_models', orderBy: 'sort_order ASC');
    return maps.map((m) => LLMModel.fromMap(m)).toList();
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
  Future<int> addChannel(LLMChannel channel) async {
    final db = await _db;
    return await db.insert('llm_channels', channel.toMap());
  }

  Future<void> updateChannel(int id, LLMChannel channel) async {
    final db = await _db;
    await db.update('llm_channels', channel.toMap(), where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteChannel(int id) async {
    final db = await _db;
    await db.update('llm_models', {'channel_id': null}, where: 'channel_id = ?', whereArgs: [id]);
    await db.delete('llm_channels', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<LLMChannel>> getChannels() async {
    final db = await _db;
    final maps = await db.query('llm_channels');
    return maps.map((m) => LLMChannel.fromMap(m)).toList();
  }

  Future<LLMChannel?> getChannel(int id) async {
    final db = await _db;
    final maps = await db.query('llm_channels', where: 'id = ?', whereArgs: [id]);
    if (maps.isNotEmpty) {
      return LLMChannel.fromMap(maps.first);
    }
    return null;
  }

  // Fee Groups Methods
  Future<int> addFeeGroup(FeeGroup group) async {
    final db = await _db;
    return await db.insert('fee_groups', group.toMap());
  }

  Future<void> updateFeeGroup(int id, FeeGroup group) async {
    final db = await _db;
    await db.update('fee_groups', group.toMap(), where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteFeeGroup(int id) async {
    final db = await _db;
    await db.update('llm_models', {'fee_group_id': null}, where: 'fee_group_id = ?', whereArgs: [id]);
    await db.delete('fee_groups', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<FeeGroup>> getFeeGroups() async {
    final db = await _db;
    final maps = await db.query('fee_groups');
    return maps.map((m) => FeeGroup.fromMap(m)).toList();
  }
}