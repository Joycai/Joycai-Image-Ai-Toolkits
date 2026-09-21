import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/spec_rate.dart';
import 'package:joycai_image_ai_toolkits/models/token_usage.dart';
import 'package:joycai_image_ai_toolkits/models/usage_checkpoint.dart';

/// Pins down how one usage row turns into money. Input, cache hits and output
/// are billed at three separate rates, and a fee group that leaves the cache
/// rate unset must fall back to the input rate rather than billing the cache
/// free. Also pins the row's trip to a `token_usage` row and back, legacy
/// shapes included.
void main() {
  final at = DateTime(2026, 9, 1, 12);

  group('TokenUsage.cost', () {
    test('bills input, cache and output at their own rates', () {
      final row = TokenUsage(
        modelId: 'm',
        timestamp: at,
        inputTokens: 1000000,
        cacheTokens: 1000000,
        outputTokens: 1000000,
        inputPrice: 2.0,
        cachePrice: 0.5,
        outputPrice: 10.0,
      );

      expect(row.cost, closeTo(12.5, 1e-9));
      expect(row.costParts.cache, closeTo(0.5, 1e-9));
    });

    test('falls back to the input rate when the cache rate is unset', () {
      // A null cache price is what an unconfigured fee group writes, and what
      // every row recorded before cache pricing existed carries.
      final row = TokenUsage(modelId: 'm', timestamp: at, cacheTokens: 1000000, inputPrice: 2.0);

      expect(row.cost, closeTo(2.0, 1e-9));
    });

    test('honours an explicit free cache rate instead of inheriting input', () {
      final row = TokenUsage(
        modelId: 'm',
        timestamp: at,
        cacheTokens: 1000000,
        inputPrice: 2.0,
        cachePrice: 0.0,
      );

      expect(row.cost, 0.0);
    });

    test('request-billed rows ignore token prices entirely', () {
      final row = TokenUsage(
        modelId: 'm',
        timestamp: at,
        billingMode: 'request',
        inputTokens: 5000,
        cacheTokens: 5000,
        outputTokens: 5000,
        inputPrice: 99.0,
        requestCount: 3,
        requestPrice: 0.02,
      );

      expect(row.cost, closeTo(0.06, 1e-9));
    });

    test('a mode nobody spelled out bills by request, as it always has', () {
      final row = TokenUsage(
        modelId: 'm',
        timestamp: at,
        billingMode: 'per-job',
        inputTokens: 5000,
        inputPrice: 99.0,
        requestPrice: 0.5,
      );

      expect(row.billing, UsageBilling.request);
      expect(row.cost, 0.5);
    });

    test('spec-billed rows price units × unit price and nothing else', () {
      final row = TokenUsage(
        modelId: 'm',
        timestamp: at,
        billingMode: 'spec',
        inputTokens: 5000,
        inputPrice: 99.0,
        requestPrice: 0.02,
        spec: const UsageSpecBilling(unit: OutputUnit.second, units: 8.0, unitPrice: 0.30),
      );

      expect(row.cost, closeTo(2.40, 1e-9));
    });

    test('a spec-billed row missing its columns prices zero, not a crash', () {
      final row = TokenUsage.fromMap({'billing_mode': 'spec', 'model_id': 'm'});

      expect(row.spec, isNull);
      expect(row.cost, 0.0);
      expect(row.specLabel, isNull);
    });
  });

  group('unmatched and specLabel', () {
    TokenUsage row(String mode, UsageSpecSnapshot? snapshot) => TokenUsage(
          modelId: 'm',
          timestamp: at,
          billingMode: mode,
          spec: UsageSpecBilling(units: 1, unitPrice: 0, snapshot: snapshot),
        );

    test('only a spec row whose snapshot says so is unmatched', () {
      expect(row('spec', const UsageSpecSnapshot(matched: false)).unmatched, isTrue);
      expect(row('spec', const UsageSpecSnapshot()).unmatched, isFalse);
      // A row without the snapshot cannot say, so counts as matched.
      expect(row('spec', null).unmatched, isFalse);
      expect(row('request', const UsageSpecSnapshot(matched: false)).unmatched, isFalse);
    });

    test('the label leaves absent dimensions out', () {
      const full = UsageSpecSnapshot(size: '1080p', quality: 'high', seconds: 8);
      expect(row('spec', full).specLabel, '1080p · high · 8s');
      expect(row('spec', const UsageSpecSnapshot(size: '1K')).specLabel, '1K');
      expect(row('spec', const UsageSpecSnapshot()).specLabel, isEmpty);
      expect(row('token', full).specLabel, isNull);
    });
  });

  group('the token_usage row', () {
    test('legacy rows written before cache columns existed still price', () {
      // Rows read back from a pre-v30 database have no cache keys at all.
      final row = TokenUsage.fromMap({
        'billing_mode': 'token',
        'model_id': 'm',
        'timestamp': at.toIso8601String(),
        'input_tokens': 1000000,
        'output_tokens': 1000000,
        'input_price': 3.0,
        'output_price': 6.0,
        'request_count': 1,
      });

      expect(row.cachePrice, isNull);
      expect(row.cost, closeTo(9.0, 1e-9));
    });

    test('a row with NULL in every defaulted column reads as the defaults', () {
      final row = TokenUsage.fromMap({
        'model_id': 'm',
        'timestamp': at.toIso8601String(),
        'billing_mode': null,
        'request_count': null,
        'input_tokens': null,
      });

      expect(row.billing, UsageBilling.token);
      expect(row.requestCount, 1);
      expect(row.inputTokens, 0);
    });

    test('a malformed output_spec is no snapshot, not an error', () {
      for (final raw in ['junk', '', '[]', null]) {
        final row = TokenUsage.fromMap({
          'model_id': 'm',
          'billing_mode': 'spec',
          'output_units': 2,
          'output_unit_price': 0.03,
          'output_unit': 'image',
          'output_spec': raw,
        });
        expect(row.spec!.snapshot, isNull, reason: '$raw');
        expect(row.unmatched, isFalse, reason: '$raw');
        expect(row.cost, closeTo(0.06, 1e-9), reason: '$raw');
      }
    });

    test('a snapshot is read the way older writers left it', () {
      // `seconds` as a double, and no `matched` key at all.
      final snapshot = UsageSpecSnapshot.tryDecode('{"size":"1080p","seconds":8.0}')!;

      expect(snapshot.seconds, 8);
      expect(snapshot.matched, isTrue);
      expect(snapshot.label, '1080p · 8s');
      expect(UsageSpecSnapshot.tryDecode('{"seconds":1e999}')!.seconds, isNull);
    });

    test('a row that predates spec billing has no spec, whatever the ALTER left', () {
      // v42 added the two numbers with DEFAULT 0.0, so a migrated token row
      // reads 0.0 where a row written since reads NULL.
      final migrated = TokenUsage.fromMap({
        'model_id': 'm',
        'billing_mode': 'token',
        'output_units': 0.0,
        'output_unit_price': 0.0,
        'output_unit': null,
        'output_spec': null,
      });

      expect(migrated.spec, isNull);
    });

    test('an output_unit that names no unit counts as pictures, as it always drew', () {
      final row = TokenUsage.fromMap({
        'model_id': 'm',
        'billing_mode': 'spec',
        'output_units': 2.0,
        'output_unit_price': 0.5,
        'output_unit': 'frame',
      });

      expect(row.spec!.unit, OutputUnit.image);
      expect(row.cost, 1.0);
    });

    test('a cell of the wrong type reads as absent, whatever the row bills by', () {
      // SQLite keeps 'abc' in a REAL column as text. A token row never prices
      // its spec or request columns, so text there must not cost it the page.
      final row = TokenUsage.fromMap({
        'id': 'x',
        'model_id': 'm',
        'model_pk': 'seven',
        'timestamp': 20260901,
        'billing_mode': 'token',
        'input_tokens': 1000000,
        'input_price': 2.0,
        'cache_price': 'abc',
        'output_price': 'abc',
        'request_count': 1.5,
        'request_price': 'abc',
        'output_units': 'abc',
        'output_unit_price': 'abc',
        'output_unit': 3,
        'output_spec': 8,
      });

      expect(row.cost, closeTo(2.0, 1e-9));
      expect(row.requestCount, 1);
      expect(row.modelDbId, isNull);
      expect(row.spec, isNull);
      expect(row.timestamp, DateTime.fromMillisecondsSinceEpoch(0));
    });

    test('survives the trip out and back', () {
      final row = TokenUsage(
        taskId: 'req_1',
        modelId: '[ch] m',
        modelDbId: 7,
        timestamp: at,
        inputTokens: 10,
        cacheTokens: 4,
        outputTokens: 6,
        inputPrice: 2.0,
        cachePrice: 0.5,
        outputPrice: 8.0,
        requestPrice: 0.02,
        billingMode: 'spec',
        spec: const UsageSpecBilling(
          unit: OutputUnit.second,
          units: 8,
          unitPrice: 0.3,
          snapshot: UsageSpecSnapshot(size: '1080p', seconds: 8, matched: false),
        ),
      );

      final back = TokenUsage.fromMap(row.toMap());

      expect(back.toMap(), row.toMap());
      expect(back.timestamp, at);
      expect(back.spec!.snapshot!.seconds, 8);
      expect(back.unmatched, isTrue);
    });

    test('a row of another mode writes its spec columns as NULL', () {
      final map = TokenUsage(modelId: 'm', timestamp: at).toMap();

      for (final column in ['output_units', 'output_unit_price', 'output_unit', 'output_spec']) {
        expect(map.containsKey(column), isTrue, reason: column);
        expect(map[column], isNull, reason: column);
      }
      expect(map.containsKey('id'), isFalse, reason: 'the insert must leave AUTOINCREMENT alone');
    });
  });

  group('UsageCheckpoint', () {
    test('keeps its per-group costs through the metadata column', () {
      final checkpoint = UsageCheckpoint(
        timestamp: at,
        totalInputTokens: 10,
        totalCacheTokens: 2,
        totalOutputTokens: 5,
        totalRequestCount: 3,
        totalCost: 1.25,
        groupCosts: const {42: 1.0, 7: 0.25},
      );

      final back = UsageCheckpoint.fromMap(checkpoint.toMap());

      expect(back.timestamp, at);
      expect(back.totalCacheTokens, 2);
      expect(back.groupCosts, {42: 1.0, 7: 0.25});
    });

    test('a cell of the wrong type reads as absent', () {
      final back = UsageCheckpoint.fromMap({
        'id': 'x',
        'timestamp': 20260901,
        'total_input_tokens': 'abc',
        'total_cache_tokens': 1.5,
        'total_output_tokens': 5,
        'total_request_count': null,
        'total_cost': 'abc',
        'metadata': 7,
      });

      expect(back.id, isNull);
      expect(back.timestamp, DateTime.fromMillisecondsSinceEpoch(0));
      expect(back.totalInputTokens, 0);
      expect(back.totalCacheTokens, 0);
      expect(back.totalOutputTokens, 5);
      expect(back.totalCost, 0.0);
      expect(back.groupCosts, isEmpty);
    });

    test('unreadable metadata is no breakdown, not an error', () {
      for (final raw in ['junk', '[]', 7, null]) {
        final back = UsageCheckpoint.fromMap(
            {'timestamp': at.toIso8601String(), 'metadata': raw});
        expect(back.groupCosts, isEmpty, reason: '$raw');
      }
    });
  });
}
