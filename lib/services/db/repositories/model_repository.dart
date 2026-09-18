import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../models/llm_channel.dart';
import '../../../models/llm_model.dart';
import '../../../models/pricing_group.dart';
import '../../llm/channel_routes.dart';
import '../database_service.dart';

class ModelRepository {
  final DatabaseService _dbService = DatabaseService();

  Future<Database> get _db async => _dbService.database;

  // LLM Models Methods
  Future<int> addModel(LLMModel model) async {
    final db = await _db;
    return db.insert('llm_models', model.toMap(includeId: false));
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
    return db.insert('llm_channels', {
      ...normalizedChannel(channel).toMap(includeId: false),
      'sort_order': (maxOrder ?? -1) + 1,
    });
  }

  /// Writes [channel] normalized. A caller that does not carry a route
  /// document (one that edits only the flat endpoint and type) keeps the
  /// stored one: the write mark then tells [ChannelRoutes.resolve] that the
  /// primary route moved, and the channel's other routes survive the save.
  Future<void> updateChannel(int id, LLMChannel channel) async {
    final db = await _db;
    var incoming = channel;
    if (incoming.routes == null) {
      final stored = await db.query('llm_channels',
          columns: ['routes'], where: 'id = ?', whereArgs: [id]);
      final doc = stored.isEmpty ? null : stored.first['routes'] as String?;
      if (doc != null) {
        incoming = incoming.withRoutes(
            type: incoming.type, endpoint: incoming.endpoint, routes: doc);
      }
    }
    await db.update('llm_channels', normalizedChannel(incoming).toMap(includeId: false),
        where: 'id = ?', whereArgs: [id]);
  }

  /// [channel] with its route document resolved against its flat columns and
  /// the flat columns rewritten to the primary route — run on every read and
  /// every write, and idempotent, so "`type` / `endpoint` are the primary
  /// route" is a fact rather than a convention (standard 02 §2).
  static LLMChannel normalizedChannel(LLMChannel channel) {
    final routes =
        ChannelRoutes.resolve(channel.type, channel.endpoint, channel.routes);
    return channel.withRoutes(
      type: routes.primaryVendorId,
      endpoint: routes.primaryAddress,
      routes: routes.encode(),
    );
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

  /// Writes a channel merge in one transaction, in the only safe order
  /// (standard 04 §4): the kept [channel] first, so the routes exist before
  /// a model points at them; then [updates], so a moved model belongs to the
  /// kept channel before its old one is cleared; then the merged-away
  /// [deletes]; then whatever is still on [absorbedChannelId]; then that
  /// channel. A failure anywhere leaves both channels as they were.
  Future<void> mergeChannels({
    required LLMChannel channel,
    required List<LLMModel> updates,
    required List<int> deletes,
    required int absorbedChannelId,
  }) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.update(
        'llm_channels',
        normalizedChannel(channel).toMap(includeId: false),
        where: 'id = ?',
        whereArgs: [channel.id],
      );
      // Only the columns a merge changes: the plan was computed from a
      // snapshot, and a whole row would revert anything written since (an
      // edit, the task queue's duration estimate).
      for (final m in updates) {
        await txn.update(
            'llm_models',
            {
              'channel_id': m.channelId,
              'active_route': m.activeRoute,
              'route_params': m.routeParams,
              'wire_protocol': m.wireProtocol,
            },
            where: 'id = ?',
            whereArgs: [m.id]);
      }
      for (final id in deletes) {
        await txn.delete('llm_models', where: 'id = ?', whereArgs: [id]);
      }
      await txn.delete('llm_models',
          where: 'channel_id = ?', whereArgs: [absorbedChannelId]);
      await txn.delete('llm_channels',
          where: 'id = ?', whereArgs: [absorbedChannelId]);
    });
  }

  Future<List<LLMChannel>> getChannels() async {
    final db = await _db;
    // `sort_order` is the user's arrangement; `id` breaks ties so channels
    // restored from a backup written before the column existed (all zeros)
    // still come back in creation order rather than an arbitrary one.
    final maps = await db.query('llm_channels', orderBy: 'sort_order ASC, id ASC');
    return maps.map((m) => normalizedChannel(LLMChannel.fromMap(m))).toList();
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
      return normalizedChannel(LLMChannel.fromMap(maps.first));
    }
    return null;
  }

  // Pricing Groups Methods
  Future<int> addPricingGroup(PricingGroup group) async {
    final db = await _db;
    // Appended, as channels are: `PricingGroup.toMap` omits `sort_order`
    // (owned by [updatePricingGroupOrder] alone), and the column default of
    // 0 would put every new group at the top of the list.
    final maxRow = await db.rawQuery('SELECT MAX(sort_order) AS m FROM fee_groups');
    final maxOrder = maxRow.first['m'] as int?;
    return db.insert('fee_groups', {
      ...group.toMap(includeId: false),
      'sort_order': (maxOrder ?? -1) + 1,
    });
  }

  /// Persists the fee-group page's arrangement: [orderedIds] is every group
  /// in its new order, rewritten to a dense 0..N-1 range in one batch.
  Future<void> updatePricingGroupOrder(List<int> orderedIds) async {
    final db = await _db;
    final batch = db.batch();
    for (var i = 0; i < orderedIds.length; i++) {
      batch.update('fee_groups', {'sort_order': i}, where: 'id = ?', whereArgs: [orderedIds[i]]);
    }
    await batch.commit(noResult: true);
  }

  Future<void> updatePricingGroup(int id, PricingGroup group) async {
    final db = await _db;
    await db.update('fee_groups', group.toMap(includeId: false), where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deletePricingGroup(int id) async {
    final db = await _db;
    await db.update('llm_models', {'fee_group_id': null}, where: 'fee_group_id = ?', whereArgs: [id]);
    await db.update('llm_channels', {'default_fee_group_id': null},
        where: 'default_fee_group_id = ?', whereArgs: [id]);
    await db.delete('fee_groups', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<PricingGroup>> getPricingGroups() async {
    final db = await _db;
    // `sort_order` is the user's arrangement; `id` breaks ties so a backup
    // written before the column existed still lists in creation order.
    final maps = await db.query('fee_groups', orderBy: 'sort_order ASC, id ASC');
    return maps.map((m) => PricingGroup.fromMap(m)).toList();
  }
}
