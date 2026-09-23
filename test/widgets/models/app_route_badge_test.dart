import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_theme.dart';
import 'package:joycai_image_ai_toolkits/core/constants.dart';
import 'package:joycai_image_ai_toolkits/core/design_tokens.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations_en.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations_zh.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/platforms.dart';
import 'package:joycai_image_ai_toolkits/widgets/models/app_route_badge.dart';
import 'package:joycai_image_ai_toolkits/widgets/models/route_labels.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/dashed_border.dart';

void main() {
  Future<ColorScheme> pump(
    WidgetTester tester,
    Widget child, {
    String? fontFamily,
  }) async {
    final theme = buildAppTheme(
      accent: AppConstants.presetThemes.values.first,
      brightness: Brightness.light,
      fontFamily: fontFamily,
    );
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: Scaffold(body: Center(child: child)),
    ));
    return theme.colorScheme;
  }

  BoxDecoration decorationOf(WidgetTester tester) => tester
      .widget<Container>(find.descendant(
        of: find.byType(AppRouteBadge),
        matching: find.byType(Container),
      ))
      .decoration! as BoxDecoration;

  testWidgets('current is a solid accent fill', (tester) async {
    final scheme = await pump(
      tester,
      const AppRouteBadge(label: 'Chat', state: RouteBadgeState.current),
    );
    expect(decorationOf(tester).color, scheme.primary);
    expect(tester.getSize(find.byType(AppRouteBadge)).height, 18);
  });

  testWidgets('configured is an accent hairline, deep ink', (tester) async {
    final scheme = await pump(
      tester,
      const AppRouteBadge(label: 'Resp', state: RouteBadgeState.configured),
    );
    final d = decorationOf(tester);
    expect(d.color, isNull);
    expect((d.border! as Border).top.color, scheme.primary);
    expect(tester.widget<Text>(find.text('Resp')).style!.color,
        scheme.onAccentTint);
  });

  testWidgets('the label is mono, falling back to the UI font for CJK', (tester) async {
    // The badge builds its style from scratch, so without the ambient family
    // its fallback would end at the mono stack and a Chinese route name would
    // drop to the engine's own (thinner) fallback face.
    await pump(
      tester,
      const AppRouteBadge(label: '对话', state: RouteBadgeState.quiet),
      fontFamily: 'Microsoft YaHei',
    );
    final style = tester.widget<Text>(find.text('对话')).style!;
    expect(style.fontFamily, kMonoFontFamilyFallback.first);
    expect(style.fontFamilyFallback!.last, 'Microsoft YaHei');
  });

  testWidgets('off is dashed', (tester) async {
    await pump(
      tester,
      const AppRouteBadge(label: 'Anth', state: RouteBadgeState.off),
    );
    expect(find.byType(DashedBorder), findsOneWidget);
  });

  testWidgets('the strip size is tappable', (tester) async {
    var taps = 0;
    await pump(
      tester,
      AppRouteBadge(
        label: 'Anthropic',
        state: RouteBadgeState.off,
        size: RouteBadgeSize.strip,
        trailingIcon: Icons.add,
        onTap: () => taps++,
      ),
    );
    expect(tester.getSize(find.byType(AppRouteBadge)).height, 28);
    await tester.tap(find.byType(AppRouteBadge));
    expect(taps, 1);
  });

  test('routes are named, short and full, and only DashScope translates', () {
    final AppLocalizations en = AppLocalizationsEn();
    final AppLocalizations zh = AppLocalizationsZh();
    expect(routeLabel(en, RouteKind.chat, short: true), 'Chat');
    expect(routeLabel(en, RouteKind.chat), 'Chat Completions');
    expect(routeLabel(zh, RouteKind.anthropic, short: true), 'Anth');
    expect(routeLabel(zh, RouteKind.dashscope, short: true), '百炼');
    expect(routeLabel(zh, RouteKind.dashscope), '百炼原生');
  });
}
