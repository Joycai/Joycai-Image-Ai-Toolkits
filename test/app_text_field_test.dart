import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_theme.dart';
import 'package:joycai_image_ai_toolkits/widgets/app_text_field.dart';

void main() {
  const seed = Colors.indigo;

  Widget host(Widget child) => MaterialApp(
        theme: buildAppTheme(seedColor: seed, brightness: Brightness.light),
        home: Scaffold(body: Center(child: child)),
      );

  testWidgets('typing reports through onChanged', (tester) async {
    String? changed;
    await tester.pumpWidget(host(AppTextField(label: 'Name', onChanged: (v) => changed = v)));

    await tester.enterText(find.byType(TextField), 'hello');
    expect(changed, 'hello');
  });

  testWidgets('obscureText pins maxLines to 1 regardless of what was passed', (tester) async {
    await tester.pumpWidget(host(const AppTextField(obscureText: true, maxLines: 5)));

    expect(tester.widget<TextField>(find.byType(TextField)).maxLines, 1);
  });

  testWidgets('a validator switches to TextFormField', (tester) async {
    await tester.pumpWidget(host(AppTextField(validator: (v) => null)));

    expect(find.byType(TextFormField), findsOneWidget);
  });
}
