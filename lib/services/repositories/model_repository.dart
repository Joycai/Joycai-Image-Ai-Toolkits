import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../models/llm_channel.dart';
import '../../models/llm_model.dart';
import '../../models/pricing_group.dart';
import '../database_service.dart';

class ModelRepository {
  final DatabaseService _dbService = DatabaseService();

  Future<Database> get _db async => await _dbService.database;

  // LLM Models Methods
  Future<int> addModel(LLMModel model) async {
    final db = await _db;
    return await db.insert('llm_models', model.toMap(includeId: false));
  }

  Future<void> updateModel(int id, LLMModel model) async {
    final db = await _db;
    await db.update('llm_models', model.toMap(includeId: false), where: 'id = ?', whereArgs: [id]);
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

  Future<void> updateModelEstimation(int modelDbId, double mean, double sd, int tasksSinceUpdate) async {
    final db = await _db;
    await db.update(
      'llm_models',
      {
        'est_mean_ms': mean,
        'est_sd_ms': sd,
        'tasks_since_update': tasksSinceUpdate,
      },
      where: 'id = ?',
      whereArgs: [modelDbId],
    );
  }

  // LLM Channels Methods
  Future<int> addChannel(LLMChannel channel) async {
    final db = await _db;
    // Append rather than inherit the column default: `LLMChannel.toMap` omits
    // `sort_order` (it is owned by [updateChannelOrder] alone), so an
    // untouched insert would land at 0 and put every new channel at the *top*
    // of the rail — the opposite of where a just-added item belongs.
    final maxRow = await db
        .rawQuery('SELECT MAX(sort_order) AS m FROM llm_channels');
    final maxOrder = maxRow.first['m'] as int?;
    return await db.insert('llm_channels', {
      ...channel.toMap(includeId: false),
      'sort_order': (maxOrder ?? -1) + 1,
    });
  }

  Future<void> updateChannel(int id, LLMChannel channel) async {
    final db = await _db;
    await db.update('llm_channels', channel.toMap(includeId: false), where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteChannel(int id) async {
    final db = await _db;
    // Delete the channel's models too. A model without a channel can't resolve
    // an endpoint/key (it's unusable), and the previous behavior of merely
    // nulling channel_id left orphaned rows that leaked into the workbench model
    // selector — appearing as a "ghost" channel with a blank selection.
    await db.delete('llm_models', where: 'channel_id = ?', whereArgs: [id]);
    await db.delete('llm_channels', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<LLMChannel>> getChannels() async {
    final db = await _db;
    // `sort_order` is the user's arrangement; `id` breaks ties so channels
    // restored from a backup written before the column existed (all zeros)
    // still come back in creation order rather than an arbitrary one.
    final maps = await db.query('llm_channels', orderBy: 'sort_order ASC, id ASC');
    return maps.map((m) => LLMChannel.fromMap(m)).toList();
  }

  /// Persists the rail's arrangement: [orderedIds] is the full channel list in
  /// its new order, rewritten to a dense 0..N-1 range in one transaction so a
  /// crash mid-write cannot leave two channels claiming the same slot.
  Future<void> updateChannelOrder(List<int> orderedIds) async {
    final db = await _db;
    final batch = db.batch();
    for (var i = 0; i < orderedIds.length; i++) {
      batch.update('llm_channels', {'sort_order': i},
          where: 'id = ?', whereArgs: [orderedIds[i]]);
    }
    await batch.commit(noResult: true);
  }

  Future<LLMChannel?> getChannel(int id) async {
    final db = await _db;
    final maps = await db.query('llm_channels', where: 'id = ?', whereArgs: [id]);
    if (maps.isNotEmpty) {
      return LLMChannel.fromMap(maps.first);
    }
    return null;
  }

  // Pricing Groups Methods
  Future<int> addPricingGroup(PricingGroup group) async {
    final db = await _db;
    return await db.insert('fee_groups', group.toMap(includeId: false));
  }

  Future<void> updatePricingGroup(int id, PricingGroup group) async {
    final db = await _db;
    await db.update('fee_groups', group.toMap(includeId: false), where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deletePricingGroup(int id) async {
    final db = await _db;
    await db.update('llm_models', {'fee_group_id': null}, where: 'fee_group_id = ?', whereArgs: [id]);
    await db.delete('fee_groups', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<PricingGroup>> getPricingGroups() async {
    final db = await _db;
    final maps = await db.query('fee_groups');
    return maps.map((m) => PricingGroup.fromMap(m)).toList();
  }
}
