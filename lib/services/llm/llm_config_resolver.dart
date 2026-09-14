import 'package:flutter/foundation.dart';

import '../../models/llm_model.dart';
import '../../models/pricing_group.dart';
import '../../models/spec_rate.dart';
import '../database_service.dart';
import 'llm_types.dart';
import 'vendors/vendors.dart';

/// Why a model identifier could not be turned into a request configuration.
enum LLMConfigErrorKind {
  /// No model row for the identifier (deleted, or a stale reference).
  modelNotFound,

  /// The model row has no channel.
  noChannel,

  /// The model's channel row no longer exists.
  channelNotFound,

  /// The channel has no API key, and its vendor does not work without one.
  missingApiKey,
}

/// A request that cannot be sent as configured. Thrown before any network
/// traffic, so it is never retried and never billed.
///
/// Typed rather than a bare `Exception` so callers can tell a configuration
/// problem from a provider failure without matching prose, and so the
/// message can name what to fix.
class LLMConfigException implements Exception {
  final LLMConfigErrorKind kind;
  final String message;

  const LLMConfigException(this.kind, this.message);

  @override
  String toString() => message;
}

class LLMConfigResolver {
  final DatabaseService _db = DatabaseService();

  /// Refuses a channel with no API key unless its vendor declares that it
  /// works keyless ([VendorProfile.keyOptional] — the local runtimes).
  ///
  /// Without this the request went out with no auth header at all
  /// ([VendorProfile.headers] drops it for an empty key) and came back as a
  /// provider 401 that names neither the channel nor the missing key
  /// (standard 11 §D39). Whitespace counts as empty: a pasted blank is the
  /// usual way a key goes missing.
  @visibleForTesting
  static void requireApiKey({
    required String channelType,
    required String apiKey,
    required String channelName,
    required String modelId,
  }) {
    if (apiKey.trim().isNotEmpty) return;
    if (Vendors.byId(channelType).keyOptional) return;
    throw LLMConfigException(
      LLMConfigErrorKind.missingApiKey,
      'Channel "$channelName" has no API key, so "$modelId" cannot be '
      'requested. Add the key in the channel settings.',
    );
  }

  Future<LLMModelConfig> resolveConfig(dynamic modelIdentifier, {Function(String, {String level})? logger}) async {
    final models = await _db.getModels();

    LLMModel modelData;

    if (modelIdentifier is int) {
      modelData = models.firstWhere(
        (m) => m.id == modelIdentifier,
        orElse: () => throw LLMConfigException(
            LLMConfigErrorKind.modelNotFound,
            'Model with PK $modelIdentifier not found (it may have been '
            'deleted).'),
      );
    } else {
      // Fallback for legacy string IDs (takes the first match)
      modelData = models.firstWhere(
        (m) => m.modelId == modelIdentifier,
        orElse: () => throw LLMConfigException(
            LLMConfigErrorKind.modelNotFound,
            'Model $modelIdentifier not found in database.'),
      );
    }

    // Fetch Pricing Group
    final pricingGroupId = modelData.feeGroupId;
    double inputFee = 0.0;
    double? cacheInputFee;
    double outputFee = 0.0;
    String billingMode = 'token';
    double requestFee = 0.0;
    OutputUnit outputUnit = OutputUnit.image;
    List<SpecRate> outputRates = const [];

    if (pricingGroupId != null) {
      final pricingGroups = await _db.getPricingGroups();
      final group = pricingGroups.cast<PricingGroup?>().firstWhere((g) => g?.id == pricingGroupId, orElse: () => null);
      if (group != null) {
        inputFee = group.inputPrice;
        cacheInputFee = group.cacheInputPrice;
        outputFee = group.outputPrice;
        billingMode = group.billingMode;
        requestFee = group.requestPrice;
        outputUnit = group.outputUnit;
        outputRates = group.outputRates;
      }
    }

    final modelId = modelData.modelId;
    final channelId = modelData.channelId;

    if (channelId == null) {
      throw LLMConfigException(LLMConfigErrorKind.noChannel,
          'Model $modelId has no associated channel.');
    }

    final channelData = await _db.getChannel(channelId);
    if (channelData == null) {
      throw LLMConfigException(LLMConfigErrorKind.channelNotFound,
          'Channel for model $modelId not found (it may have been deleted).');
    }

    final endpoint = channelData.endpoint;
    final apiKey = channelData.apiKey;
    final channelType = channelData.type;

    requireApiKey(
      channelType: channelType,
      apiKey: apiKey,
      channelName: channelData.displayName,
      modelId: modelId,
    );

    // Global Proxy Settings
    final proxyEnabled = (await _db.getSetting('proxy_enabled')) == 'true';
    final proxyUrl = await _db.getSetting('proxy_url');
    final proxyUsername = await _db.getSetting('proxy_username');
    final proxyPassword = await _db.getSetting('proxy_password');

    return LLMModelConfig(
      id: modelData.id,
      modelId: modelId,
      channelType: channelType,
      endpoint: endpoint,
      apiKey: apiKey,
      enableThinking: modelData.enableThinking,
      reasoningEffort: ReasoningEffort.tryParse(modelData.reasoningEffort),
      enableWebSearch: modelData.enableWebSearch,
      wireProtocol: modelData.wireProtocol,
      tag: modelData.tag,
      inputFee: inputFee,
      cacheInputFee: cacheInputFee,
      outputFee: outputFee,
      billingMode: billingMode,
      requestFee: requestFee,
      outputUnit: outputUnit,
      outputRates: outputRates,
      proxyEnabled: proxyEnabled,
      proxyUrl: proxyUrl,
      proxyUsername: proxyUsername,
      proxyPassword: proxyPassword,
    );
  }
}
