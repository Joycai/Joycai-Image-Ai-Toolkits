# 009 — Snackbar 连发不再"退场再进场"地闪

- **Status**: DONE(2026-08-27 执行,flutter analyze 零问题,1130 个测试全通过)
- **Commit**: 07906de
- **Severity**: MEDIUM
- **Category**: 可中断性(4)/ 目的与频率(1)
- **Estimated scope**: 1 个文件 1 行 + 注释;另加 1 个收紧后的既有测试

## Problem

```dart
// lib/widgets/app_snackbar.dart:78 — 现状
    // Hidden first so a rapid string of calls (e.g. one failure per file in a
    // batch) doesn't queue up a stack of toasts the user has to dismiss one
    // at a time — only the latest state is worth showing.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
```

注释里的意图是对的——批量操作里每个文件报一次错,只有最新那条值得看。选错的是手段。

`hideCurrentSnackBar()` 会**播完当前 toast 的整段退场动画**(Material 的
`SnackBar` 退场约 250ms)再让下一条进场。于是一批 8 个失败的重命名任务,用户看到的是
八次「滑出 → 滑入」:一个在原地抖动 2 秒的方块,每一次都要重新读一遍才知道文案变没变。

`removeCurrentSnackBar()` 立刻摘掉当前那条,下一条马上进场——同样不排队(注释里那个
目的原样达成),但换的是**内容**而不是整个控件。审计准则第 4 条正是这一条:反复快速
触发的 UI 必须能从当前状态被接管,而不是每次从零重放。准则第 1 条给出同一个答案的另一面
——批量失败提示是高频、非庆祝性的信息,它的正确动画量是"尽可能少"。

## Target

```dart
// lib/widgets/app_snackbar.dart — 目标
    // Removed, not hidden: a rapid string of calls (e.g. one failure per file
    // in a batch) must not queue up a stack of toasts, and `hide` gets there
    // by playing the outgoing toast's full exit before the next one enters —
    // eight failures read as eight slide-out/slide-in flickers of the same
    // box. `remove` swaps the contents in place, so what changes is the
    // message rather than the whole control.
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(
```

## Repo conventions to follow

- 注释解释**为什么**,并且当选择有一个显而易见的替代项时,说明为什么不是它——参见
  `lib/widgets/app_run_console.dart:418`(`stop` 而非 `reset` 的理由)、
  `lib/core/design_tokens.dart:448`(为什么归零而不是缩短)。
- 测试写法参考 `test/app_snackbar_test.dart` 既有的 `host(...)` + `tap('Trigger')` 骨架。

## Steps

1. 打开 `lib/widgets/app_snackbar.dart`,把第 78–82 行的注释与
   `..hideCurrentSnackBar()` 替换为 Target 节给出的注释与 `..removeCurrentSnackBar()`。
   其余(`..showSnackBar(` 及整个 `SnackBar(...)`)一个字不动。
2. 收紧 `test/app_snackbar_test.dart:126` 那个既有测试,让它真正能测出这次差别。把
   第 135 行的 `await tester.pumpAndSettle();` 换成两帧定量 pump:
   ```dart
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
   ```
   断言(第 137–138 行)保持不变。同时把第 127–129 行的注释更新为:
   ```dart
    // Two fixed pumps, not pumpAndSettle: settling would pass either way. The
    // point is that the second toast is on screen *immediately* — with
    // `hide` the first is still playing its exit at this instant.
   ```
3. **先验证这个测试确实会红**:在第 1 步之前(或临时把 `removeCurrentSnackBar` 改回
   `hideCurrentSnackBar`)跑一次
   `flutter test test/app_snackbar_test.dart`,确认它失败;再改回来确认它绿。
   本仓库有过"新测试其实什么都没测"的先例,这一步不能跳。

## Boundaries

- **只改 `lib/widgets/app_snackbar.dart` 与 `test/app_snackbar_test.dart`。**
- 不要改 `SnackBar` 的 `duration`(4 秒 / 有操作时 8 秒)、颜色、圆角、内边距或
  `behavior`——那些都有各自的注释记录了来源。
- 不要动 `app_snackbar.dart:18-25` 的类文档(它描述的是重构前各调用点的写法,是史料,
  不是本计划的对象)。
- 不要去各个调用点加"要不要提示"的判断,本计划不改任何调用点。
- 不要新增依赖。

## Verification

- **Mechanical**:
  - `flutter analyze` → 必须是 `No issues found!`
  - `flutter test test/app_snackbar_test.dart` → 全部通过
  - 第 3 步的红/绿双向确认已完成
  - `grep -n "hideCurrentSnackBar" lib/widgets/app_snackbar.dart` → 无输出
- **Feel check**:`flutter run --release`,制造一批必然失败的任务(例如把输出目录指向
  一个只读路径后批量处理 5 张图):
  - 5 条错误提示替换时,**方块本身不应移动**——只有里面的文字换掉。修复前是滑出再滑入。
  - 单条提示(只触发一次)的进场必须与修复前完全一致:仍然从底部滑入。
  - 带操作按钮的提示(例如需要「重试」的)出现后,再触发一条普通提示:按钮那条应被
    立即换掉,不留残影。
- **Done when**:上述 `grep` 无输出,收紧后的测试在改动前红、改动后绿。
