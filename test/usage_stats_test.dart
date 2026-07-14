import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/llm_model.dart';
import 'package:joycai_image_ai_toolkits/screens/metrics/widgets/usage_stats.dart';

/// Pins down how usage rows turn into money. Input, cache hits and output are
/// billed at three separate rates, and a fee group that leaves the cache rate
/// unset must fall back to the input rate rather than billing the cache free.
void main() {
  Map<String, dynamic> tokenRow({
    int input = 0,
    int cache = 0,
    int output = 0,
    double inputPrice = 0.0,
    double? cachePrice,
    double outputPrice = 0.0,
    int? modelPk,
  }) =>
      {
        'billing_mode': 'token',
        'input_tokens': input,
        'cache_tokens': cache,
        'output_tokens': output,
        'input_price': inputPrice,
        'cache_price': cachePrice,
        'output_price': outputPrice,
        'request_count': 1,
        'model_pk': modelPk,
      };

  LLMModel model(int id, int? feeGroupId) => LLMModel(
        id: id,
        modelId: 'm$id',
        modelName: 'Model $id',
        type: 'openai-api',
        tag: 'chat',
        feeGroupId: feeGroupId,
      );

  group('calculateRowCost', () {
    test('bills input, cache and output at their own rates', () {
      final cost = calculateRowCost(tokenRow(
        input: 1000000,
        cache: 1000000,
        output: 1000000,
        inputPrice: 2.0,
        cachePrice: 0.5,
        outputPrice: 10.0,
      ));

      expect(cost, closeTo(12.5, 1e-9));
    });

    test('falls back to the input rate when the cache rate is unset', () {
      // cache_price null is what an unconfigured fee group writes, and what
      // every row recorded before cache pricing existed carries.
      final cost = calculateRowCost(tokenRow(
        cache: 1000000,
        inputPrice: 2.0,
        cachePrice: null,
      ));

      expect(cost, closeTo(2.0, 1e-9));
    });

    test('honours an explicit free cache rate instead of inheriting input', () {
      final cost = calculateRowCost(tokenRow(
        cache: 1000000,
        inputPrice: 2.0,
        cachePrice: 0.0,
      ));

      expect(cost, 0.0);
    });

    test('request-billed rows ignore token prices entirely', () {
      final cost = calculateRowCost({
        'billing_mode': 'request',
        'input_tokens': 5000,
        'cache_tokens': 5000,
        'output_tokens': 5000,
        'input_price': 99.0,
        'request_count': 3,
        'request_price': 0.02,
      });

      expect(cost, closeTo(0.06, 1e-9));
    });

    test('legacy rows written before cache columns existed still price', () {
      // Rows read back from a pre-v30 database have no cache keys at all.
      final cost = calculateRowCost({
        'billing_mode': 'token',
        'input_tokens': 1000000,
        'output_tokens': 1000000,
        'input_price': 3.0,
        'output_price': 6.0,
        'request_count': 1,
      });

      expect(cost, closeTo(9.0, 1e-9));
    });
  });

  group('calculateStats', () {
    test('sums input, cache and output separately', () {
      final stats = calculateStats([
        tokenRow(input: 10, cache: 3, output: 7),
        tokenRow(input: 5, cache: 2, output: 1),
      ], []);

      expect(stats.totalInput, 15);
      expect(stats.totalCache, 5);
      expect(stats.totalOutput, 8);
      expect(stats.totalRequestCount, 2);
    });

    test('attributes cache cost to the model\'s fee group', () {
      final stats = calculateStats([
        tokenRow(cache: 1000000, inputPrice: 4.0, cachePrice: 1.0, modelPk: 1),
      ], [
        model(1, 42)
      ]);

      expect(stats.groupCosts[42], closeTo(1.0, 1e-9));
      expect(stats.totalCost, closeTo(1.0, 1e-9));
    });

    test('accumulates on top of a checkpoint base', () {
      final base = calculateStats([tokenRow(input: 100, cache: 20, output: 5)], []);
      final stats = calculateStats([tokenRow(input: 1, cache: 2, output: 3)], [], base: base);

      expect(stats.totalInput, 101);
      expect(stats.totalCache, 22);
      expect(stats.totalOutput, 8);
    });
  });

  group('cacheHitRate', () {
    test('is the cached share of every prompt token in range', () {
      // input and cache are stored disjoint, so the denominator is their sum —
      // dividing by input alone would let the rate exceed 100%.
      final stats = calculateStats([
        tokenRow(input: 750, cache: 250, output: 40),
      ], []);

      expect(stats.cacheHitRate, closeTo(0.25, 1e-9));
    });

    test('ignores output tokens', () {
      // Output is not a prompt token and can never be served from the cache.
      final stats = calculateStats([tokenRow(input: 50, cache: 50, output: 999999)], []);

      expect(stats.cacheHitRate, closeTo(0.5, 1e-9));
    });

    test('is null when the range holds no prompt tokens', () {
      // Request-billed image jobs never ask the cache for anything; reporting
      // 0% would read as a cache that always misses.
      final stats = calculateStats([
        {'billing_mode': 'request', 'request_count': 3, 'request_price': 0.02},
      ], []);

      expect(stats.cacheHitRate, isNull);
      expect(UsageStats.empty().cacheHitRate, isNull);
    });

    test('reaches 1.0 when every prompt token was cached', () {
      final stats = calculateStats([tokenRow(input: 0, cache: 400)], []);

      expect(stats.cacheHitRate, 1.0);
    });
  });
}
