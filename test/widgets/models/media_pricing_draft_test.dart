import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/media_pricing.dart';
import 'package:joycai_image_ai_toolkits/models/pricing_group.dart';
import 'package:joycai_image_ai_toolkits/models/spec_rate.dart';
import 'package:joycai_image_ai_toolkits/widgets/models/fee_group_draft.dart';

void main() {
  test('media prices retain missing vs free and survive mode switching', () {
    final draft = FeeGroupDraft(
      PricingGroup(
        name: 'media',
        mediaPricing: const MediaPricing(
          imageInput: 2,
          imageCache: 0,
          imageOutput: 8,
          videoInputRates: [SpecRate(size: '1080p', price: 0.1)],
        ),
      ),
    );
    addTearDown(draft.dispose);
    expect(draft.imageTokenCacheCtrl.text, '0.0');
    draft.imageTokenCacheCtrl.clear();
    draft.setMode('spec');
    final saved = PricingGroup.fromMap(draft.toGroup().toMap());
    expect(saved.mediaPricing.imageCache, isNull);
    expect(saved.mediaPricing.imageInput, 2);
    expect(saved.mediaPricing.videoInputRates.single.price, 0.1);
    expect(draft.isDirty, isTrue);
    draft.imageTokenInputCtrl.text = '-1';
    expect(draft.canSave, isFalse);
  });
}
