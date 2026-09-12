# 011 — 玻璃菜单从触发它的那个角长出

- **Status**: TODO
- **Commit**: 0b97136
- **Severity**: HIGH
- **Category**: 物理性与原点(3)
- **Estimated scope**: 1 个文件加约 45 行 + 4 个调用点各改 2 行 + 1 个测试改 1 行

## Problem

菜单的缩放原点写死在左上角:

```dart
// lib/widgets/glass/app_glass_menu.dart:145-160 — 现状
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (AppMotion.prefersReduced(context)) return child;
    final curved = CurvedAnimation(parent: animation, curve: AppMotion.enter, reverseCurve: AppMotion.quick);
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
        alignment: Alignment.topLeft,
        child: child,
      ),
    );
  }
```

对右键菜单这是对的——`position` 就是指针落点,菜单左上角挂在指针上。但同一个路由还
服务另一种形状:**按钮下拉**。那种形状由这个辅助函数定位,它把菜单的**右**边缘对齐
按钮的右边缘:

```dart
// lib/widgets/glass/app_glass_menu.dart:94-98 — 现状
Offset appGlassMenuPositionBelow(BuildContext anchor, {double width = kAppGlassMenuWidth}) {
  final box = anchor.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return Offset.zero;
  return box.localToGlobal(Offset(box.size.width - width, box.size.height + AppSpace.s4));
}
```

于是这 4 个调用点打开的菜单,**贴着按钮的是右上角,却从左上角长出来**——230px 宽的
面板从一个按钮不在的角展开:

- `lib/screens/batch/task_queue_card.dart:557`
- `lib/screens/models/widgets/channel_column.dart:294`
- `lib/screens/models/widgets/models_phone_layout.dart:326`
- `lib/screens/models/widgets/model_detail_column.dart:400`

第二种错法出现在贴边翻转时。布局代理会在菜单要超出窗口时把它翻到落点的另一侧:

```dart
// lib/widgets/glass/app_glass_menu.dart:177-189 — 现状
  Offset getPositionForChild(Size size, Size childSize) {
    final double minX = padding.left + _margin;
    final double minY = padding.top + _margin;
    final double maxX = math.max(minX, size.width - padding.right - _margin - childSize.width);
    final double maxY = math.max(minY, size.height - padding.bottom - _margin - childSize.height);

    // Flip to the other side of the point before clamping: a menu opened near
    // the bottom-right corner still has its corner at the click.
    double x = position.dx;
    double y = position.dy;
    if (x > maxX) x = position.dx - childSize.width;
    if (y > maxY) y = position.dy - childSize.height;
    return Offset(x.clamp(minX, maxX), y.clamp(minY, maxY));
  }
```

翻转之后贴着落点的是右下角,原点却仍是左上角——在窗口底部右键,菜单是朝着指针
**缩回去**的方向长出来的。

为什么值得修:浮层的原点是它唯一能说明「我从哪来」的手段。原点错了,0.96→1 的缩放
就从一次「从这个按钮里展开」退化成一次无来源的整体放大。这是本应用唯一的浮层,且
每个下拉调用点都错。

## Target

原点由**菜单实际停在哪个角**决定,而这个角在路由被 push 之前就能算出来:高度是确定的
(行高固定),落点、窗口尺寸与安全区在调用点全部可知。

