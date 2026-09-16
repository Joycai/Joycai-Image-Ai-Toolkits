// `D1d`: the Models screen's right-hand list sorts on four keys, and sorting
// is a *reading* — it never writes `sort_order`, so 「默认顺序」 is always the
// way back to what the channel handed over.
//
// These pin the three rules that would otherwise rot silently: the kind key
// groups in the filter chips' order rather than alphabetically, every tie
// falls back to the stored order so a rebuild cannot reshuffle equal rows,
// and 「降序」 is the exact reverse of 「升序」 — ties included.
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/llm_model.dart';
import 'package:joycai_image_ai_toolkits/services/model_list_ordering.dart';

void main() {
  LLMModel model(int id, String name, String tag, {String? modelId}) => LLMModel(
        id: id,
        modelId: modelId ?? name.toLowerCase().replaceAll(' ', '-'),
        modelName: name,
        tag: tag,
      );

  List<String> names(Iterable<LLMModel> models) => models.map((m) => m.modelName).toList();

  List<LLMModel> sorted(
    List<LLMModel> models,
    ModelSortKey key, [
    ModelSortDirection direction = ModelSortDirection.ascending,
  ]) =>
      sortModels(models, key: key, direction: direction);

  // Stored order, deliberately neither alphabetical nor grouped by kind, and
  // with ids that do not follow it either — a channel whose models were added
  // in one order and dragged into another.
  final List<LLMModel> stored = <LLMModel>[
    model(30, 'Veo 3.1 Fast', 'video'),
    model(10, 'gemini 2.5 pro', 'multimodal'),
    model(50, 'Imagen 4', 'image'),
    model(20, 'Gemini 2.5 Flash', 'chat'),
    model(40, 'Amber Relay', 'refiner'),
  ];

  test('default order is the stored order, untouched', () {
    expect(names(sorted(stored, ModelSortKey.manual)), names(stored));
  });

  test('sorting never mutates the list it was given', () {
    final input = [...stored];
    sortModels(input, key: ModelSortKey.name, direction: ModelSortDirection.descending);
    expect(names(input), names(stored));
  });

  test('name sorts case-insensitively', () {
    // Lower-cased first: 'gemini 2.5 pro' lands beside 'Gemini 2.5 Flash'
    // rather than after every capitalised name, which is the whole point.
    expect(names(sorted(stored, ModelSortKey.name)), [
      'Amber Relay',
      'Gemini 2.5 Flash',
      'gemini 2.5 pro',
      'Imagen 4',
      'Veo 3.1 Fast',
    ]);
  });

  test('two rows sharing a display name are told apart by model id', () {
    final twins = <LLMModel>[
      model(1, 'Nano Banana', 'image', modelId: 'relay/nano-banana'),
      model(2, 'Nano Banana', 'image', modelId: 'google/nano-banana'),
    ];
    expect(
      sorted(twins, ModelSortKey.name).map((m) => m.modelId).toList(),
      ['google/nano-banana', 'relay/nano-banana'],
    );
  });

  test('kind groups in the filter chips order, not alphabetically', () {
    // chat · image · video · multimodal, and the legacy `refiner` after all
    // four — not chat · image · multimodal · refiner · video.
    expect(names(sorted(stored, ModelSortKey.kind)), [
      'Gemini 2.5 Flash',
      'Imagen 4',
      'Veo 3.1 Fast',
      'gemini 2.5 pro',
      'Amber Relay',
    ]);
  });

  test('inside a kind, rows run by name', () {
    final images = <LLMModel>[
      model(1, 'Imagen 4', 'image'),
      model(2, 'Flux', 'video'),
      model(3, 'Aurora', 'image'),
    ];
    expect(names(sorted(images, ModelSortKey.kind)), ['Aurora', 'Imagen 4', 'Flux']);
  });

  test('date added runs on the row id, oldest first', () {
    expect(names(sorted(stored, ModelSortKey.added)), [
      'gemini 2.5 pro',
      'Gemini 2.5 Flash',
      'Veo 3.1 Fast',
      'Amber Relay',
      'Imagen 4',
    ]);
  });

  test('descending is the exact reverse of ascending, for every key', () {
    for (final key in ModelSortKey.values) {
      final up = names(sorted(stored, key));
      final down = names(sorted(stored, key, ModelSortDirection.descending));
      expect(down, up.reversed.toList(), reason: 'key: ${key.name}');
    }
  });

  test('ties fall back to the stored order, in the sort direction', () {
    // Rows the key cannot separate: the whole list must still come back
    // in one fixed order rather than whatever the unstable sort leaves.
    final flat = <LLMModel>[
      model(5, 'Same', 'chat', modelId: 'a'),
      model(4, 'Same', 'chat', modelId: 'a'),
      model(3, 'Same', 'chat', modelId: 'a'),
    ];
    expect(sorted(flat, ModelSortKey.kind).map((m) => m.id).toList(), [5, 4, 3]);
    expect(
      sorted(flat, ModelSortKey.kind, ModelSortDirection.descending).map((m) => m.id).toList(),
      [3, 4, 5],
    );
  });

  test('a model not yet saved sorts oldest', () {
    final fresh = LLMModel(modelId: 'draft', modelName: 'Draft', tag: 'chat');
    final list = <LLMModel>[model(7, 'Saved', 'chat'), fresh];
    expect(names(sorted(list, ModelSortKey.added)), ['Draft', 'Saved']);
  });

  test('an empty channel sorts to an empty list on every key', () {
    for (final key in ModelSortKey.values) {
      expect(sorted(const <LLMModel>[], key), isEmpty);
    }
  });
}
