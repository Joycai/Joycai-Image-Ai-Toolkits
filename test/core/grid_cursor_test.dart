import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/grid_cursor.dart';

void main() {
  test('vertical navigation follows partial grouped rows, without wrapping', () {
    final cursor = GridCursor()
      ..layout([
        ['a', 'b', 'c'],
        ['d', 'e', 'f', 'g'],
      ], 2);
    cursor.point('b');
    expect(cursor.move(vertical: 1), 'c');
    expect(cursor.move(vertical: 1), 'd');
    expect(cursor.move(horizontal: -1), 'c');
    cursor.point('g');
    expect(cursor.move(vertical: 1), 'g');
    cursor.point('a');
    expect(cursor.move(horizontal: -1), 'a');
  });

  test('range expands and contracts; identity survives sorting and column changes', () {
    final cursor = GridCursor()
      ..layout([
        ['a', 'b', 'c', 'd'],
      ], 2);
    cursor.move(horizontal: 1, extend: true);
    cursor.move(horizontal: 1, extend: true);
    expect(cursor.range, ['a', 'b', 'c']);
    cursor.move(horizontal: -1, extend: true);
    expect(cursor.range, ['a', 'b']);
    cursor.layout([
      ['d', 'c', 'b', 'a'],
    ], 3);
    expect(cursor.active, 'b');
    expect(cursor.anchor, 'a');
    cursor.layout([
      ['d', 'c', 'a'],
    ], 1);
    expect(cursor.active, 'a');
    cursor.layout([], 1);
    expect(cursor.active, isNull);
    expect(cursor.move(vertical: 1), isNull);
    expect(cursor.range, isEmpty);
  });
}
