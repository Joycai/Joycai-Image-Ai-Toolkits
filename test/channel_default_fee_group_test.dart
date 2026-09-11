import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/private_data_dir.dart';

/// A channel's default fee group (`llm_channels.default_fee_group_id`) as the
/// repository stores it: saved and edited with the channel, and cleared when
/// its group is deleted rather than left pointing at nothing.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  usePrivateDataDir('joycai_default_fee_group_test');

  Map<String, dynamic> channel(String name, {int? group}) => {
        'display_name': name,
        'endpoint': 'https://example.com/v1',
        'api_key': 'k',
        'type': 'openai-api-rest',
        'default_fee_group_id': group,
      };

  test('a channel keeps its default group through an edit, and an edit can clear it', () async {
    final db = DatabaseService();
    final group = await db.addPricingGroup({'name': 'Pro'});
    final id = await db.addChannel(channel('With default', group: group));
    expect((await db.getChannel(id))!.defaultFeeGroupId, group);

    await db.updateChannel(id, channel('Renamed', group: group));
    expect((await db.getChannel(id))!.defaultFeeGroupId, group);

    await db.updateChannel(id, channel('Renamed'));
    expect((await db.getChannel(id))!.defaultFeeGroupId, isNull);
  });

  test('deleting a fee group clears it as a channel default, and only that group', () async {
    final db = DatabaseService();
    final doomed = await db.addPricingGroup({'name': 'Doomed'});
    final kept = await db.addPricingGroup({'name': 'Kept'});
    final a = await db.addChannel(channel('A', group: doomed));
    final b = await db.addChannel(channel('B', group: kept));

    await db.deletePricingGroup(doomed);

    expect((await db.getChannel(a))!.defaultFeeGroupId, isNull);
    expect((await db.getChannel(b))!.defaultFeeGroupId, kept);
  });
}
