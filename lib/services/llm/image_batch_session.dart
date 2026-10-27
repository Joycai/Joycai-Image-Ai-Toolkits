import '../../models/media_pricing.dart';
import '../../models/pricing_group.dart';
import '../../models/token_usage.dart';
import '../billing/media_accounting.dart';
import '../db/database_service.dart';
import '../db/repositories/usage_repository.dart';
import 'llm_types.dart';
import 'protocols/openai_image_batch_protocol.dart';
import 'protocols/protocol.dart';
import 'protocols/usage_normalization.dart';

/// Already routed by the dispatcher. Carries live credentials only in memory.
class ImageBatchSession {
  ImageBatchSession(this._target);
  final LLMTarget _target;
  final _protocol = OpenAIImageBatchProtocol();

  Map<String, dynamic> get snapshot => {
    'channelId': _target.config.channelId,
    'endpoint': _target.config.endpoint,
    'channelType': _target.config.channelType,
    'modelId': _target.config.modelId,
    'protocol': 'openai-image-batch',
    // Official Batch USD / million tokens, verified 2026-10-26. These are
    // explicit rates, never a multiplier applied to a user's custom fee group.
    'pricingSource': 'OpenAI Batch 2026-10-26 USD',
    'textInputRate': 2.5, 'imageInputRate': 4.0,
    'textCacheRate': 0.625, 'imageCacheRate': 1.0, 'outputRate': 15.0,
  };

  Future<String> upload(String customId, Map<String, dynamic> body) =>
      _protocol.upload(_target, customId, body);
  Future<Map<String, dynamic>> create(String file, String intent, bool edit) =>
      _protocol.create(_target, file, intent, edit);
  Future<Map<String, dynamic>> inspect(String id) => _protocol.inspect(_target, id);
  Future<Map<String, dynamic>> cancel(String id) => _protocol.cancel(_target, id);
  Future<Map<String, dynamic>?> reconcile(String intent, String file) =>
      _protocol.reconcile(_target, intent, file);
  Future<Map<String, dynamic>?> resultLine(String file, String customId) =>
      _protocol.resultLine(_target, file, customId);
  Future<LLMResponse> decodeResult(Map<String, dynamic> body, int inputs) =>
      _protocol.decodeResult(_target, body, inputs);

  /// Uses the same disjoint components as immediate requests. Legacy chart
  /// counters are projections; missing detail remains explicitly incomplete.
  static Future<void> settle(
    DatabaseService database,
    String taskId,
    int? modelPk,
    Map<String, dynamic> state,
    Map<String, dynamic> body,
  ) async {
    final rawUsage = body['usage'];
    final usage = rawUsage is Map ? Map<String, dynamic>.from(rawUsage) : <String, dynamic>{};
    double rate(String key) => (state[key] as num).toDouble();
    final accounting = MediaAccounting.price(
      PricingGroup(
        name: state['modelId'] as String,
        inputPrice: rate('textInputRate'),
        cacheInputPrice: rate('textCacheRate'),
        outputPrice: rate('outputRate'),
        mediaPricing: MediaPricing(
          imageInput: rate('imageInputRate'),
          imageCache: rate('imageCacheRate'),
          imageOutput: rate('outputRate'),
        ),
      ),
      normalizeTokenUsage(Map<String, dynamic>.from(usage), imageOutput: true),
      priceSource: state['pricingSource'] as String? ?? 'OpenAI Batch snapshot',
    );
    final projection = accounting.tokenProjection;
    final repository = UsageRepository(db: database);
    await repository.recordTokenUsage(
      TokenUsage(
        accounting: accounting,
        taskId: 'batch:$taskId',
        modelId: state['modelId'] as String,
        modelDbId: modelPk,
        timestamp: DateTime.parse(state['submittedAt'] as String),
        inputTokens: projection['input_tokens'] as int,
        cacheTokens: projection['cache_tokens'] as int,
        outputTokens: projection['output_tokens'] as int,
        inputPrice: projection['input_price'] as double,
        cachePrice: projection['cache_price'] as double,
        outputPrice: projection['output_price'] as double,
        billingMode: 'token',
      ),
    );
    final saved = await repository.usageFor('batch:$taskId');
    if (saved == null || saved.costIncomplete) {
      throw LLMApiException('Batch usage incomplete; settlement pending.');
    }
  }
}
