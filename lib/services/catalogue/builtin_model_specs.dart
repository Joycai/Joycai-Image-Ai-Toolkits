import '../../models/media_pricing.dart';
import '../../models/pricing_group.dart';
import '../../models/spec_rate.dart';
import '../billing/spec_billing.dart';

part 'builtin_model_specs_data.dart';

/// Official API pricing definition for a built-in model preset.
///
/// Mirrors [PricingGroup]'s three billing modes (`token`, `spec`, `request`)
/// so a preset can both price requests directly as a fallback when no user
/// fee group is assigned and seed a user-editable [PricingGroup].
class BuiltinPricingSpec {
  final String billingMode; // 'token' | 'spec' | 'request'
  final double inputPrice;
  final double? cacheInputPrice;
  final double outputPrice;
  final double requestPrice;
  final OutputUnit outputUnit;
  final List<SpecRate> outputRates;
  final double inputUnitPrice;
  final int inputFreeUnits;
  final MediaPricing mediaPricing;

  const BuiltinPricingSpec.token({
    required this.inputPrice,
    this.cacheInputPrice,
    required this.outputPrice,
    this.mediaPricing = const MediaPricing(),
  }) : billingMode = 'token',
       requestPrice = 0.0,
       outputUnit = OutputUnit.image,
       outputRates = const [],
       inputUnitPrice = 0.0,
       inputFreeUnits = 0;

  const BuiltinPricingSpec.spec({
    required this.outputUnit,
    required this.outputRates,
    this.inputUnitPrice = 0.0,
    this.inputFreeUnits = 0,
    this.mediaPricing = const MediaPricing(),
  }) : billingMode = specBillingMode,
       inputPrice = 0.0,
       cacheInputPrice = null,
       outputPrice = 0.0,
       requestPrice = 0.0;

  const BuiltinPricingSpec.request({
    required this.requestPrice,
    this.inputUnitPrice = 0.0,
    this.inputFreeUnits = 0,
    this.mediaPricing = const MediaPricing(),
  }) : billingMode = 'request',
       inputPrice = 0.0,
       cacheInputPrice = null,
       outputPrice = 0.0,
       outputUnit = OutputUnit.image,
       outputRates = const [];

  PricingGroup toPricingGroup({required String name}) => PricingGroup(
    name: name,
    billingMode: billingMode,
    inputPrice: inputPrice,
    cacheInputPrice: cacheInputPrice,
    outputPrice: outputPrice,
    requestPrice: requestPrice,
    outputUnit: outputUnit,
    outputRates: outputRates,
    inputUnitPrice: inputUnitPrice,
    inputFreeUnits: inputFreeUnits,
    mediaPricing: mediaPricing,
  );
}

/// Built-in parameter and official API pricing specification for a known model.
class BuiltinModelSpec {
  /// Stable preset identifier (unique across [BuiltinModelSpecs.all]).
  final String id;

  /// Provider / vendor display group (e.g. `OpenAI`, `Anthropic`, `Google`).
  final String provider;

  /// Human-readable model name shown in preset pickers.
  final String displayName;

  /// Canonical official API model ID.
  final String canonicalId;

  /// Additional official IDs, dated snapshots, or common relay aliases.
  final List<String> aliases;

  /// Model kind matching `LLMModel.tag`: `chat`, `multimodal`, `image`, `video`.
  final String tag;

  /// Official context window in tokens, or null if not applicable.
  final int? contextWindow;

  /// Official maximum output tokens, or null if not applicable.
  final int? maxOutputTokens;

  /// Whether the model supports thinking / reasoning controls.
  final bool supportsThinking;

  /// Recommended default `ReasoningEffort` name (`low`, `medium`, `high`,
  /// `max`, `off`), or null to leave at provider default.
  final String? defaultReasoningEffort;

  /// Short technical summary of the model's thinking parameter support.
  final String? thinkingSummary;

  /// Optional compatible `GenerationProfiles` ID for image/video models.
  final String? generationProfile;

