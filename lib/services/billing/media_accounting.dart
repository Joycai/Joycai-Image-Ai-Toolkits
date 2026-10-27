import '../../models/pricing_group.dart';
import '../../models/spec_rate.dart';
import '../../models/usage_accounting.dart';
import '../llm/output_spec.dart';
import 'spec_billing.dart';

/// Shared by immediate images, Batch and asynchronous video settlement.
/// Quantities are normalized by protocol adapters; totals are validation only.
class MediaAccounting {
  static UsageAccounting price(
    PricingGroup pricing,
    Map<String, dynamic> q, {
    Map<String, dynamic>? options,
    bool video = false,
    bool pending = false,
    int revision = 0,
    bool pricingKnown = true,
    String priceSource = 'user',
  }) {
    final spec = OutputSpec.from(options, metadata: q);
    final parts = <UsageComponent>[];
    var valid = q['invalid'] != true && pricingKnown;
    double? number(String key) {
      final raw = q[key];
      if (raw is num && raw.isFinite && raw >= 0) return raw.toDouble();
      if (raw != null) valid = false;
      return null;
    }

    void add(
      String meter,
      String category,
      double? quantity,
      double? price, {
      double basis = 1,
      String source = 'reported',
    }) {
      if (price != null && (!price.isFinite || price < 0)) {
        valid = false;
        price = null;
      }
      parts.add(
        UsageComponent(
          meter: meter,
          category: category,
          quantity: quantity,
          price: pricingKnown ? price : null,
          basis: basis,
          source: source,
        ),
      );
    }

    void token(String name, double? total, double? cached, double? price, double? cachePrice) {
      if (total != null && cached != null && cached > total) {
        valid = false;
        total = null;
        cached = null;
      }
      // Missing cache detail is an explicit non-cache estimate, not an invented hit count.
      add(
        '${name}_tokens',
        'input',
        total == null ? null : total - (cached ?? 0),
        price,
        basis: 1e6,
        source: cached == null ? 'estimated' : 'reported',
      );
      if (cached != null) add('${name}_cached_tokens', 'cache', cached, cachePrice, basis: 1e6);
    }

    if (pricing.billingMode == 'token') {
      final split = q['multimodal'] == true;
      if (split) {
        final text = number('text_input');
        final image = number('image_input');
        final total = number('input');
        final cache = number('cache');
        var textCache = number('text_cache');
        var imageCache = number('image_cache');
        if (total != null && text != null && image != null && total != text + image) valid = false;
        if (cache != null &&
            textCache != null &&
            imageCache != null &&
            textCache + imageCache != cache) {
          valid = false;
        }
        if (cache == 0) {
          if ((textCache ?? 0) > 0 || (imageCache ?? 0) > 0) valid = false;
          textCache = 0;
          imageCache = 0;
        }
        if (cache != null &&
            cache > 0 &&
            (textCache == null || imageCache == null || textCache + imageCache != cache)) {
          valid = false;
        }
        token('text_input', text, textCache, pricing.inputPrice, pricing.effectiveCacheInputPrice);
        token(
          'image_input',
          image,
          imageCache,
          pricing.mediaPricing.imageInput,
          pricing.mediaPricing.imageCache,
        );
      } else {
        token(
          'input',
          number('input'),
          number('cache'),
          pricing.inputPrice,
          pricing.effectiveCacheInputPrice,
        );
      }
      if (q['output_split'] == true) {
        final imageOutput = number('image_output');
        final textOutput = number('text_output');
        final totalOutput = number('output');
        if (imageOutput != null &&
            textOutput != null &&
            totalOutput != null &&
            imageOutput + textOutput != totalOutput) {
          valid = false;
        }
        add(
          'image_output_tokens',
          'output',
          imageOutput,
          pricing.mediaPricing.imageOutput,
          basis: 1e6,
        );
        add('text_output_tokens', 'output', textOutput, pricing.outputPrice, basis: 1e6);
      } else {
        add('output_tokens', 'output', number('output'), pricing.outputPrice, basis: 1e6);
      }
    } else if (pricing.billingMode == 'spec' || pricing.billingMode == 'request') {
      if (pricing.billingMode == 'request') {
        add('requests', 'request', 1, pricing.requestPrice, source: 'estimated');
      } else {
        final match = matchSpecRate(pricing.outputRates, spec);
        final quantity = switch (pricing.outputUnit) {
          OutputUnit.image => number('images'),
          OutputUnit.second => spec.seconds?.toDouble(),
          OutputUnit.clip => 1.0,
        };
        add(
          'output_${pricing.outputUnit.name}',
          'spec',
          quantity,
          match.rate?.price,
          source: pricing.outputUnit == OutputUnit.image
              ? (q['images_source'] as String? ?? 'reported')
              : q.containsKey('output_seconds')
              ? 'reported'
              : 'estimated',
        );
      }
      final images = number('input_images');
      add(
        'input_images',
        'specInput',
        images == null ? null : (images - pricing.inputFreeUnits).clamp(0, double.infinity),
        pricing.inputUnitPrice,
        source: 'estimated',
      );
      if (video) {
        final seconds = number('input_seconds');
        final match = matchSpecRate(pricing.mediaPricing.videoInputRates, spec);
        add(
          'video_input_seconds',
          'specInput',
          seconds,
          seconds == 0 ? 0 : match.rate?.price,
          source: q['input_seconds_source'] as String? ?? 'unknown',
        );
      }
    } else {
      valid = false;
    }
    return UsageAccounting(
      components: parts,
      pricing: {
        ...pricing.toMap(includeId: false),
        'pricingKnown': pricingKnown,
        'priceSource': priceSource,
        'options': {'imageSize': spec.size, 'quality': spec.quality, 'seconds': spec.seconds},
        'video': video,
      },
      quantities: Map.of(q),
      status: pending ? 'pending' : 'estimated',
      valid: valid,
      revision: revision,
    );
  }

  static UsageAccounting settle(UsageAccounting original, Map<String, dynamic> evidence) {
    final q = {...original.quantities, ...evidence};
    final changed =
        original.status == 'pending' ||
        evidence.entries.any(
          (e) => e.key != 'settlement_version' && original.quantities[e.key] != e.value,
        );
    return price(
      PricingGroup.fromMap(original.pricing),
      q,
      options: Map<String, dynamic>.from(original.pricing['options'] as Map? ?? {}),
      video: original.pricing['video'] == true,
      revision: original.revision + (changed ? 1 : 0),
      pricingKnown: original.pricing['pricingKnown'] != false,
      priceSource: original.pricing['priceSource'] as String? ?? 'user',
    );
  }
}