```dart
// lib/widgets/glass/app_glass_menu.dart — 目标(新增)

/// The height an [AppGlassMenu] built from [entries] wants: 6 of padding at
/// each end, a 28 row each — 42 under a disabled row carrying its reason — and
/// a 1px rule in 4 of padding for each divider.
///
/// Not a layout input; the menu is still laid out by its own content. This is
/// what [showAppGlassMenu] needs *before* the route exists, to know which
/// corner the panel will be anchored by and therefore which corner it should
/// scale out of.
double appGlassMenuHeight(List<AppGlassMenuEntry> entries) {
  double height = AppSpace.s6 * 2;
  for (final AppGlassMenuEntry entry in entries) {
    height += switch (entry) {
      AppGlassMenuItem(:final bool isEnabled, :final String? note) =>
        !isEnabled && note != null ? _AppGlassMenuRow._noteHeight : AppSize.compact,
      _ => 1 + AppSpace.s4 * 2,
    };
  }
  return height;
}

/// Which corner of the menu ends up on [position] — the corner it should
/// therefore scale out of.
///
/// [anchor] is where the *caller* put the point: `topLeft` for a right-click,
/// where the menu hangs off the pointer, and `topRight` for a dropdown laid
/// under a button's right edge. [_AppGlassMenuLayout.getPositionForChild]
/// then flips an axis where the menu would run off the window, and a flipped
/// axis always leaves that far edge on the point.
Alignment _menuOrigin({
  required Offset position,
  required Size childSize,
  required Size screenSize,
  required EdgeInsets padding,
  required Alignment anchor,
}) {
  const double margin = _AppGlassMenuLayout._margin;
  final double minX = padding.left + margin;
  final double minY = padding.top + margin;
  final double maxX = math.max(minX, screenSize.width - padding.right - margin - childSize.width);
  final double maxY = math.max(minY, screenSize.height - padding.bottom - margin - childSize.height);
  return Alignment(
    position.dx > maxX ? 1 : anchor.x,
    position.dy > maxY ? 1 : anchor.y,
  );
}

/// Opens a menu under the button [anchor] belongs to, its right edge on the
/// button's right edge — and growing out of that corner.
Future<void> showAppGlassMenuBelow(
  BuildContext anchor, {
  required List<AppGlassMenuEntry> entries,
  double width = kAppGlassMenuWidth,
}) {
  return showAppGlassMenu(
    anchor,
    position: appGlassMenuPositionBelow(anchor, width: width),
    entries: entries,
    width: width,
    anchor: Alignment.topRight,
  );
}
```

```dart
// lib/widgets/glass/app_glass_menu.dart:72-90 — 目标(改)
Future<void> showAppGlassMenu(
  BuildContext context, {
  required Offset position,
  required List<AppGlassMenuEntry> entries,
  double width = kAppGlassMenuWidth,
  Alignment anchor = Alignment.topLeft,
}) async {
  final navigator = Navigator.of(context);
  final MediaQueryData media = MediaQuery.of(context);
  // Clamped the way the delegate clamps it, so a menu longer than the window
  // is measured at the height it will actually get.
  final double maxHeight = math.max(
    0,
    media.size.height - media.padding.vertical - _AppGlassMenuLayout._margin * 2,
  );
  final action = await navigator.push<VoidCallback>(
    _AppGlassMenuRoute(
      position: position,
      entries: entries,
      width: width,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      duration: AppMotion.durationOf(context, AppMotion.state),
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      origin: _menuOrigin(
        position: position,
        childSize: Size(width, math.min(appGlassMenuHeight(entries), maxHeight)),
        screenSize: media.size,
        padding: media.padding,
        anchor: anchor,
      ),
    ),
  );
  action?.call();
}
```

```dart
// lib/widgets/glass/app_glass_menu.dart:156-158 — 目标(改)
        scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
        alignment: origin,
        child: child,
```

## Repo conventions to follow

- 时长与曲线全部来自 `AppMotion`(`lib/core/design_tokens.dart:317`)。本计划**不改**
  任何时长或曲线,只改原点。
- 间距/尺寸走 `AppSpace` / `AppSize`(`s4` = 4、`s6` = 6、`compact` = 28)。
- 已经把「从哪长出来」做对的样板在同一文件:反向曲线 `reverseCurve: AppMotion.quick`
  与 0.96 起手(`app_glass_menu.dart:152-156`)。这两点保持原样。
- 文件里已有 `import 'dart:math' as math;`(第 1 行),`_menuOrigin` 直接用。

## Steps

1. `lib/widgets/glass/app_glass_menu.dart`:在 `appGlassMenuPositionBelow`
   (第 94-98 行)下方新增 `appGlassMenuHeight`、`_menuOrigin`、
   `showAppGlassMenuBelow` 三个顶层声明,内容照抄上面 Target 节。
2. 同文件:给 `showAppGlassMenu`(第 72 行)加 `Alignment anchor = Alignment.topLeft`
   具名参数,并按 Target 节改写函数体(新增 `media` / `maxHeight` 两个局部变量与
   `origin:` 实参)。其余实参原样不动。
3. 同文件 `_AppGlassMenuRoute`(第 100 行):在 `required this.width,`(第 104 行)一组
   构造参数里加 `required this.origin,`,并在 `final double width;` 旁加
   `/// Which corner the panel grows out of — see [_menuOrigin].` + `final Alignment origin;`。