  /// Official API pricing for this model.
  final BuiltinPricingSpec pricing;

  const BuiltinModelSpec({
    required this.id,
    required this.provider,
    required this.displayName,
    required this.canonicalId,
    this.aliases = const [],
    required this.tag,
    this.contextWindow,
    this.maxOutputTokens,
    this.supportsThinking = false,
    this.defaultReasoningEffort,
    this.thinkingSummary,
    this.generationProfile,
    required this.pricing,
  });

  /// All raw identifiers this spec matches against.
  Iterable<String> get allNames sync* {
    yield canonicalId;
    yield displayName;
    yield* aliases;
  }
}

/// Result of fuzzy-matching a model ID against [BuiltinModelSpecs.all].
class BuiltinModelMatch {
  final BuiltinModelSpec spec;
  final double score;
  final bool isExact;

  const BuiltinModelMatch({required this.spec, required this.score, required this.isExact});
}

/// Built-in catalog of common models, their parameters, and official API
/// pricing, with fuzzy matching and manual search.
class BuiltinModelSpecs {
  const BuiltinModelSpecs._();

  /// Minimum fuzzy-match score accepted by [match].
  static const double matchThreshold = 0.65;

  /// All built-in model presets, ordered by provider family.
  static const List<BuiltinModelSpec> all = _builtinModelSpecsData;

