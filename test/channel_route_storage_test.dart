import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/llm_model.dart';
import 'package:joycai_image_ai_toolkits/services/db/database_migrations.dart';
import 'package:joycai_image_ai_toolkits/services/db/database_service.dart';
import 'package:joycai_image_ai_toolkits/services/llm/channel_routes.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_routes.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/platforms.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/private_data_dir.dart';

Future<Set<String>> columnsOf(Database db, String table) async =>
    {for (final r in await db.rawQuery('PRAGMA table_info($table)')) r['name'] as String};

LLMModel chatModel({
  String? activeRoute,
  String? wireProtocol,
  String? routeParams,
  String tag = 'chat',
  String modelId = 'gpt-5.2',
}) =>
    LLMModel(
      modelId: modelId,
      modelName: modelId,
      tag: tag,
      activeRoute: activeRoute,
      wireProtocol: wireProtocol,
      routeParams: routeParams,
    );

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('v45 migration', () {
    test('adds the three route columns, unset, keeping existing rows', () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await db.execute('CREATE TABLE llm_channels (id INTEGER PRIMARY KEY, '
          'display_name TEXT, endpoint TEXT, api_key TEXT, type TEXT)');
      await db.execute('CREATE TABLE llm_models (id INTEGER PRIMARY KEY, '
          'model_id TEXT, model_name TEXT, tag TEXT, wire_protocol TEXT)');
      await db.insert('llm_channels', {
        'display_name': 'r',
        'endpoint': 'https://r.example/v1',
        'api_key': 'k',
        'type': Vendors.newApiOpenAI,
      });
      await db.insert('llm_models', {
        'model_id': 'm',
        'model_name': 'm',
        'tag': 'chat',
        'wire_protocol': 'openai-responses',
      });

      await DatabaseMigration.migrate(db, 44, 45);
      await DatabaseMigration.migrate(db, 44, 45); // idempotent

      expect(await columnsOf(db, 'llm_channels'), contains('routes'));
      expect(await columnsOf(db, 'llm_models'),
          containsAll(['active_route', 'route_params']));
      final channel = (await db.query('llm_channels')).single;
      expect(channel['routes'], isNull);
      expect(channel['endpoint'], 'https://r.example/v1');
      final model = (await db.query('llm_models')).single;
      expect(model['active_route'], isNull);
      expect(model['wire_protocol'], 'openai-responses');
    });

    test('a fresh database is created with them', () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await DatabaseMigration.onCreate(db);
      expect(await columnsOf(db, 'llm_channels'), contains('routes'));
      expect(await columnsOf(db, 'llm_models'),
          containsAll(['active_route', 'route_params']));
    });
  });

  group('the repository normalizes on read and write', () {
    usePrivateDataDir('joycai_channel_route_storage_test');

    test('a legacy row reads with its derived routes', () async {
      final db = DatabaseService();
      final id = await db.addChannel({
        'display_name': 'Bailian',
        'type': Vendors.dashscopeNative,
        'endpoint': 'https://dashscope.aliyuncs.com/api/v1',
        'api_key': 'k',
      });
      final channel = (await db.getChannel(id))!;
      expect(channel.routes, isNotNull);
      final routes =
          ChannelRoutes.resolve(channel.type, channel.endpoint, channel.routes);
      expect(routes.kinds,
          [RouteKind.dashscope, RouteKind.chat, RouteKind.anthropic]);
      expect(channel.endpoint, 'https://dashscope.aliyuncs.com/api/v1');
    });

    test('a flat-only update keeps the other routes', () async {
      final db = DatabaseService();
      final routes = ChannelRoutes.create(Platforms.byId(Platforms.newapi),
          'https://r.example', [RouteKind.chat, RouteKind.gemini]);
      final id = await db.addChannel({
        'display_name': 'Relay',
        'type': routes.primaryVendorId,
        'endpoint': routes.primaryAddress,
        'api_key': 'k',
        'routes': routes.encode(),
      });
      // The pre-route channel editor writes a map without `routes`.
      await db.updateChannel(id, {
        'display_name': 'Relay',
        'type': Vendors.newApiOpenAI,
        'endpoint': 'https://moved.example/v1',
        'api_key': 'k',
      });
      final channel = (await db.getChannel(id))!;
      final after =
          ChannelRoutes.resolve(channel.type, channel.endpoint, channel.routes);
      expect(after.kinds, containsAll([RouteKind.chat, RouteKind.gemini]));
      expect(after.addressOf(RouteKind.gemini), 'https://moved.example/v1beta');
    });

    test('model route columns round-trip', () async {
      final db = DatabaseService();
      final channelId = await db.addChannel({
        'display_name': 'c',
        'type': Vendors.newApiOpenAI,
        'endpoint': 'https://r.example/v1',
        'api_key': 'k',
      });
      final pk = await db.addModel({
        'model_id': 'gpt-5.2',
        'model_name': 'GPT',
        'tag': 'chat',
        'channel_id': channelId,
        'active_route': 'responses',
        'route_params': '{"chat":{"max_output_tokens":4096}}',
      });
      final model = (await db.getModels()).firstWhere((m) => m.id == pk);
      expect(model.activeRoute, 'responses');
      expect(ModelRoutes.parked(model),
          {RouteKind.chat: const RouteParams(maxOutputTokens: 4096)});
    });
  });

  group('ModelRoutes', () {
    final relay = ChannelRoutes.create(Platforms.byId(Platforms.newapi),
        'https://r.example', [RouteKind.chat, RouteKind.responses]);

    test('a legacy chat pin reads as the route it pinned', () {
      final m = chatModel(wireProtocol: 'openai-responses');
      expect(ModelRoutes.explicitRoute(m), RouteKind.responses);
      expect(ModelRoutes.requestRoute(m, relay), RouteKind.responses);
    });

    test('no selection follows the primary route', () {
      final m = chatModel();
      expect(ModelRoutes.explicitRoute(m), isNull);
      expect(ModelRoutes.requestRoute(m, relay), RouteKind.chat);
    });

    test('a stale legacy pin still degrades to the primary', () {
      final m = chatModel(wireProtocol: 'anthropic-chat');
      expect(ModelRoutes.requestRoute(m, relay), RouteKind.chat);
    });

    test('an explicit route the channel lost fails the request, not the view',
        () {
      final m = chatModel(activeRoute: 'gemini');
      expect(ModelRoutes.requestRoute(m, relay), isNull);
      expect(ModelRoutes.displayRoute(m, relay), RouteKind.chat);
    });

    test('image and video models ride no route', () {
      final m = chatModel(
          tag: 'image', modelId: 'gpt-image-1', activeRoute: 'responses',
          wireProtocol: 'openai-images');
      expect(ModelRoutes.usesRoutes(m), isFalse);
      expect(ModelRoutes.explicitRoute(m), isNull);
      expect(ModelRoutes.requestRoute(m, relay), RouteKind.chat);
    });

    test('enabled routes: current first, then parked in channel order', () {
      final m = chatModel(
          activeRoute: 'responses',
          routeParams: '{"chat":{},"gemini":{"reasoning_effort":"high"}}');
      expect(ModelRoutes.enabledRoutes(m, relay),
          [RouteKind.responses, RouteKind.chat]);
    });

    test('parked parameters are narrowed field by field', () {
      final m = chatModel(
          routeParams: '{"chat":{"max_output_tokens":"lots","enable_thinking":1,'
              '"reasoning_effort":"low"},"telepathy":{},"responses":7}');
      expect(ModelRoutes.parked(m), {
        RouteKind.chat: const RouteParams(reasoningEffort: 'low'),
        RouteKind.responses: RouteParams.empty,
      });
      expect(ModelRoutes.parked(chatModel(routeParams: 'nope')), isEmpty);
    });

    test('encodeParked is null when empty and round-trips otherwise', () {
      expect(ModelRoutes.encodeParked(const {}), isNull);
      final parked = {
        RouteKind.anthropic:
            const RouteParams(maxOutputTokens: 8192, enableThinking: true),
        RouteKind.chat: RouteParams.empty,
      };
      final m = chatModel(routeParams: ModelRoutes.encodeParked(parked));
      expect(ModelRoutes.parked(m), parked);
    });
  });
}
