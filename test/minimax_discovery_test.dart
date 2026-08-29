import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_dispatcher.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_family.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/minimax_payload.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

/// Pins model discovery on a MiniMax channel.
///
/// Two failures reported from a live account, one visible and one not:
///
/// * A channel stored as `…/v2` (which is what MiniMax's *video* doc shows)
///   answers 404 on `GET /v2/models` and `POST /v2/chat/completions`. Images
///   and video worked on that same channel, because those two protocols
///   derive their own base — the generic ones were still using the raw
///   string.
/// * On a correctly stored `…/v1` channel the button works and still never
///   produces `MiniMax-H3` or `image-01`. Upstream's listing enumerates the
///   compatible face; the native surfaces are not on it and cannot be
///   (docs/api/minimax.md §5). Nothing said so — the models simply were not
///   there, and the user had to know the ids by heart.
void main() {
  final minimax = Vendors.byId(Vendors.minimax);
  final minimaxAnthropic = Vendors.byId(Vendors.minimaxAnthropic);

  /// Every path a MiniMax channel may plausibly have been stored with,
  /// including the two that are wrong-but-understandable.
  const storedFaces = [
    'https://api.minimaxi.com',
    'https://api.minimaxi.com/v1',
    'https://api.minimaxi.com/v1/',
    'https://api.minimaxi.com/v2', // from the video doc
    'https://api.minimaxi.com/anthropic',
    'https://api.minimaxi.com/anthropic/v1',
  ];

  group('the native surfaces are declared as unlisted', () {
    test('both faces carry the same three models', () {
      for (final vendor in [minimax, minimaxAnthropic]) {
        expect(vendor.unlistedModels.map((m) => m.id),
            containsAll(['MiniMax-H3', 'image-01', 'image-01-live']),
            reason: vendor.id);
      }
      // Which chat face a channel stores decides nothing about what the
      // image and video endpoints serve, so the two lists must not drift.
      expect(minimax.unlistedModels.map((m) => m.id).toList(),
          minimaxAnthropic.unlistedModels.map((m) => m.id).toList());
    });

    test('the ids are spelled the way the endpoints accept them', () {
      // `MiniMax-H3` is sent verbatim as the `model` field; a lower-cased
      // copy here would be a 404 the user cannot diagnose from the picker.
      expect(minimax.unlistedModels.map((m) => m.id), contains('MiniMax-H3'));
      expect(minimax.unlistedModels.map((m) => m.id),
          isNot(contains('minimax-h3')));
    });

    test('no chat model is in the catalog — the listing already has those',
        () {
      // The catalog exists for what `/v1/models` structurally cannot return.
      // Adding an M-series id here would produce a duplicate row on every
      // fetch, or a stale one after upstream retires the model.
      for (final vendor in [minimax, minimaxAnthropic]) {
        for (final m in vendor.unlistedModels) {
          expect(ModelFamilyClassifier.classify(m.id), isNot(ModelFamily.openaiChat),
              reason: '${vendor.id}: ${m.id}');
        }
      }
    });

    test('each classifies onto the surface it was added for', () {
      // Being listed is only half the job: once added, the model has to route
      // to the native protocol rather than fall through to chat.
      expect(ModelFamilyClassifier.classify('MiniMax-H3'), ModelFamily.openaiVideo);
      expect(ModelFamilyClassifier.classify('image-01'), ModelFamily.minimaxImage);
      expect(ModelFamilyClassifier.classify('image-01-live'), ModelFamily.minimaxImage);
    });

    test('no other vendor gained a catalog', () {
      for (final v in Vendors.all) {
        if (v.id == Vendors.minimax || v.id == Vendors.minimaxAnthropic) {
          continue;
        }
        expect(v.unlistedModels, isEmpty, reason: v.id);
      }
    });
  });

  group('unlistedBeyond', () {
    test('adds every catalog entry to a listing that has none of them', () {
      final extra = minimax.unlistedBeyond(
          ['MiniMax-M3', 'MiniMax-M2.7', 'MiniMax-M2.5']);
      expect(extra.map((m) => m.id),
          ['MiniMax-H3', 'image-01', 'image-01-live']);
    });

    test('a relay that already lists one produces one row, not two', () {
      // Relays front MiniMax and do publish the image ids. Two entries for
      // one model is a worse list than the one we started with.
      final extra = minimax.unlistedBeyond(['gpt-4o', 'image-01']);
      expect(extra.map((m) => m.id), isNot(contains('image-01')));
      expect(extra.map((m) => m.id), contains('MiniMax-H3'));
    });

    test('the dedup is case-insensitive', () {
      // The catalog spells it `MiniMax-H3` because that is what the endpoint
      // wants; a relay is under no obligation to agree.
      final extra = minimax.unlistedBeyond(['minimax-h3', 'IMAGE-01']);
      expect(extra.map((m) => m.id), ['image-01-live']);
    });

    test('a listing covering everything adds nothing', () {
      final extra = minimax
          .unlistedBeyond(['MiniMax-H3', 'image-01', 'image-01-live']);
      expect(extra, isEmpty);
    });

    test('a vendor with no catalog is untouched by an empty listing', () {
      // The merge runs on every family now, so the no-catalog path is the
      // one nearly every channel in the app takes.
      expect(Vendors.byId(Vendors.openAIRest).unlistedBeyond(const []),
          isEmpty);
    });
  });

  group('mergeUnlistedModels', () {
    DiscoveredModel listed(String id) =>
        DiscoveredModel(modelId: id, displayName: id, rawData: {'id': id});

    test('appends the catalog after the live listing', () {
      final merged = mergeUnlistedModels(
          minimax, [listed('MiniMax-M3'), listed('MiniMax-M2.5')]);
      expect(merged.map((m) => m.modelId), [
        'MiniMax-M3',
        'MiniMax-M2.5',
        'MiniMax-H3',
        'image-01',
        'image-01-live',
      ]);
    });

    test('the live listing keeps its own rows untouched', () {
      // The endpoint's answer is the authoritative half; the merge may only
      // add to it. A catalog entry that shadowed a live row would pin a
      // description upstream has since changed.
      final live = listed('MiniMax-M3');
      final merged = mergeUnlistedModels(minimax, [live]);
      expect(merged.first, same(live));
    });

    test('a catalog entry is marked as one', () {
      final merged = mergeUnlistedModels(minimax, const []);
      final h3 = merged.firstWhere((m) => m.modelId == 'MiniMax-H3');
      expect(h3.rawData['source'], 'vendor-catalog');
      expect(h3.description, isNotEmpty,
          reason: 'the description is what tells the user which surface');
    });

    test('an id the listing already returned is not added twice', () {
      final merged =
          mergeUnlistedModels(minimax, [listed('image-01'), listed('gpt-4o')]);
      expect(merged.where((m) => m.modelId == 'image-01'), hasLength(1));
      expect(merged, hasLength(4));
    });

    test('a vendor with no catalog gets its listing back unchanged', () {
      // Every channel in the app runs this path; it must not so much as
      // reallocate the list.
      final live = [listed('gpt-4o')];
      expect(
          mergeUnlistedModels(Vendors.byId(Vendors.openAIRest), live),
          same(live));
    });

    test('an empty listing still yields the catalog', () {
      // A relay that serves no `/models` returns nothing rather than
      // throwing; the native models must survive that.
      expect(mergeUnlistedModels(minimaxAnthropic, const []).map((m) => m.modelId),
          ['MiniMax-H3', 'image-01', 'image-01-live']);
    });
  });

  group('the chat face derives from whatever the channel stored', () {
    test('the OpenAI face resolves to /v1 from every stored face', () {
      final derive = minimax.protocolBases[WireProtocol.openaiChat];
      expect(derive, isNotNull,
          reason: 'without this, chat and discovery use the raw endpoint');
      for (final endpoint in storedFaces) {
        expect(derive!(endpoint), 'https://api.minimaxi.com/v1',
            reason: endpoint);
      }
    });

    test('the Anthropic face resolves to /anthropic/v1 from every stored face',
        () {
      final derive =
          minimaxAnthropic.protocolBases[WireProtocol.anthropicChat];
      expect(derive, isNotNull);
      for (final endpoint in storedFaces) {
        expect(derive!(endpoint), 'https://api.minimaxi.com/anthropic/v1',
            reason: endpoint);
      }
    });

    test('a channel stored at /v2 reaches all four wires', () {
      // The reported configuration. Images and video already worked here —
      // they derive internally — so only the two generic protocols were
      // landing on `/v2/chat/completions` and `/v2/models`.
      const stored = 'https://api.minimaxi.com/v2';
      expect(minimax.protocolBases[WireProtocol.openaiChat]!(stored),
          'https://api.minimaxi.com/v1');
      expect(minimaxOpenAIBase(stored), 'https://api.minimaxi.com/v1');
      expect(minimaxV2Base(stored), 'https://api.minimaxi.com/v2');
    });

    test('the derivation does not reach the native protocols', () {
      // Those own their path shape and derive it themselves; listing them
      // here would rewrite the endpoint twice.
      for (final vendor in [minimax, minimaxAnthropic]) {
        expect(vendor.protocolBases.containsKey(WireProtocol.minimaxImages),
            isFalse,
            reason: vendor.id);
        expect(vendor.protocolBases.containsKey(WireProtocol.minimaxVideo),
            isFalse,
            reason: vendor.id);
      }
    });
  });
}