  /// Looks up a preset by its stable [id].
  static BuiltinModelSpec? byId(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final spec in all) {
      if (spec.id == id) return spec;
    }
    return null;
  }

  /// Fuzzy-matches a raw [modelId] (including provider prefixes, date
  /// snapshots, separator variations, and swapped token order) to the best
  /// built-in spec, or returns null if no preset meets [matchThreshold].
  static BuiltinModelMatch? match(String modelId) {
    final raw = modelId.trim();
    if (raw.isEmpty) return null;

    final cleaned = _stripNamespaceAndTag(raw);
    final stripped = _stripDateAndVariantSuffix(cleaned);
    final queryNorm = _normalizeCompact(cleaned);
    final queryStrippedNorm = _normalizeCompact(stripped);
    final queryTokens = _tokenize(stripped);
    if (queryNorm.isEmpty) return null;

    BuiltinModelSpec? bestSpec;
    double bestScore = 0.0;
    bool bestExact = false;

    for (final spec in all) {
      final result = _scoreSpec(
        spec,
        queryNorm: queryNorm,
        queryStrippedNorm: queryStrippedNorm,
        queryTokens: queryTokens,
      );
      if (result.score > bestScore) {
        bestScore = result.score;
        bestSpec = spec;
        bestExact = result.isExact;
      }
    }

    if (bestSpec == null || bestScore < matchThreshold) return null;
    return BuiltinModelMatch(spec: bestSpec, score: bestScore, isExact: bestExact);
  }

  /// Searches [all] for the manual preset picker. Empty query returns [all].
  static List<BuiltinModelSpec> search(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return all;

    final lower = trimmed.toLowerCase();
    final tokens = _tokenize(trimmed);
    final compact = _normalizeCompact(trimmed);

    final scored = <(BuiltinModelSpec, double)>[];
    for (final spec in all) {
      var score = 0.0;
      final haystacks = [
        spec.displayName,
        spec.canonicalId,
        spec.provider,
        spec.tag,
        ...spec.aliases,
      ];
      for (final h in haystacks) {
        final hl = h.toLowerCase();
        if (hl == lower) {
          score = score < 1.0 ? 1.0 : score;
        } else if (hl.contains(lower)) {
          score = score < 0.85 ? 0.85 : score;
        } else if (compact.isNotEmpty && _normalizeCompact(h).contains(compact)) {
          score = score < 0.80 ? 0.80 : score;
        }
      }
      if (tokens.isNotEmpty) {
        final specTokens = {
          ..._tokenize(spec.displayName),
          ..._tokenize(spec.canonicalId),
          ..._tokenize(spec.provider),
          for (final a in spec.aliases) ..._tokenize(a),
        };
        final matchedTokens = tokens
            .where((t) => specTokens.any((st) => st == t || st.startsWith(t) || st.contains(t)))
            .length;
        if (matchedTokens == tokens.length) {
          final ratio = 0.75 + 0.15 * (matchedTokens / (specTokens.length + 1));
          if (ratio > score) score = ratio;
        } else if (matchedTokens > 0) {
          final ratio = 0.4 * (matchedTokens / tokens.length);
          if (ratio > score) score = ratio;
        }
      }
      if (score > 0.0) {
        scored.add((spec, score));
      }
    }

    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return [for (final item in scored) item.$1];
  }

  static ({double score, bool isExact}) _scoreSpec(
    BuiltinModelSpec spec, {
    required String queryNorm,
    required String queryStrippedNorm,
    required List<String> queryTokens,
  }) {
    var best = 0.0;
    var exact = false;

    for (final candidate in spec.allNames) {
      final candStripped = _stripDateAndVariantSuffix(candidate);
      final candNorm = _normalizeCompact(candidate);
      final candStrippedNorm = _normalizeCompact(candStripped);

      if (queryNorm == candNorm) {
        return (score: 1.0, isExact: true);
      }
      if (queryStrippedNorm.isNotEmpty && queryStrippedNorm == candStrippedNorm) {
        if (0.96 > best) {
          best = 0.96;
          exact = true;
        }
        continue;
      }

      final candTokens = _tokenize(candStripped);
      if (queryTokens.isEmpty || candTokens.isEmpty) continue;

      // Reject conflicting version numbers (e.g. gpt-6.1 must not match gpt-6.2,
      // claude-opus-4.6 must not match claude-opus-4.7).
      if (!_versionsCompatible(queryTokens, candTokens)) continue;

      final qSet = queryTokens.toSet();
      final cSet = candTokens.toSet();

      // Exact token-set match handles word-order swaps like
      // `wan-image-2.7` <-> `wan2.7-image` and `claude-4.6-opus` <-> `claude-opus-4-6`.
      if (qSet.length == cSet.length && qSet.containsAll(cSet)) {
        if (0.93 > best) {
          best = 0.93;
          exact = false;
        }
        continue;
      }

      // Compute token Jaccard + coverage similarity.
      final intersection = qSet.intersection(cSet).length;
      if (intersection == 0) continue;

      final union = qSet.union(cSet).length;
      final jaccard = intersection / union;
      final candCoverage = intersection / cSet.length;
      final queryCoverage = intersection / qSet.length;

      // Require at least one non-version brand/family token to match.
      final matchedNonVersion = qSet.intersection(cSet).any((t) => !_isVersionToken(t));
      if (!matchedNonVersion) continue;

      var score = (jaccard * 0.55) + (candCoverage * 0.25) + (queryCoverage * 0.20);

      // Small boost when one compact string starts with or contains the other.
      if (queryStrippedNorm.contains(candStrippedNorm) ||
          candStrippedNorm.contains(queryStrippedNorm)) {
        score = (score + 0.08).clamp(0.0, 0.90);
      }

      if (score > best) {
        best = score;
        exact = false;
      }
    }

    return (score: best, isExact: exact);
  }

  /// Strips provider namespaces (`openai/`, `models/`, `Pro/deepseek-ai/`) and
  /// relay suffix tags (`:free`, `:thinking`, `[1m]`).
  static String _stripNamespaceAndTag(String raw) {
    var s = raw.trim().toLowerCase();
    if (s.contains('/')) {
      s = s.split('/').last;
    }
    s = s.replaceAll(RegExp(r'\[[^\]]*\]$'), '');
    if (s.contains(':')) {
      s = s.split(':').first;
    }
    return s.trim();
  }

  /// Strips trailing date snapshots (`-2026-04-21`, `-20260908`, `-260628`)
  /// and common release-channel suffixes (`-preview`, `-latest`, `-exp`,
  /// `-generate-001`).
  static String _stripDateAndVariantSuffix(String raw) {
    var s = raw.trim().toLowerCase();
    s = s.replaceAll(RegExp(r'[-_](?:20\d{2}[-_]?\d{2}[-_]?\d{2}|\d{6})(?=$|[-_])'), '');
    s = s.replaceAll(
      RegExp(r'[-_](?:preview|latest|exp|experimental|generate[-_]?\d{3}|00\d)(?=$|[-_])'),
      '',
    );
    return s.trim();
  }

  /// Normalizes a name for exact-ish comparison by collapsing separators and
  /// unifying version dashes like `4-6` into `4.6` and `5-0` into `5.0`.
  static String _normalizeCompact(String raw) {
    final s = _normalizeVersionSeparators(raw.toLowerCase());
    return s.replaceAll(RegExp(r'[^a-z0-9.]'), '');
  }

  /// Splits a model ID into semantic tokens, separating letters from version
  /// numbers (`qwen3.8-max` -> `['qwen', '3.8', 'max']`,
  /// `Seedream5.0pro` -> `['seedream', '5.0', 'pro']`,
  /// `claude-opus-4-6` -> `['claude', 'opus', '4.6']`).
  static List<String> _tokenize(String raw) {
    var s = _normalizeVersionSeparators(raw.toLowerCase());
    // Normalize `v4.1` -> `4.1` so `deepseek-v4.1-flash` matches `deepseek-4.1-flash`.
    s = s.replaceAllMapped(
      RegExp(r'(^|[^a-z])v(\d+(?:\.\d+)?)'),
      (m) => '${m.group(1)}${m.group(2)}',
    );
    // Insert space between letters and digits (`qwen4` -> `qwen 4`, `5.0pro` -> `5.0 pro`).
    s = s.replaceAllMapped(RegExp(r'([a-z])(\d)'), (m) => '${m.group(1)} ${m.group(2)}');
    s = s.replaceAllMapped(RegExp(r'(\d)([a-z])'), (m) => '${m.group(1)} ${m.group(2)}');
    final parts = s.split(RegExp(r'[^a-z0-9.]+')).where((p) => p.isNotEmpty).toList();
    // Normalize trailing `.0` on version numbers (`4.0` -> `4`, `5.0` -> `5`, `3.0` -> `3`)
    // so `qwen-image-3` matches `qwen-image-3.0` and `claude-opus-5` matches `claude-opus-5.0`.
    return [
      for (final p in parts)
        if (_isVersionToken(p)) _canonicalVersion(p) else p,
    ];
  }

  /// Converts dash/underscore between single/double-digit version parts into a
  /// dot (`4-6` -> `4.6`, `5-0` -> `5.0`, `2-5` -> `2.5`).
  static String _normalizeVersionSeparators(String s) {
    return s.replaceAllMapped(
      RegExp(r'(?<!\d)(\d{1,2})[-_](\d{1,2})(?!\d)'),
      (m) => '${m.group(1)}.${m.group(2)}',
    );
  }

  static bool _isVersionToken(String token) => RegExp(r'^\d+(?:\.\d+)?$').hasMatch(token);

  static String _canonicalVersion(String v) {
    if (v.endsWith('.0')) return v.substring(0, v.length - 2);
    return v;
  }

  /// If both query and candidate contain version tokens, they must agree on
  /// all version tokens so `gpt-6.1` never fuzzy-matches `gpt-6.2`.
  static bool _versionsCompatible(List<String> queryTokens, List<String> candTokens) {
    final qVersions = queryTokens.where(_isVersionToken).toSet();
    final cVersions = candTokens.where(_isVersionToken).toSet();
    if (qVersions.isEmpty || cVersions.isEmpty) return true;
    return qVersions.length == cVersions.length && qVersions.containsAll(cVersions);
  }
}
