import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/browser_file.dart';
import 'package:joycai_image_ai_toolkits/screens/browser/widgets/browser_selection_bar.dart';
import 'package:joycai_image_ai_toolkits/screens/browser/widgets/file_card.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/widgets/preview/media_preview_dialog.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:joycai_image_ai_toolkits/state/file_browser_state.dart';
import 'package:joycai_image_ai_toolkits/widgets/shell/phone_dock.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/focus_pane.dart';

import '../../screenshots/harness/fixture_env.dart';
import '../../screenshots/harness/shoot.dart';
import '../../screenshots/harness/suite.dart';

void main() {
  late FixtureEnv env;
  setUpScreenSuite((value) => env = value);

  FocusNode pane(WidgetTester tester, String name) => tester
      .widgetList<FocusPane>(find.byType(FocusPane))
      .firstWhere((p) => p.node.debugLabel == 'browser-pane-$name')
      .node;

  Future<void> press(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    LogicalKeyboardKey? modifier,
  }) async {
    if (modifier != null) await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(key);
    if (modifier != null) await tester.sendKeyUpEvent(modifier);
    await settle(tester);
  }

  Future<FileBrowserState> mount(WidgetTester tester, {Size size = const Size(1440, 900)}) async {
    await mountApp(
      tester,
      env: env,
      screen: AppScreen.fileBrowser,
      size: size,
      before: (_) async {
        AppState().fileBrowserState.setViewMode(BrowserViewMode.grid);
        AppState().fileBrowserState.clearSelection();
      },
    );
    pane(tester, 'grid').requestFocus();
    await settle(tester);
    return AppState().fileBrowserState;
  }

  final primary = Platform.isMacOS ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft;

  testWidgets('context menu and double-click preview restore the targeted file', (tester) async {
    final state = await mount(tester);
    final file = state.filteredFiles.firstWhere((f) => f.category == FileCategory.image);
    final card = find.byWidgetPredicate((w) => w is FileCard && w.file.path == file.path);
    await tester.tap(card, buttons: kSecondaryButton);
    await settle(tester);
    await press(tester, LogicalKeyboardKey.escape);
    expect(pane(tester, 'grid').hasPrimaryFocus, isTrue);
    state.clearSelection();
    await press(tester, LogicalKeyboardKey.space);
    expect(state.selectedFiles, {file});
    await tester.tap(card);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(card);
    await settle(tester);
    expect(find.byType(MediaPreviewDialog), findsOneWidget);
    await press(tester, LogicalKeyboardKey.escape);
    state.clearSelection();
    await press(tester, LogicalKeyboardKey.space);
    expect(state.selectedFiles, {file});
  });

  testWidgets('group rows and virtualized scrolling survive resize, sorting and removal', (
    tester,
  ) async {
    final state = await mount(tester);
    final original = state.allFiles;
    final directories = state.activeDirectories;
    try {
      state.allFiles = [
        for (var i = 0; i < 101; i++)
          BrowserFile(
            path: 'C:/keyboard/${i == 0 ? 'a' : 'b'}/${i.toString().padLeft(3, '0')}.txt',
            name: '${i.toString().padLeft(3, '0')}.txt',
            category: FileCategory.text,
            size: 0,
            modified: DateTime(2026),
          ),
      ];
      state.activeDirectories = ['C:/keyboard/a', 'C:/keyboard/b'];
      await actInRealAsync(tester, () async {
        state.setSortField(BrowserSortField.name);
        state.setSortAscending(true);
        state.setGroupByFolder(true);
      });
      expect(state.folderSections.map((s) => s.count), [1, 100]);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(state.selectedFiles.single.name, '001.txt', reason: 'skip header after partial row');
      for (var i = 0; i < 25; i++) {
        await press(tester, LogicalKeyboardKey.arrowDown);
      }
      final active = state.selectedFiles.single;
      expect(int.parse(active.name.split('.').first), greaterThan(90));
      final rect = tester.getRect(find.text(active.name).first);
      expect(rect.top, greaterThan(140));
      expect(rect.bottom, lessThan(700));
      tester.view.physicalSize = const Size(390, 844);
      await settle(tester);
      final selectionBar = tester.getRect(find.byType(BrowserSelectionBar));
      expect(selectionBar.bottom, lessThan(tester.getRect(find.byType(PhoneDock)).top));
      expect(tester.getRect(find.text(active.name).first).bottom, lessThan(selectionBar.top));
      await press(tester, LogicalKeyboardKey.space);
      expect(state.selectedFiles, isEmpty, reason: 'resize preserves file identity');
      await actInRealAsync(tester, () async => state.setSortAscending(false));
      await press(tester, LogicalKeyboardKey.space);
      expect(state.selectedFiles, {active}, reason: 'sorting preserves file identity');
      state.allFiles = state.allFiles.where((f) => f.path != active.path).toList();
      state.setSearchQuery('');
      await settle(tester);
      await press(tester, LogicalKeyboardKey.space);
      expect(state.selectedFiles, hasLength(1));
      expect(state.selectedFiles.single.path, isNot(active.path));
    } finally {
      state.allFiles = original;
      state.activeDirectories = directories;
      state.setSearchQuery('');
    }
  });

  testWidgets('grid selection, contracting ranges, focus-only movement and Tab', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final state = await mount(tester);
      final files = state.filteredFiles.toList();
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(state.selectedFiles, {files[1]});
      await press(tester, LogicalKeyboardKey.arrowRight, modifier: LogicalKeyboardKey.shiftLeft);
      expect(state.selectedFiles, {files[1], files[2]});
      await press(tester, LogicalKeyboardKey.arrowLeft, modifier: LogicalKeyboardKey.shiftLeft);
      expect(state.selectedFiles, {files[1]});
      await press(tester, LogicalKeyboardKey.arrowRight, modifier: primary);
      expect(state.selectedFiles, {files[1]});
      final item = tester
          .getSemantics(find.bySemanticsLabel(files[2].name).first)
          .getSemanticsData();
      expect(item.flagsCollection.isFocused, Tristate.isTrue);
      await press(tester, LogicalKeyboardKey.space);
      expect(state.selectedFiles, {files[1], files[2]});
      await press(tester, LogicalKeyboardKey.tab);
      expect(pane(tester, 'grid').hasFocus, isFalse);
      await press(tester, LogicalKeyboardKey.tab, modifier: LogicalKeyboardKey.shiftLeft);
      expect(pane(tester, 'grid').hasPrimaryFocus, isTrue);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('list retains identity, scrolls offscreen, survives filtering and empty results', (
    tester,
  ) async {
    final state = await mount(tester);
    await press(tester, LogicalKeyboardKey.arrowRight);
    final active = state.selectedFiles.single;
    await actInRealAsync(tester, () async => state.setViewMode(BrowserViewMode.list));
    await press(tester, LogicalKeyboardKey.space);
    expect(state.selectedFiles, isEmpty, reason: 'switching view retains active file');
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(state.selectedFiles.single, state.filteredFiles[2]);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    await settle(tester);
    expect(state.selectedFiles.single, state.filteredFiles[4]);
    for (var i = 0; i < 20; i++) {
      await press(tester, LogicalKeyboardKey.arrowDown);
    }
    expect(state.selectedFiles.single, state.filteredFiles.last);
    expect(tester.getRect(find.text(state.filteredFiles.last.name).first).bottom, lessThan(700));
    state.setSearchQuery(active.name);
    await settle(tester);
    state.clearSelection();
    await press(tester, LogicalKeyboardKey.space);
    expect(state.selectedFiles, {active});
    state.setSearchQuery('no-matching-file-here');
    await settle(tester);
    state.clearSelection();
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.space);
    expect(state.selectedFiles, isEmpty);
    state.setSearchQuery('');
  });

  testWidgets('F6 cycles visible panes and reverse; closing staging restores grid', (tester) async {
    final state = await mount(tester);
    await actInRealAsync(tester, () async {
      AppState().fileStagingState.addAll(state.filteredFiles.take(1).toList());
    });
    await press(tester, LogicalKeyboardKey.f6);
    expect(pane(tester, 'staging').hasPrimaryFocus, isTrue);
    await press(tester, LogicalKeyboardKey.f6);
    expect(pane(tester, 'tree').hasPrimaryFocus, isTrue);
    await press(tester, LogicalKeyboardKey.f6, modifier: LogicalKeyboardKey.shiftLeft);
    expect(pane(tester, 'staging').hasPrimaryFocus, isTrue);
    await tester.sendKeyDownEvent(primary);
    await press(tester, LogicalKeyboardKey.backslash, modifier: LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(primary);
    await settle(tester);
    expect(pane(tester, 'grid').hasFocus, isTrue);
    await press(tester, LogicalKeyboardKey.f6);
    expect(pane(tester, 'tree').hasPrimaryFocus, isTrue);
  });

  testWidgets('preview and narrow drawer restore source pane; search protects selection', (
    tester,
  ) async {
    final state = await mount(tester, size: const Size(834, 1112));
    final file = state.filteredFiles.firstWhere((f) => f.category == FileCategory.image);
    final card = find.byWidgetPredicate((w) => w is FileCard && w.file.path == file.path);
    await tester.tap(card);
    await settle(tester);
    await press(tester, LogicalKeyboardKey.enter);
    expect(find.byType(MediaPreviewDialog), findsOneWidget);
    await press(tester, LogicalKeyboardKey.escape);
    expect(pane(tester, 'grid').hasPrimaryFocus, isTrue);
    await press(tester, LogicalKeyboardKey.backslash, modifier: primary);
    expect(find.byType(Drawer), findsWidgets);
    pane(tester, 'tree').requestFocus();
    await settle(tester);
    await press(tester, LogicalKeyboardKey.f6);
    expect(pane(tester, 'grid').hasPrimaryFocus, isTrue);
    final selected = state.selectedFiles.toSet();
    await press(tester, LogicalKeyboardKey.keyF, modifier: primary);
    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.f6);
    expect(state.selectedFiles, selected);
    expect(pane(tester, 'grid').hasFocus, isFalse);
    await press(tester, LogicalKeyboardKey.escape);
  });
}
