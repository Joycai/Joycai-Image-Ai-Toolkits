import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/screens/batch/task_queue_screen.dart';

/// One labelled line of a task's expanded detail.
///
/// A prompt runs to hundreds of characters while every other value is a few.
/// Both defects below only showed up against a long value, which is why they
/// survived: reading the call site tells you nothing, and the short rows above
/// the prompt looked perfect.
void main() {
  const longPrompt =
      '# 任务\n生成一张超写实的 Cosplay 摄影照片。\n\n## 模特设定\n+ 面部：柔和的五官比例\n'
      '+ 身材：身高约155cm\n+ 假发与发饰：黑色高温丝假发\n+ 美瞳与妆容：深褐色美瞳\n\n'
      '## 服装与鞋子描述\n完全忽略模特原本的穿着。\n+ 上衣：白色哑光面料\n+ 袖子：大宽幅红白拼接\n'
      '+ 腰部：宽幅红色樱花图案束腰腰封\n+ 下装：红色百褶微蓬短裙\n+ 鞋子与袜子：白色皮质系带短靴';

  Future<void> pumpRow(WidgetTester tester, String value) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          child: TaskInfoRow(
            icon: Icons.description_outlined,
            label: '提示词',
            value: value,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Text valueTextOf(WidgetTester tester) =>
      tester.widget<Text>(find.byType(Text).last);

  testWidgets('the label stays level with the first line of a long value', (tester) async {
    await pumpRow(tester, longPrompt);

    final label = tester.getTopLeft(find.text('提示词: '));
    final valueBox = tester.getRect(find.text(longPrompt));

    // The defect: Row defaults to CrossAxisAlignment.center, which floated the
    // label to the vertical middle of a tall value. Everything rendered above
    // it then read as belonging to the row above — a prompt looked like it was
    // part of the config line.
    expect(valueBox.height, greaterThan(20),
        reason: 'the value must actually be multi-line for this to mean anything');
    expect(label.dy, lessThan(valueBox.top + 8),
        reason: 'the label must sit at the top of its value, not its middle');
  });

  testWidgets('a long value is bounded and ellipsized', (tester) async {
    await pumpRow(tester, longPrompt);

    final text = valueTextOf(tester);
    // overflow: ellipsis was already set here and did nothing, because ellipsis
    // needs a line bound to act on. The prompt wrapped over the whole panel.
    expect(text.maxLines, isNotNull);
    expect(text.maxLines, TaskInfoRow.maxValueLines);
    expect(text.overflow, TextOverflow.ellipsis);

    final valueBox = tester.getRect(find.text(longPrompt));
    expect(valueBox.height, lessThan(90),
        reason: 'a prompt must not sprawl down the panel unbounded');
  });

  testWidgets('a short value still renders on one line, untouched', (tester) async {
    await pumpRow(tester, '1536x2304');

    expect(find.text('1536x2304'), findsOneWidget);
    final valueBox = tester.getRect(find.text('1536x2304'));
    expect(valueBox.height, lessThan(24));
  });

  testWidgets('the label and its value share a row', (tester) async {
    // Guards the actual complaint: a value must never look like it belongs to
    // a neighbouring label.
    await pumpRow(tester, longPrompt);

    final label = tester.getRect(find.text('提示词: '));
    final valueBox = tester.getRect(find.text(longPrompt));
    expect(valueBox.left, greaterThan(label.right - 1),
        reason: 'the value sits beside its own label, not under another one');
  });
}
