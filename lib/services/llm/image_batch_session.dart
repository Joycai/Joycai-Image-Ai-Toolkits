import '../../models/token_usage.dart';
import '../db/database_service.dart';
import '../db/repositories/usage_repository.dart';
import 'llm_types.dart';
import 'protocols/openai_image_batch_protocol.dart';
import 'protocols/protocol.dart';

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

  /// TokenUsage owns arithmetic. Mixed text/image input becomes a weighted
  /// price snapshot; missing modality detail must not look like a free image.
  static Future<void> settle(
    DatabaseService database,
    String taskId,
    int? modelPk,
    Map<String, dynamic> state,
    Map<String, dynamic> body,
  ) async {
    final usage = body['usage'];
    if (usage is! Map) {
      throw LLMApiException('Batch usage is unavailable; result saved, settlement pending.');
    }
    final details = usage['input_tokens_details'];
    if (details is! Map ||
        details['text_tokens'] is! num ||
        details['image_tokens'] is! num ||
        usage['output_tokens'] is! num) {
      throw LLMApiException('Batch token details are incomplete; settlement pending.');
    }
    if ((usage['output_tokens'] as num) < 0 ||
        usage['input_tokens'] is! num ||
        usage['input_tokens'] !=
            (details['text_tokens'] as num) + (details['image_tokens'] as num)) {
      throw LLMApiException('Invalid Batch token totals; settlement pending.');
    }
    final text = (details['text_tokens'] as num).toInt();
    final image = (details['image_tokens'] as num).toInt();
    final cached = (details['cached_tokens'] as num?)?.toInt() ?? 0;
    // Images usage currently has no guaranteed cached modality split. Keep
    // nonzero unknown splits pending rather than silently mispricing them.
    final cachedDetails = details['cached_tokens_details'];
    if (cached > 0 && cachedDetails is! Map) {
      throw LLMApiException('Batch cached token breakdown unavailable; settlement pending.');
    }
    final cachedText = cachedDetails is Map
        ? (cachedDetails['text_tokens'] as num?)?.toInt() ?? 0
        : 0;
    final cachedImage = cachedDetails is Map
        ? (cachedDetails['image_tokens'] as num?)?.toInt() ?? 0
        : 0;
    if (cachedText + cachedImage != cached ||
        cachedText > text ||
        cachedImage > image ||
        text < 0 ||
        image < 0 ||
        cached < 0) {
      throw LLMApiException('Invalid Batch token accounting.');
    }
    final input = text + image - cached;
    double rate(String key) => (state[key] as num).toDouble();
    await UsageRepository(db: database).recordTokenUsage(
      TokenUsage(
        taskId: 'batch:$taskId',
        modelId: state['modelId'] as String,
        modelDbId: modelPk,
        timestamp: DateTime.parse(state['submittedAt'] as String),
        inputTokens: input,
        cacheTokens: cached,
        outputTokens: (usage['output_tokens'] as num).toInt(),
        inputPrice: input == 0
            ? 0
            : ((text - cachedText) * rate('textInputRate') +
                      (image - cachedImage) * rate('imageInputRate')) /
                  input,
        cachePrice: cached == 0
            ? 0
            : (cachedText * rate('textCacheRate') + cachedImage * rate('imageCacheRate')) / cached,
        outputPrice: rate('outputRate'),
        billingMode: 'token',
      ),
    );
  }
}
