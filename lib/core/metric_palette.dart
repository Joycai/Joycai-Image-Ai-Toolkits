/// Identity colours for the five things the usage screens count.
///
/// Each hue names one metric and follows it everywhere it appears: a rate in
/// the fee-group editor, a token count in the usage summary, and a chip in the
/// record list are the same colour because they are the same quantity. That is
/// the colour's whole job — it says "input tokens", not "good" or "a lot".
///
/// Which is why these are literals rather than roles on the [ColorScheme]:
/// following the user's seed would make input and output the same hue under
/// every theme, and the distinction is the entire point. For the same reason
/// they are not in `AppSemanticColors` — success/warning/info state a
/// *condition*, these name a *category*. See `core/fee_group_palette.dart`,
/// which is the same idea for fee groups and deliberately avoids these hues.
///
/// Material swatches rather than hand-picked hex, unlike the fee-group
/// palette: these were already `Colors.blue`/`teal`/… at both of the call
/// sites this file replaced, and re-picking them here would have been a
/// silent visual change smuggled into a de-duplication.
library;

import 'package:flutter/material.dart';

const Color usageInputAccent = Colors.blue;
const Color usageCacheAccent = Colors.teal;
const Color usageOutputAccent = Colors.green;
const Color usageRequestAccent = Colors.purple;
const Color usageCostAccent = Colors.orange;
