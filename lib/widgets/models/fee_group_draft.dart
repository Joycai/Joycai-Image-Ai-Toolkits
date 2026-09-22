import 'package:flutter/widgets.dart';

import '../../models/pricing_group.dart';
import '../../models/spec_rate.dart';
import '../../services/billing/spec_billing.dart';
import '../../state/app_state.dart';
import 'spec_rate_table.dart';

/// What the fee-group editor edits (`D2 · 1e / 1f`, `D1a · 1d`): the name,
/// the billing mode and every mode's rates, validated as they are typed.
///
/// One draft serves the desktop's editor card, the tablet's inline card and
/// the phone's full-screen page, so the three cannot drift in what they
/// accept. It notifies on every keystroke — [canSave] and [isDirty] are read
/// live by the Save button and by the 「switch group」 confirmation.
///
/// Every mode's rates are kept through mode switches and written whatever
/// the mode, as the stored group keeps them: a table typed in and then
/// parked behind 「按 token」 survives the save.
class FeeGroupDraft extends ChangeNotifier {
  FeeGroupDraft(this.group) {
    final g = group;
    nameCtrl = TextEditingController(text: g?.name ?? '');
    inputPriceCtrl = TextEditingController(text: (g?.inputPrice ?? 0.0).toString());
    // Left blank when unset, which is what makes the field mean "follow the
    // input price" rather than "free".
    cacheInputPriceCtrl = TextEditingController(text: g?.cacheInputPrice?.toString() ?? '');
    outputPriceCtrl = TextEditingController(text: (g?.outputPrice ?? 0.0).toString());
    requestPriceCtrl = TextEditingController(text: (g?.requestPrice ?? 0.0).toString());
    billingMode = g?.billingMode ?? 'token';

    outputUnit = g?.outputUnit ?? OutputUnit.image;
    final rates = g?.outputRates ?? const <SpecRate>[];
    // The catch-all is the pinned bottom row; blank when the group has none
    // (unlisted specs then bill at zero, which the editor says out loud).
    final other = rates.where((r) => r.isCatchAll).firstOrNull;
    otherPriceCtrl = TextEditingController(text: other == null ? '' : other.price.toStringAsFixed(4));
    specRows.addAll(rates.where((r) => !r.isCatchAll).map(SpecRateDraft.of));
    // Blank when zero: most groups charge nothing for inputs, and an empty
    // row is what keeps that quiet (`D2c · 22a`).
    final inputPrice = g?.inputUnitPrice ?? 0.0;
    final inputFree = g?.inputFreeUnits ?? 0;
    inputImagePriceCtrl = TextEditingController(text: inputPrice > 0 ? inputPrice.toStringAsFixed(4) : '');
    inputFreeCtrl = TextEditingController(text: inputFree > 0 ? '$inputFree' : '');

    for (final ctrl in _controllers) {
      ctrl.addListener(notifyListeners);
    }
    _initial = _snapshot();
  }

  /// The group being edited; null while adding.
  final PricingGroup? group;

  late final TextEditingController nameCtrl;
  late final TextEditingController inputPriceCtrl;
  late final TextEditingController cacheInputPriceCtrl;
  late final TextEditingController outputPriceCtrl;
  late final TextEditingController requestPriceCtrl;
  late final TextEditingController otherPriceCtrl;

  /// Spec mode's input side (`D2c`): the price of one reference image and
  /// how many of each request's are free. Named for the image — the token
  /// mode already has an [inputPriceCtrl].
  late final TextEditingController inputImagePriceCtrl;
  late final TextEditingController inputFreeCtrl;
  late String billingMode;
  late OutputUnit outputUnit;
  final List<SpecRateDraft> specRows = [];

  late final String _initial;
  bool _disposed = false;

  List<TextEditingController> get _controllers =>
      [
        nameCtrl,
        inputPriceCtrl,
        cacheInputPriceCtrl,
        outputPriceCtrl,
        requestPriceCtrl,
        otherPriceCtrl,
        inputImagePriceCtrl,
        inputFreeCtrl,
      ];

  bool get isNew => group == null;
  bool get isToken => billingMode == 'token';
  bool get isSpec => billingMode == specBillingMode;
  bool get isRequest => billingMode == 'request';

  String get name => nameCtrl.text.trim();

  static double? _parsePrice(String text) => parsePriceInput(text);

  /// Whether [ctrl]'s text cannot be saved. A blank cache rate is a valid
  /// "inherit"; every other rate must parse.
  bool invalid(TextEditingController ctrl) {
    final text = ctrl.text.trim();
    if (identical(ctrl, cacheInputPriceCtrl) && text.isEmpty) return false;
    return _parsePrice(text) == null;
  }

  List<TextEditingController> get _activeFields =>
      isToken ? [inputPriceCtrl, cacheInputPriceCtrl, outputPriceCtrl] : [requestPriceCtrl];

  /// A blank catch-all is allowed (it means zero, and the table says so);
  /// anything typed there must parse.
  bool get otherPriceInvalid => otherPriceCtrl.text.trim().isNotEmpty && _parsePrice(otherPriceCtrl.text) == null;

