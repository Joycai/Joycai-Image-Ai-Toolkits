import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/app_image.dart';
import 'package:joycai_image_ai_toolkits/state/gallery_state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Covers the selection ordinal the gallery grid labels its thumbnails with.
///
/// The number is not decoration: it is the order the pictures are handed to
/// the model, and the reference strip in the config panel is ordered the same
/// way. A prompt that says "match the second image's pose" is wrong the
/// moment the badge and the payload disagree, and nothing on screen would
/// show it.
void main() {
  // GalleryState reloads its settings from disk while constructing, so it
  // needs a database and a path_provider even though the selection index
  // itself is pure in-memory bookkeeping.
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall methodCall) async => Directory.systemTemp.path,
  );

  AppImage img(String name) => AppImage(path: '/tmp/$name.png', name: '$name.png');

  late GalleryState state;

  setUp(() => state = GalleryState());

  test('numbers run from 1, in selection order', () {
    // 1-based because it is shown to a person; the off-by-one would be
    // invisible in code review and obvious in a screenshot.
    state.selectedImages = [img('a'), img('b'), img('c')];

    expect(state.selectionNumberOf('/tmp/a.png'), 1);
    expect(state.selectionNumberOf('/tmp/b.png'), 2);
    expect(state.selectionNumberOf('/tmp/c.png'), 3);
  });

  test('an unselected picture reports 0, not a valid position', () {
    // The grid treats >0 as "selected", so a miss must not land on 1.
    state.selectedImages = [img('a')];

    expect(state.selectionNumberOf('/tmp/nowhere.png'), 0);
    expect(state.isImageSelected('/tmp/nowhere.png'), isFalse);
  });

  test('toggling appends to the tail rather than reusing a freed number', () {
    state.selectedImages = [img('a'), img('b')];
    state.toggleImageSelection(img('c'));

    expect(state.selectionNumberOf('/tmp/c.png'), 3);
  });

  test('removing from the middle renumbers everything after it', () {
    // The failure this guards: dropping the index for the removed path only,
    // leaving 'c' still claiming 3 while it is now second in the payload.
    state.selectedImages = [img('a'), img('b'), img('c')];

    state.toggleImageSelection(img('b'));

    expect(state.isImageSelected('/tmp/b.png'), isFalse);
    expect(state.selectionNumberOf('/tmp/b.png'), 0);
    expect(state.selectionNumberOf('/tmp/a.png'), 1);
    expect(state.selectionNumberOf('/tmp/c.png'), 2);
  });

  test('reordering the reference strip renumbers the grid', () {
    // The strip is a ReorderableListView; dragging there is the user telling
    // the model which image is first, so the badges have to follow.
    state.selectedImages = [img('a'), img('b'), img('c')];

    state.reorderSelectedImages(0, 2);

    expect(state.selectionNumberOf('/tmp/b.png'), 1);
    expect(state.selectionNumberOf('/tmp/a.png'), 3);
  });

  test('clearing leaves nothing numbered', () {
    state.selectedImages = [img('a'), img('b')];
    state.clearImageSelection();

    expect(state.selectionNumberOf('/tmp/a.png'), 0);
    expect(state.selectedImages, isEmpty);
  });
}
