// `D1d`: the model list's reading — key, direction and, on the phone,
// 「按渠道分组」 — is a *preference*, so it survives a relaunch, and a value
// this build does not recognise degrades to the default rather than throwing.
//
// The grouping flag is the one worth pinning hardest: it defaults to on
// because that is the shape the phone's tab has always had, and a regression
// to off would silently dissolve every channel group on first launch.
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/catalogue/model_list_ordering.dart';
import 'package:joycai_image_ai_toolkits/services/db/database_service.dart';
import 'package:joycai_image_ai_toolkits/state/model_list_state.dart';

import '../screenshots/harness/fixture_env.dart';

void main() {
  final TestWidgetsFlutterBinding binding = TestWidgetsFlutterBinding.ensureInitialized();

  late FixtureEnv env;
  late DatabaseService db;

  setUpAll(() async {
    env = installFixtureEnv(binding);
    db = DatabaseService();
  });

  tearDownAll(() => env.dispose());

  // An empty row is the closest this store gets to 「没存过」, and it is also
  // a value none of the three fields recognises — so every test below starts
  // from the same place a fresh install does.
  setUp(() async {
    for (final key in const [
      ModelListState.sortKeySetting,
      ModelListState.sortDirectionSetting,
      ModelListState.groupByChannelSetting,
    ]) {
      await db.saveSetting(key, '');
    }
  });

  test('a fresh install reads the list the way it always has', () async {
    final state = ModelListState();
    await state.load();

    expect(state.sortKey, ModelSortKey.manual);
    expect(state.sortDirection, ModelSortDirection.ascending);
    expect(state.groupByChannel, isTrue);
    expect(state.isDefault, isTrue);
    expect(state.isPhoneDefault, isTrue);
  });

  test('all three survive a relaunch', () async {
    final first = ModelListState();
    await first.load();
    await first.setSortKey(ModelSortKey.added);
    await first.setSortDirection(ModelSortDirection.descending);
    await first.setGroupByChannel(false);

    final second = ModelListState();
    await second.load();
    expect(second.sortKey, ModelSortKey.added);
    expect(second.sortDirection, ModelSortDirection.descending);
    expect(second.groupByChannel, isFalse);
  });

  test('a stored value this build does not know falls back to the default', () async {
    // A key written by a newer build, and a flag that got mangled: all three
    // fields degrade to the arrangement the screen has always had rather than
    // to whatever `false` happens to parse as.
    await db.saveSetting(ModelListState.sortKeySetting, 'contextWindow');
    await db.saveSetting(ModelListState.sortDirectionSetting, 'sideways');
    await db.saveSetting(ModelListState.groupByChannelSetting, 'yes');

    final state = ModelListState();
    await state.load();
    expect(state.sortKey, ModelSortKey.manual);
    expect(state.sortDirection, ModelSortDirection.ascending);
    expect(state.groupByChannel, isTrue);
  });

  test('grouping off is a departure for the phone, but not for the column', () async {
    final state = ModelListState();
    await state.load();
    await state.setGroupByChannel(false);

    // The right column has one channel and no groups to lose, so its button
    // stays quiet; the phone's tab is now one run across every channel, which
    // its button has to say.
    expect(state.isDefault, isTrue);
    expect(state.isPhoneDefault, isFalse);
  });

  test('setting a value it already holds notifies nobody', () async {
    final state = ModelListState();
    await state.load();

    var notifications = 0;
    state.addListener(() => notifications++);

    await state.setSortKey(ModelSortKey.manual);
    await state.setGroupByChannel(true);
    expect(notifications, 0);

    await state.setSortKey(ModelSortKey.kind);
    expect(notifications, 1);
  });
}