4. 同文件 `buildTransitions`(第 145 行):把 `alignment: Alignment.topLeft,` 改成
   `alignment: origin,`。这一行是本计划的**全部**视觉改动。
5. 把 4 个下拉调用点从 `showAppGlassMenu(… position: appGlassMenuPositionBelow(…) …)`
   换成 `showAppGlassMenuBelow(…)`,逐个如下(只删 `position:` 一行、把函数名换掉,
   其余实参原样保留):
   - `lib/screens/batch/task_queue_card.dart:555-558` →
     `await showAppGlassMenuBelow(context, width: _menuWidth, entries: [ … ]);`
   - `lib/screens/models/widgets/channel_column.dart:292-296` →
     `showAppGlassMenuBelow(anchor, entries: entries(anchor))`
   - `lib/screens/models/widgets/models_phone_layout.dart:324-327` →
     `showAppGlassMenuBelow(anchor, entries: channelMenuItems(anchor, …))`
   - `lib/screens/models/widgets/model_detail_column.dart:398-401` →
     `showAppGlassMenuBelow(anchor, entries: [ … ])`
6. 右键菜单的 3 个调用点(`file_context_menu.dart:47`、`folder_context_menu.dart:44`、
   `downloader_image_card.dart:83`)与 `channel_column.dart:177` 的 `onContextMenu`
   **不动**——它们传的是指针落点,`anchor` 的默认值 `Alignment.topLeft` 就是对的。
7. `test/app_glass_menu_test.dart`:新增一个测试,钉住原点(`appGlassMenuPositionBelow`
   仍是公开的,第 132 行那个既有测试不用改):

   ```dart
   testWidgets('a dropdown under a button scales out of its top-right corner', (tester) async {
     // 打开一个 showAppGlassMenuBelow 菜单,取出 ScaleTransition:
     final ScaleTransition scale = tester.widget(find.descendant(
       of: find.byType(AppGlassMenu),
       matching: find.byType(ScaleTransition),
     ).first);
     expect(scale.alignment, Alignment.topRight);
   });
   ```

   照该文件第 28 行既有的挂载方式(`showAppGlassMenu(host, position: at, entries: entries)`)
   写宿主,把它换成 `showAppGlassMenuBelow(host, entries: entries)`。
8. `dart format` 不跑(仓库未强制);`flutter analyze`。

## Boundaries

- **不要改布局代理** `_AppGlassMenuLayout.getPositionForChild`(第 177-189 行)。菜单
  停在哪里一个像素都不能变——本计划只改它**从哪里长出来**。
- 不要改时长、曲线、`0.96` 起手值、`reverseCurve`、`prefersReduced` 分支。
- 不要把 `appGlassMenuPositionBelow` 改成私有:`test/app_glass_menu_test.dart:132`
  直接用它。
- 不要动右键菜单的 4 个调用点。
- 不要给 `AppGlass`、`_AppGlassMenuRow`、`_AppGlassMenuRule` 加任何东西。
- 不要新增依赖。
- 若第 145-160 行或第 177-189 行与上文引用的不符,**停下来报告**。

## Verification

- **Mechanical**:
  - `flutter analyze` → 必须是 `No issues found!`
  - `flutter test test/app_glass_menu_test.dart` → 全绿(含新增的那条)
  - `grep -rn "appGlassMenuPositionBelow" lib/` → 应只剩 `app_glass_menu.dart` 自身
    两处(定义与 `showAppGlassMenuBelow` 内部)
- **Feel check**:`flutter run --release`
  - 「任务」屏 → 任一任务卡右上角的「⋯」按钮 → 菜单应从**按钮所在的那个角**(右上)
    张开,而不是从面板左上角。与修复前对比最直观的做法:连开两次,盯住面板左下角——
    修复前它是从左上角斜着扫出来的。
  - 「模型」屏 → 渠道列头的下拉按钮,同上。
  - 把窗口缩到很矮,在**靠近窗口底边**的文件卡上右键:菜单会向上翻转,此时它应从
    **下边缘**(贴着指针的那条边)长出,而不是从上边缘。
  - 打开系统「减少动态效果」:菜单应瞬间出现(`prefersReduced` 分支直接 return child),
    与修复前一致。
- **Done when**:上述三个场景里,菜单贴着触发点的那个角,就是它缩放的原点;且
  `flutter analyze` 零问题、菜单的落点与修复前逐像素一致(可用
  `flutter test test/app_glass_menu_test.dart` 里既有的边界断言确认)。
