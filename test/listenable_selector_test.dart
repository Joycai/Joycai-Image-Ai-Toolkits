import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/listenable_selector.dart';

/// Rebuilds for what it selects, not for every notification.
void main() {
  testWidgets('a notification that changes nothing selected builds nothing', (tester) async {
    final notifier = ValueNotifier<int>(0);
    addTearDown(notifier.dispose);
    var builds = 0;
    await tester.pumpWidget(ListenableSelector<bool>(
      listenable: notifier,
      selector: () => notifier.value.isEven,
      builder: (context) {
        builds++;
        return const SizedBox();
      },
    ));
    expect(builds, 1);

    notifier.value = 2; // still even
    await tester.pump();
    expect(builds, 1);

    notifier.value = 3;
    await tester.pump();
    expect(builds, 2);
  });

  testWidgets('a new listenable is followed, the old one dropped', (tester) async {
    final a = ValueNotifier<int>(0);
    final b = ValueNotifier<int>(0);
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    var builds = 0;
    Widget host(ValueNotifier<int> n) => ListenableSelector<int>(
          listenable: n,
          selector: () => n.value,
          builder: (context) {
            builds++;
            return const SizedBox();
          },
        );
    await tester.pumpWidget(host(a));
    await tester.pumpWidget(host(b));
    final before = builds;
    a.value = 5;
    await tester.pump();
    expect(builds, before, reason: 'the old listenable no longer reaches it');
    b.value = 5;
    await tester.pump();
    expect(builds, before + 1);
  });
}
