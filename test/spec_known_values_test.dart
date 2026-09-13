import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/billing/spec_known_values.dart';

/// The rate editor's pick lists are the union of every family's parameter
/// table, normalised — so a value picked there always equals the value a
/// request carries, and a family gaining a tier shows up by itself.
void main() {
  final known = SpecKnownValues.collect();

  test('image sizes: K tiers first by size, then pixel sizes, all normalised', () {
    expect(known.imageSizes, containsAllInOrder(['1K', '2K', '4K', '1024x1024']));
    expect(known.imageSizes, isNot(contains('1k')));
    expect(known.imageSizes, isNot(contains('auto')));
    expect(known.imageSizes, isNot(contains('not_set')));
  });

  test('video resolutions carry the p suffix in lower case, in ascending order', () {
    expect(known.videoResolutions, containsAllInOrder(['480p', '720p', '768p', '1080p']));
    expect(known.videoResolutions, isNot(contains('768P')));
  });

  test('qualities read low → high, with the odd ones after', () {
    expect(known.qualities, containsAllInOrder(['low', 'medium', 'high', 'standard']));
    expect(known.qualities, isNot(contains('auto')));
  });

  test('seconds are integers in ascending order', () {
    expect(known.seconds, containsAllInOrder([4, 5, 8, 10]));
    expect(known.seconds, isSorted);
  });
}

const Matcher isSorted = _Sorted();

class _Sorted extends Matcher {
  const _Sorted();

  @override
  bool matches(Object? item, Map matchState) {
    if (item is! List<int>) return false;
    for (var i = 1; i < item.length; i++) {
      if (item[i - 1] > item[i]) return false;
    }
    return true;
  }

  @override
  Description describe(Description description) => description.add('sorted ascending');
}
