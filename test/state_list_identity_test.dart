// A `select` only sees a list change when the list is a new instance — the
// project rule is "new list before notifyListeners()". These pin it for the
// state methods that once mutated in place.

import 'package:flutter_test/flutter_test.dart';

import 'package:joycai_image_ai_toolkits/models/app_image.dart';
import 'package:joycai_image_ai_toolkits/state/downloader_state.dart';
import 'package:joycai_image_ai_toolkits/state/workbench_ui_state.dart';

void main() {
  test('video reference images get a new list on add and remove', () {
    final ui = WorkbenchUIState();
    final a = AppImage(path: '/a.png', name: 'a.png');
    final b = AppImage(path: '/b.png', name: 'b.png');

    final before = ui.videoReferenceImages;
    ui.addVideoReferenceImage(a);
    expect(identical(before, ui.videoReferenceImages), isFalse);
    expect(before, isEmpty, reason: 'the old list must not be touched');

    ui.addVideoReferenceImage(b);
    final twoItems = ui.videoReferenceImages;
    ui.removeVideoReferenceImage(a);
    expect(identical(twoItems, ui.videoReferenceImages), isFalse);
    expect(twoItems.map((i) => i.path), ['/a.png', '/b.png']);
    expect(ui.videoReferenceImages.map((i) => i.path), ['/b.png']);
  });

  test('a no-op add or remove keeps the list and stays silent', () {
    final ui = WorkbenchUIState();
    final a = AppImage(path: '/a.png', name: 'a.png');
    ui.addVideoReferenceImage(a);
    final list = ui.videoReferenceImages;
    var notified = 0;
    ui.addListener(() => notified++);

    ui.addVideoReferenceImage(a);
    ui.removeVideoReferenceImage(AppImage(path: '/x.png', name: 'x'));
    expect(identical(list, ui.videoReferenceImages), isTrue);
    expect(notified, 0);
  });

  test('downloader logs get a new list on add and reset', () {
    final state = DownloaderState();
    final before = state.logs;
    state.addLog('hello');
    expect(identical(before, state.logs), isFalse);
    expect(before, isEmpty);

    final withLine = state.logs;
    state.reset();
    expect(identical(withLine, state.logs), isFalse);
    expect(withLine, hasLength(1));
  });
}
