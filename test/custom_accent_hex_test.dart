import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/custom_accent.dart';

/// `CustomAccent.parseHex`, which is what a stored `custom:` theme colour is
/// read back through.
void main() {
  test('reads the three spellings of a colour', () {
    expect(CustomAccent.parseHex('#1E88E5')?.toARGB32(), 0xFF1E88E5);
    expect(CustomAccent.parseHex('1e88e5')?.toARGB32(), 0xFF1E88E5);
    expect(CustomAccent.parseHex('  #abc  ')?.toARGB32(), 0xFFAABBCC);
  });

  test('rejects anything that is not six hex digits', () {
    // `int.tryParse` takes a leading sign, so a length check alone let
    // '-FFFFF' through as a colour.
    expect(CustomAccent.parseHex('-FFFFF'), isNull);
    expect(CustomAccent.parseHex('+FFFFF'), isNull);
    expect(CustomAccent.parseHex('#GGGGGG'), isNull);
    expect(CustomAccent.parseHex('12345'), isNull);
    expect(CustomAccent.parseHex(''), isNull);
  });

  test('a storage value round-trips, and a preset key is not one', () {
    const seed = Color(0xFF7E57C2);
    expect(CustomAccent.parseStorageValue(CustomAccent.storageValue(seed))?.toARGB32(),
        seed.toARGB32());
    expect(CustomAccent.parseStorageValue('blue'), isNull);
    expect(CustomAccent.parseStorageValue('custom:#nope'), isNull);
  });
}