  /// Blank is "inputs are free"; anything typed must parse. Checked only
  /// while the row is on screen — spec or request mode — so a value parked
  /// behind token mode can never block a save the user cannot see why.
  bool get inputImagePriceInvalid =>
      showsInputImages &&
      inputImagePriceCtrl.text.trim().isNotEmpty &&
      _parsePrice(inputImagePriceCtrl.text) == null;

  /// Whether the editor shows the input-image row: spec mode under every
  /// unit, and request mode (`D2e`) — the two modes whose groups charge
  /// inputs ([PricingGroup.chargesInputImages]).
  bool get showsInputImages => isSpec || isRequest;

  int get inputFreeUnits => int.tryParse(inputFreeCtrl.text.trim()) ?? 0;

  /// `22c`: a free count with no price does nothing, and the editor says so.
  bool get inputFreeWithoutPrice =>
      inputFreeUnits > 0 && (_parsePrice(inputImagePriceCtrl.text) ?? 0) <= 0;

  bool get ratesValid => isSpec
      ? !SpecTableIssues.of(specRows).blocksSave && !otherPriceInvalid && !inputImagePriceInvalid
      : !_activeFields.any(invalid) && !inputImagePriceInvalid;

  /// `1f`: Save lights up once the group has a name and its rates parse.
  bool get canSave => name.isNotEmpty && ratesValid;

  /// Whether anything differs from the group as it was opened.
  bool get isDirty => _snapshot() != _initial;

  void setMode(String mode) {
    if (mode == billingMode) return;
    billingMode = mode;
    notifyListeners();
  }

  void setUnit(OutputUnit unit) {
    if (unit == outputUnit) return;
    outputUnit = unit;
    notifyListeners();
  }

  void addSpecRow() {
    specRows.add(SpecRateDraft());
    notifyListeners();
  }

  void removeSpecRow(int index) {
    specRows.removeAt(index).dispose();
    notifyListeners();
  }

  /// `D2b · 21d` ④: a table that is only the catch-all is per-request billing
  /// in disguise, so the editor offers to say so — the price goes with it.
  void switchToRequest() {
    billingMode = 'request';
    if (otherPriceCtrl.text.trim().isNotEmpty) requestPriceCtrl.text = otherPriceCtrl.text.trim();
    notifyListeners();
  }

  /// Called by the spec table after it edits a row's conditions in place.
  void touch() => notifyListeners();

  /// The table as it will be stored: the ordinary rows, then the catch-all
  /// only when it has a price — a blank one is *no* catch-all, which is what
  /// makes unlisted specs bill at zero and count as unmatched.
  List<SpecRate> specRates() {
    final other = _parsePrice(otherPriceCtrl.text);
    return [
      for (final row in specRows) row.toRate(),
      if (other != null) SpecRate(price: other),
    ];
  }

  PricingGroup toGroup() {
    final cacheText = cacheInputPriceCtrl.text.trim();
    return PricingGroup(
      name: name,
      billingMode: billingMode,
      inputPrice: _parsePrice(inputPriceCtrl.text) ?? 0.0,
      // Blank stays null so the cost math falls back to the input price; an
      // explicit 0 is kept as a real (free) cache rate.
      cacheInputPrice: cacheText.isEmpty ? null : _parsePrice(cacheText),
      outputPrice: _parsePrice(outputPriceCtrl.text) ?? 0.0,
      requestPrice: _parsePrice(requestPriceCtrl.text) ?? 0.0,
      outputUnit: outputUnit,
      outputRates: specRates(),
      // Kept whatever the mode and unit, like the table: parked, not lost.
      // An unparseable price cannot get here while its row shows (it blocks
      // the save); behind another unit it falls back to what was stored.
      inputUnitPrice: inputImagePriceCtrl.text.trim().isEmpty
          ? 0.0
          : _parsePrice(inputImagePriceCtrl.text) ?? group?.inputUnitPrice ?? 0.0,
      inputFreeUnits: inputFreeUnits,
    );
  }

  String _snapshot() => [
        nameCtrl.text,
        billingMode,
        inputPriceCtrl.text,
        cacheInputPriceCtrl.text,
        outputPriceCtrl.text,
        requestPriceCtrl.text,
        outputUnit.name,
        otherPriceCtrl.text,
        inputImagePriceCtrl.text,
        inputFreeCtrl.text,
        for (final r in specRows) '${r.size}|${r.quality}|${r.seconds}|${r.priceCtrl.text}',
      ].join('\x00');

  /// Writes the draft: the new group's id, or the edited group's.
  ///
  /// Rates are snapshotted onto every usage row at request time, so a rate
  /// that silently saved as 0.0 poisoned history irreversibly. Unparseable
  /// input blocks the save rather than being coerced.
  Future<int?> save(AppState appState) async {
    if (!canSave) return null;
    final data = toGroup();
    final g = group;
    if (g == null) return appState.addPricingGroup(data);
    await appState.updatePricingGroup(g.id!, data);
    return g.id;
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final ctrl in _controllers) {
      ctrl.removeListener(notifyListeners);
      ctrl.dispose();
    }
    for (final row in specRows) {
      row.dispose();
    }
    super.dispose();
  }
}
