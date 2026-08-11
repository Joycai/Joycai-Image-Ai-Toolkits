import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_theme.dart';
import 'package:joycai_image_ai_toolkits/services/window_chrome_service.dart';

/// Covers the channel that recolours the Windows title bar.
///
/// This shipped broken for three releases and nothing caught it. Every colour
/// crossed the channel as an int64 — an opaque ARGB value always exceeds
/// `0x7FFFFFFF`, and Dart's codec widens anything past that — while the runner
/// would only accept an int32. It rejected all of them, the Dart side caught
/// the error and dropped it on the floor, and the caption silently kept the OS
/// theme. Nothing in the app misbehaved; it simply never did the one thing it
/// existed to do.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('joycai/window_chrome');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;
  String? errorFrom;

  /// Installs a handler that records calls and answers with [reject] set to
  /// true when the runner should refuse them.
  void mockRunner({bool reject = false, Map<String, int>? hresults}) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (reject) throw PlatformException(code: 'bad_args', message: 'nope');
      return hresults ?? const {'darkMode': 0, 'caption': 0, 'text': 0};
    });
  }

  setUp(() {
    calls = [];
    errorFrom = null;
    WindowChromeService.resetCache();
    FlutterError.onError = (details) => errorFrom = details.library;
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    FlutterError.onError = FlutterError.presentError;
  });

  ThemeData theme(Brightness brightness) =>
      buildAppTheme(seedColor: Colors.teal, brightness: brightness);

  test('an opaque caption colour does not fit in an int32', () {
    // The whole defect in one assertion. Alpha is 0xFF on any colour this
    // sends, so the value is always above the int32 ceiling and the codec
    // always widens it. Any runner reading this channel has to accept an
    // int64; one that insists on int32 receives nothing it can use, ever.
    for (final brightness in [Brightness.light, Brightness.dark]) {
      final scheme = theme(brightness).colorScheme;
      for (final colour in [scheme.surfaceContainer, scheme.onSurface]) {
        final argb = colour.toARGB32();
        expect(argb, greaterThan(0x7FFFFFFF),
            reason: 'an opaque colour that fits in an int32 would hide the widening');
      }
    }
  });

  test('the colours survive the codec the runner decodes with', () {
    // Encoding and decoding with the real StandardMethodCodec is as close as
    // a Dart test gets to the runner. If the value that comes out the far end
    // is not the value that went in, the caption is painted the wrong colour.
    final scheme = theme(Brightness.light).colorScheme;
    final sent = <String, Object?>{
      'caption': scheme.surfaceContainer.toARGB32(),
      'text': scheme.onSurface.toARGB32(),
      'dark': false,
    };

    const codec = StandardMethodCodec();
    final decoded = codec.decodeMethodCall(
      codec.encodeMethodCall(MethodCall('setCaptionColors', sent)),
    );

    expect(decoded.arguments, sent);
  });

  group('on Windows', () {
    test('the caption takes the canvas colour and the label the text colour', () async {
      mockRunner();
      final scheme = theme(Brightness.light).colorScheme;

      await WindowChromeService.applyTheme(scheme);

      expect(calls, hasLength(1));
      expect(calls.single.method, 'setCaptionColors');
      final args = calls.single.arguments as Map;
      expect(args['caption'], scheme.surfaceContainer.toARGB32());
      expect(args['text'], scheme.onSurface.toARGB32());
      expect(args['dark'], isFalse);
    });

    test('dark mode is announced separately from the colours', () async {
      // Windows 10 rejects the two colour attributes but honours the dark
      // flag, so it has to travel on its own rather than be inferred.
      mockRunner();

      await WindowChromeService.applyTheme(theme(Brightness.dark).colorScheme);

      expect((calls.single.arguments as Map)['dark'], isTrue);
    });

    test('unchanged colours do not cross the channel twice', () async {
      mockRunner();
      final scheme = theme(Brightness.light).colorScheme;

      await WindowChromeService.applyTheme(scheme);
      await WindowChromeService.applyTheme(scheme);

      expect(calls, hasLength(1));
    });

    test('a rejected call is reported rather than dropped', () async {
      // The runner errors only on arguments it cannot read — a defect here,
      // not a property of the machine. Swallowing it is what let the int64
      // mismatch survive three releases.
      mockRunner(reject: true);

      await WindowChromeService.applyTheme(theme(Brightness.light).colorScheme);

      expect(errorFrom, 'window_chrome_service');
    });

    test('it reports what DWM did, because nothing else can see it', () async {
      // The caption is painted by the window manager, outside anything
      // Flutter renders — no widget test and no screenshot can reach it. The
      // platform's own answer in the execution log is the only evidence the
      // feature works, and its absence is what let a dead channel pass for a
      // working one across three releases.
      mockRunner();

      final report = await WindowChromeService.applyTheme(theme(Brightness.light).colorScheme);

      expect(report, isNotNull);
      expect(report, contains('applied'));
    });

    test('success is said once, not once per animation frame', () async {
      // A theme switch is animated, so this runs eight or nine times with
      // interpolated colours. Applying each frame is deliberate — the caption
      // then fades with the UI — but nine identical log lines per switch bury
      // the user's own output, which is what the execution log is for.
      mockRunner();
      final light = theme(Brightness.light).colorScheme;

      final first = await WindowChromeService.applyTheme(light);
      // Distinct colours, as each animation frame would be.
      final second = await WindowChromeService.applyTheme(theme(Brightness.dark).colorScheme);
      final third = await WindowChromeService.applyTheme(light);

      expect(first, isNotNull);
      expect(second, isNull);
      expect(third, isNull);
      expect(calls, hasLength(3), reason: 'the later frames were not applied to the caption');
    });

    test('a failure is said every time, however often it repeats', () async {
      // The opposite rule. A caption that silently stopped working is the
      // whole defect this service has already shipped once.
      mockRunner(hresults: const {'darkMode': 0, 'caption': -2147024809, 'text': 0});

      final first = await WindowChromeService.applyTheme(theme(Brightness.light).colorScheme);
      final second = await WindowChromeService.applyTheme(theme(Brightness.dark).colorScheme);

      expect(first, contains('refused'));
      expect(second, contains('refused'));
    });

    test('a partial refusal names the attribute that failed', () async {
      // Windows 10 takes the dark-mode flag and refuses the two colours, so
      // "it worked" and "it did nothing" have to be tellable apart per
      // attribute rather than as one boolean.
      mockRunner(hresults: const {'darkMode': 0, 'caption': -2147024809, 'text': -2147024809});

      final report = await WindowChromeService.applyTheme(theme(Brightness.light).colorScheme);

      expect(report, contains('refused'));
      expect(report, contains('caption'));
      expect(report, isNot(contains('darkMode')), reason: 'the attribute that succeeded was named as a failure');
    });

    test('a rejected call is retried on the next theme change', () async {
      // The cache used to be written before the await, so a refusal also made
      // the failure permanent: the next theme saw its colours already "sent".
      mockRunner(reject: true);
      await WindowChromeService.applyTheme(theme(Brightness.light).colorScheme);
      expect(calls, hasLength(1));

      mockRunner();
      await WindowChromeService.applyTheme(theme(Brightness.dark).colorScheme);
      await WindowChromeService.applyTheme(theme(Brightness.light).colorScheme);

      expect(calls, hasLength(3),
          reason: 'the light theme was never re-sent after being refused');
    });
  },
      skip: WindowChromeService.isSupported
          ? false
          : 'applyTheme is a no-op off Windows (host is ${Platform.operatingSystem})');
}
