@Tags(['screenshots'])
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/models/llm_channel.dart';
import 'package:joycai_image_ai_toolkits/screens/models/widgets/channel_edit_dialog.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:material_ui/material_ui.dart';

import 'harness/fixture_env.dart';
import 'harness/shoot.dart';
import 'harness/suite.dart';

void main() {
  late FixtureEnv env;
  setUpScreenSuite((e) => env = e);
  for (final locale in const [
    Locale('en'),
    Locale('zh'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    Locale('ja'),
  ]) {
    for (final size in kShotSizes) {
      for (final brightness in Brightness.values) {
        testWidgets('Token Plan ${locale.toLanguageTag()} ${size.label} ${brightness.name}', (
          tester,
        ) async {
          await shoot(
            tester,
            env: env,
            screen: AppScreen.models,
            size: size,
            brightness: brightness,
            locale: locale,
            suffix: 'tokenUpload_${locale.toLanguageTag()}',
            after: (tester) async {
              final context = tester.element(find.byType(Navigator).first);
              unawaited(
                showDialog<void>(
                  context: context,
                  builder: (context) => ChannelEditDialog(
                    l10n: AppLocalizations.of(context)!,
                    appState: AppState(),
                    channel: LLMChannel(
                      displayName: 'Token Plan',
                      endpoint: 'https://token-plan.cn-beijing.maas.aliyuncs.com/api/v1',
                      apiKey: 'plan-key',
                      type: Vendors.dashscopeNative,
                    ),
                  ),
                ),
              );
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 500));
              final dialog = tester.element(find.byType(ChannelEditDialog));
              await tester.ensureVisible(find.text(AppLocalizations.of(dialog)!.channelTokenPlan));
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 500));
            },
          );
        });
      }
    }
  }
}
