import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/pricing_group.dart';
import 'package:joycai_image_ai_toolkits/models/spec_rate.dart';
import 'package:joycai_image_ai_toolkits/widgets/models/fee_group_draft.dart';

/// The input-image side of the fee-group draft (`D2c · 22a–22d`): two
/// scalars that are blank for most groups, kept through mode and unit
/// switches like the rate table, and validated only while their row shows.
void main() {
  PricingGroup seedream({OutputUnit unit = OutputUnit.image}) => PricingGroup(
        id: 1,
        name: 'Seedream pro',
        billingMode: 'spec',
        outputUnit: unit,
        outputRates: const [SpecRate(price: 0.30)],
        inputUnitPrice: 0.02,
        inputFreeUnits: 1,
      );

  FeeGroupDraft draftOf(PricingGroup? group) {
    final draft = FeeGroupDraft(group);
    addTearDown(draft.dispose);
    return draft;
  }

  test('a group that charges nothing opens with both fields blank', () {
    final draft = draftOf(PricingGroup(id: 2, name: 'Nano', billingMode: 'spec'));
    expect(draft.inputImagePriceCtrl.text, isEmpty);
    expect(draft.inputFreeCtrl.text, isEmpty);
    expect(draft.toGroup().inputUnitPrice, 0.0);
    expect(draft.toGroup().inputFreeUnits, 0);
  });

  test('a stored rate opens filled and saves back unchanged', () {
    final draft = draftOf(seedream());
    expect(draft.inputImagePriceCtrl.text, '0.0200');
    expect(draft.inputFreeCtrl.text, '1');
    expect(draft.isDirty, isFalse);

    final saved = draft.toGroup();
    expect(saved.inputUnitPrice, 0.02);
    expect(saved.inputFreeUnits, 1);
  });

  test('typing in either field dirties the draft', () {
    final draft = draftOf(seedream());
    draft.inputFreeCtrl.text = '2';
    expect(draft.isDirty, isTrue);
  });

  test('a price that does not parse blocks the save', () {
    final draft = draftOf(seedream());
    draft.inputImagePriceCtrl.text = 'two cents';
    expect(draft.inputImagePriceInvalid, isTrue);
    expect(draft.canSave, isFalse);

    draft.inputImagePriceCtrl.text = '0,03';
    expect(draft.canSave, isTrue);
    expect(draft.toGroup().inputUnitPrice, 0.03);
  });

  test('a free count without a price is hinted at, not refused', () {
    final draft = draftOf(seedream());
    draft.inputImagePriceCtrl.text = '';
    expect(draft.inputFreeWithoutPrice, isTrue);
    expect(draft.canSave, isTrue);
    expect(draft.toGroup().inputFreeUnits, 1, reason: 'saved as typed');
  });

  test('behind another unit the row is hidden: kept, and never the reason a save fails', () {
    final draft = draftOf(seedream());
    draft.inputImagePriceCtrl.text = 'garbage';
    draft.setUnit(OutputUnit.second);

    expect(draft.showsInputImages, isFalse);
    expect(draft.canSave, isTrue);
    final saved = draft.toGroup();
    expect(saved.inputUnitPrice, 0.02, reason: 'falls back to what was stored');
    expect(saved.chargesInputImages, isFalse, reason: 'a per-second group bills no inputs');
  });

  test('the values survive a switch to another billing mode', () {
    final draft = draftOf(seedream());
    draft.setMode('token');
    final saved = draft.toGroup();
    expect(saved.inputUnitPrice, 0.02);
    expect(saved.inputFreeUnits, 1);
  });
}
