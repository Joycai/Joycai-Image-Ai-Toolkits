import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/llm_model.dart';
import 'package:joycai_image_ai_toolkits/models/spec_rate.dart';
import 'package:joycai_image_ai_toolkits/models/token_usage.dart';
import 'package:joycai_image_ai_toolkits/screens/metrics/widgets/usage_stats.dart';

/// Pins down how a range of usage rows adds up: totals, the per-group
/// breakdown and the cache hit rate. What one row costs is `TokenUsage`'s own
/// business — see `token_usage_test.dart`.
void main() {
  final at = DateTime(2026, 9, 1, 12);

  TokenUsage tokenRow({
    int input = 0,
    int cache = 0,
    int output = 0,
    double inputPrice = 0.0,
    double? cachePrice,
    double outputPrice = 0.0,
    int? modelPk,
  }) =>
      TokenUsage(
        modelId: 'm',
        modelDbId: modelPk,
        timestamp: at,
        inputTokens: input,
        cacheTokens: cache,
        outputTokens: output,
        inputPrice: inputPrice,
        cachePrice: cachePrice,
        outputPrice: outputPrice,
      );

  LLMModel model(int id, int? feeGroupId) => LLMModel(
        id: id,
        modelId: 'm$id',
        modelName: 'Model $id',
        tag: 'chat',
        feeGroupId: feeGroupId,
      );

  group('spec-billed rows in calculateStats', () {
    TokenUsage specRow({
      required OutputUnit unit,
      required double units,
      required double price,
      bool matched = true,
      int? modelPk,
    }) =>
        TokenUsage(
          modelId: 'm',
          modelDbId: modelPk,
          timestamp: at,
          billingMode: 'spec',
          spec: UsageSpecBilling(
            unit: unit,
            units: units,
            unitPrice: price,
            snapshot: UsageSpecSnapshot(size: '1080p', matched: matched),
          ),
        );

    test('cost lands in the group\'s spec bucket with its unit count', () {
      final stats = calculateStats([
        specRow(unit: OutputUnit.second, units: 8, price: 0.30, modelPk: 1),
        specRow(unit: OutputUnit.second, units: 5, price: 0.30, modelPk: 1),
        specRow(unit: OutputUnit.image, units: 2, price: 0.03, modelPk: 1),
      ], [
        model(1, 42)
      ]);

      final usage = stats.groupUsage[42]!;
      expect(usage.specCost, closeTo(3.96, 1e-9));
      expect(usage.requestCost, 0.0);
      expect(usage.totalCost, closeTo(3.96, 1e-9));
      expect(usage.specUnits, {OutputUnit.second: 13.0, OutputUnit.image: 2.0});
      expect(usage.unmatchedCount, 0);
      expect(stats.groupCosts[42], closeTo(3.96, 1e-9));
      expect(stats.totalRequestCount, 3);
    });

    test('what reference images cost is its own part, and the group\'s total has it', () {
      final stats = calculateStats([
        TokenUsage(
          modelId: 'seedream',
          modelDbId: 1,
          timestamp: at,
          billingMode: 'spec',
          spec: const UsageSpecBilling(
            unit: OutputUnit.image,
            units: 1,
            unitPrice: 0.30,
            inputImages: 3,
            inputUnits: 2,
            inputUnitPrice: 0.02,
          ),
        ),
      ], [
        model(1, 42)
      ]);

      final usage = stats.groupUsage[42]!;
      expect(usage.specCost, closeTo(0.30, 1e-9), reason: 'output alone');
      expect(usage.specInputCost, closeTo(0.04, 1e-9));
      // The bar's segments must add up to the amount beside it.
      expect(usage.totalCost, closeTo(stats.groupCosts[42]!, 1e-9));
      expect(stats.totalCost, closeTo(0.34, 1e-9));
      expect((usage + usage).specInputCost, closeTo(0.08, 1e-9));
    });

    test('requests no rate row covered are counted, not hidden in a zero', () {
      final stats = calculateStats([
        specRow(unit: OutputUnit.image, units: 1, price: 0.0, matched: false, modelPk: 1),
        specRow(unit: OutputUnit.image, units: 1, price: 0.03, modelPk: 1),
      ], [
        model(1, 42)
      ]);

      expect(stats.groupUsage[42]!.unmatchedCount, 1);
    });

    test('a provider-reported row is its own part, and fills no rate-table gap (D2d)', () {
      final reported = TokenUsage(
        modelId: 'grok-imagine-image-2.0',
        modelDbId: 1,
        timestamp: at,
        billingMode: 'spec',
        spec: const UsageSpecBilling(
          unit: OutputUnit.image,
          units: 1,
          unitPrice: 0.0,
          snapshot: UsageSpecSnapshot(size: '1K', quality: 'low', matched: false),
          inputImages: 1,
          inputUnits: 1,
          inputUnitPrice: 0.01,
        ),
        reportedCost: 0.05,
      );
      final stats = calculateStats([
        reported,
        specRow(unit: OutputUnit.image, units: 1, price: 0.03, modelPk: 1),
      ], [
        model(1, 42)
      ]);

      final usage = stats.groupUsage[42]!;
      expect(usage.reportedCost, closeTo(0.05, 1e-9));
      // Nothing of the reported row leaks into the table-priced parts.
      expect(usage.specCost, closeTo(0.03, 1e-9));
      expect(usage.specInputCost, 0.0);
      expect(usage.unmatchedCount, 0);
      expect(usage.specUnits, {OutputUnit.image: 2.0});
      expect(usage.totalCost, closeTo(0.08, 1e-9));
      expect(usage.totalCost, closeTo(stats.groupCosts[42]!, 1e-9));
      expect((usage + usage).reportedCost, closeTo(0.10, 1e-9));
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
        TokenUsage(
          modelId: 'm',
          timestamp: at,
          billingMode: 'request',
          requestCount: 3,
          requestPrice: 0.02,
        ),
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
