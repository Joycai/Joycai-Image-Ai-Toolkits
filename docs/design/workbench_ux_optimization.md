# Workbench UI/UX Optimization Plan

**Scope:** `lib/screens/workbench/`  
**Goal:** Beauty · Modern · Convenience · Theme consistency · Multi-screen adaptation  
**Date:** 2026-06-14

---

## 1. Current State Audit

### Architecture Overview

The workbench uses a 3-panel layout:

```
┌─────────────────────────────────────────────────────────────┐
│  [≡]  [Tab 0] [Tab 1] [Tab 2] [Tab 3] [Tab 4] [Tab 5]  [⚙] │  ← WorkbenchTopBar
├──────────┬──────────────────────────────────┬───────────────┤
│          │                                  │               │
│  Left    │       Center Content             │  Right Config │
│  Panel   │  (Gallery / Tool View)           │  Panel        │
│  (Sidebar│                                  │  (Form)       │
│  or Tree)│                                  │               │
│          │                                  │               │
├──────────┴──────────────────────────────────┴───────────────┤
│  ● Execution Logs                        [last log line] [↑] │  ← WorkbenchBottomConsole
└─────────────────────────────────────────────────────────────┘
```

**Responsive mapping:**
- Desktop (≥1000px): Full 3-panel layout with resizable dividers
- Tablet (600–999px): Left panel becomes a `Drawer`; right panel becomes `endDrawer`
- Mobile (<600px): Both panels are drawers; right config is a `DraggableScrollableSheet` via FAB

### Tab Inventory

| # | Tab | Left Panel | Right Panel |
|---|-----|-----------|-------------|
| 0 | Image Processing | UnifiedSidebar (folder tree) | WorkbenchConfigPanel |
| 1 | Comparator | Hidden | MetadataInspector |
| 2 | Mask Editor | Hidden | Hidden |
| 3 | Crop & Resize | Hidden | Hidden |
| 4 | Prompt Optimizer | OptimizerReferencePanel | OptimizerConfigPanel |
| 5 | Video Generation | UnifiedSidebar | VideoConfigPanel |

---

## 2. Issues Identified

### 2.1 Visual Design Gaps

#### Top Bar
- Background is flat `colorScheme.surface` with a thin `Divider` — no depth or visual interest.
- On narrow screens, tab labels use **9px font size** (extremely small) beneath an 18px icon.
- The sidebar toggle (`Icons.menu / Icons.menu_open`) is an icon button with no label — unclear to new users.
- No visual hierarchy between the toolbar actions and the tab strip.

#### Gallery Cards (`_ImageCard`)
- Image name bar at the bottom uses a fixed `Colors.black.withAlpha(0.6)` — ignores dark/light theme.
- Dimensions badge at top uses `Colors.black.withAlpha(0.4)` — unreadable on dark images.
- Hover action buttons (Compare, Mask, Crop) appear at top-left, overlapping the dimensions badge.
- Selected state: border + blue overlay + shadow — three simultaneous indicators feel visually noisy.
- `BoxFit.contain` with a `Padding(4)` leaves awkward gap between card edges and image on non-square images.

#### Config Panel (`WorkbenchConfigPanel`)
- Inconsistent divider heights: `Divider(height: 32)`, `Divider(height: 24)`, `const Divider()` used interchangeably.
- `SwitchListTile` for "Use Streaming" breaks the visual rhythm of the form (different height/density than the surrounding controls).
- Model selection uses a custom `InkWell + Padding` collapsible instead of a proper `ExpansionTile` — icon is `keyboard_arrow_right/down` which looks like a navigation arrow.
- "Send to Optimizer" and "Queue Settings" inside a `surfaceContainerLow` card feel disconnected from the primary action button below.
- Hardcoded `Text("Use Streaming", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold))` — bypasses `textTheme`.

#### Bottom Console
- Fixed 36px status bar height — insufficient tap target on mobile (Material recommends 48px minimum).
- Log console height (`_height = 200`) is local state and resets on every widget rebuild/hot reload.
- The resize handle is a 4px-high `Container` with `color: outlineVariant.withAlpha(50)` — nearly invisible.
- Processing indicator uses raw `Colors.green` / `Colors.red` / `Colors.grey` instead of `colorScheme.primary` / `colorScheme.error`.

#### Comparator (`ComparatorView`)
- Footer shows full file paths in a single text line: `"Raw: /Users/.../file.png | After: /Users/.../file.png"` — truncated on any real path, and not localized.
- The scan line handle (24px in swap mode) is functional but not visually polished — no hover state or shadow.
- Empty state is plain centered text with icon — no instructional guidance.

#### Mask Editor / Crop & Resize
- Empty states show "No image selected for masking" / generic text with no call-to-action button to return to gallery.
- MaskEditorView `"Failed to load image"` error has no retry affordance.

#### Video Tab
- Floating video preview card (`VideoWorkbenchOverlay`) has no entrance/exit animation.
- Frame drop targets use hardcoded `"Tap to Pick"` English string (not localized via `l10n`).
- `_FrameDropTarget` in mobile mode opens the _left_ drawer (`openLeftPanel()`) labeled as "gallery" — unintuitive; the left sidebar is a folder tree, not the temp gallery.
- `_ReferenceImagesTarget` drop hint uses `l10n.dropVideoReferenceHere` but no visual cue distinguishes it from frame targets.

#### Prompt Optimizer
- The `Icons.arrow_forward_rounded` / `Icons.arrow_downward_rounded` between panels is static — gives no feedback during active AI generation.
- The refined output panel has no "copy" shortcut inline; user must select all text manually.
- No visual progress indicator during streaming (text just appends; no animated cursor or skeleton).

### 2.2 Theme Consistency

These raw color constants appear in workbench files but should use `colorScheme` equivalents:

| Hardcoded Color | Recommended Token | File |
|----------------|-------------------|------|
| `Colors.grey[400]`, `Colors.grey[600]` | `colorScheme.outline` | `gallery.dart`, multiple |
| `Colors.green` (processing) | `colorScheme.primary` | `workbench_bottom_console.dart` |
| `Colors.red` (error) | `colorScheme.error` | `workbench_bottom_console.dart` |
| `Colors.grey` (idle) | `colorScheme.outline` | `workbench_bottom_console.dart` |
| `Colors.black54`, `Colors.black.withAlpha(150)` | `Colors.black54` is acceptable for image overlays, but thumbnail label should use `colorScheme.inverseSurface` | `gallery.dart` |
| `Colors.blueAccent`, `Colors.orangeAccent` (comparator labels) | Define in theme extension or use `colorScheme.primary` / `colorScheme.tertiary` | `comparator_view.dart` |
| `Colors.red` (delete action) | `colorScheme.error` | `gallery.dart` context menu |
| `Colors.purple`, `Colors.indigo`, `Colors.teal` (context menu icons) | Avoid semantic-free colors; use icon only or consistent `colorScheme` token | `gallery.dart` |

### 2.3 Multi-Screen Adaptation Gaps

| Issue | Affected Screens |
|-------|-----------------|
| 9px tab label text on narrow screens is unreadable | All tabs on tablet |
| Mobile FAB for right panel is `Icons.tune` — generic; changes meaning per tab | Mobile (all tabs) |
| Console status bar only 36px tall — insufficient touch target | Mobile |
| `_FrameDropTarget` on mobile taps open left drawer (wrong) | Video tab, mobile |
| Tab 2 (Mask Editor) and Tab 3 (Crop) hide all panels silently with no "back" affordance | Tablet/Mobile |
| `ReorderableListView` in selection preview has no visual cue that items are reorderable on mobile | Mobile |
| Gallery `LayoutBuilder` with `maxWidth ≤ 0` guard is good, but no minimum grid item count guard | All |
| Prompt Optimizer `PromptOptimizerView` breaks at `Responsive.mobileBreakpoint` (600px) which is the widget's own `constraints.maxWidth`, not the screen width — correct approach but inconsistent naming | Prompt Optimizer |

---

## 3. Optimization Proposals

### 3.1 Top Bar — Visual Hierarchy + Readability

**Target:** Modern, clear, app-identity reinforcing

**Changes:**

1. **Elevated surface with blur effect** — Replace flat `colorScheme.surface` background with a `ClipRect + BackdropFilter` blur pill when content scrolls behind it (desktop). On mobile, use `colorScheme.surfaceContainerLow` for slight elevation.

2. **Tab indicator redesign** — Switch from the default underline indicator to a pill/capsule indicator using `TabBar`'s `indicator` property:
   ```dart
   indicator: BoxDecoration(
     color: colorScheme.primaryContainer,
     borderRadius: BorderRadius.circular(20),
   ),
   indicatorSize: TabBarIndicatorSize.tab,
   labelColor: colorScheme.onPrimaryContainer,
   unselectedLabelColor: colorScheme.onSurfaceVariant,
   ```

3. **Narrow screen tabs** — Replace the 9px stacked icon+text with icon-only tabs on narrow screens. Move labels into `Tooltip` which already exists. Increase icon size from 18px to 22px.

4. **Sidebar toggle button** — Use `IconButton.filledTonal` to give it visual weight matching its importance. Add a subtle badge when sidebar contains unread/new items.

5. **Top bar height** — Increase the `TabBar` height to accommodate the pill indicator with comfortable padding (min 48px total row height including the tab).

**Breakpoint behavior:**
```
Desktop (≥1000px): Icon + Label tabs, pill indicator, sidebar toggle left, settings icon right
Tablet (600–999px): Icon-only tabs (with tooltips), pill indicator, menu icon left, ⚙ right  
Mobile (<600px):   Icon-only tabs in scrollable TabBar, hamburger left, overflow menu right
```

---

### 3.2 Gallery Cards — Clarity + Polish

**Target:** Clean thumbnails that communicate selection state without visual noise

**Changes:**

1. **Single selection indicator** — Remove the blue tint overlay. Keep only the border and a checkmark badge. The badge should be `colorScheme.primary` circle with white check, positioned top-right (already done) but animate its appearance with `AnimatedScale`.

2. **Hover actions — pill design** — Group the three action buttons (Compare, Mask, Crop) into a single horizontally centered pill that floats over the bottom third of the image on hover:
   ```
   ┌──────────────────────────────────┐
   │  [image thumbnail]               │
   │                                  │
   │  ┌─[⇄]──[✏]──[✂]──────────────┐ │  ← pill overlay, bottom-center
   │  └──────────────────────────────┘ │
   └──────────────────────────────────┘
   ```
   Move dimension badge inside the image (top-right) using a smaller semi-transparent chip.

3. **Name label** — Show filename only on hover/selection (not always). When hidden, the image fills the full card for a cleaner grid. On mobile (no hover), show a truncated name always but limit to 1 line.

4. **Aspect ratio preservation** — Use `BoxFit.cover` instead of `BoxFit.contain` for thumbnails to fill the card cleanly. This is standard in modern photo grid UIs (Lightroom, Google Photos). The current `Padding(4)` around the thumbnail creates visual gap.

5. **Card border radius** — Increase from `12` to `16` for a more modern look. Also remove the `Padding(4)` wrapper and let the `ClipRRect` handle antialiasing.

6. **Video card** — The VIDEO label badge is good. Consider adding a duration badge (once thumbnail is loaded) in the bottom-left using the same `surfaceContainerHighest` chip style.

---

### 3.3 Config Panel — Structure + Density

**Target:** Scannable sidebar with clear hierarchy; primary action prominent

**Changes:**

1. **Section headers** — Replace raw `Divider` elements with a consistent section header style:
   ```dart
   // Section header widget
   Padding(
     padding: EdgeInsets.only(top: 16, bottom: 8),
     child: Text(
       label.toUpperCase(),
       style: textTheme.labelSmall?.copyWith(
         color: colorScheme.primary,
         letterSpacing: 1.0,
         fontWeight: FontWeight.bold,
       ),
     ),
   )
   ```

2. **Model selection** — Replace the custom `InkWell` collapsible with an `ExpansionTile` configured with `tilePadding: EdgeInsets.zero`. Show the selected model name as the subtitle when collapsed.

3. **"Use Streaming" toggle** — Move into the model settings expansion (it's an AI behavior setting, not a prompt setting). Use a `SwitchListTile` with `dense: true` and `visualDensity: VisualDensity.compact`.

4. **Action zone** — The current two-button area ("Send to Optimizer" + Settings gear) and the primary Process button create visual confusion about what the primary action is. Redesign:
   ```
   ┌─────────────────────────────────────┐
   │  [▶  Process 3 images            ]  │  ← FilledButton, full width, always visible
   ├─────────────────────────────────────┤
   │  [✨ Send to Optimizer]  [⚙]        │  ← Row: OutlinedButton + IconButton
   └─────────────────────────────────────┘
   ```
   The separation makes the primary CTA unambiguous.

5. **Prompt field** — Add a character count badge in the bottom-right corner of the `MarkdownEditor`. The current field has no length feedback.

6. **Selection preview** — The 16/9 aspect ratio placeholder is too tall. Replace with a horizontal scrollable strip of fixed 80px height (current strip is 100px). This saves vertical space for the form controls that matter more.

---

### 3.4 Bottom Console — Visibility + Status

**Target:** Always-useful status bar; expandable log viewer

**Changes:**

1. **Status bar height** — Increase to 44px on desktop, 48px on mobile for adequate touch target.

2. **Progress bar integration** — When `isProcessing`, show a thin `LinearProgressIndicator` (height: 2px) at the very top of the status bar strip:
   ```dart
   Stack(children: [
     if (isProcessing) Positioned(top: 0, left: 0, right: 0,
       child: LinearProgressIndicator(minHeight: 2)),
     // ... rest of status bar
   ])
   ```

3. **Color tokens** — Replace `Colors.green / red / grey` with:
   - `colorScheme.primary` (processing/active)
   - `colorScheme.error` (error state)
   - `colorScheme.outline` (idle)

4. **Resize handle visibility** — Increase handle to 6px height, use `colorScheme.outlineVariant` with `0.8` opacity (not `50` alpha). Add `Icons.drag_handle` icon centered on the handle.

5. **Persist console height** — Add `consoleHeight` to `AppState` and persist to SQLite. Use the persisted value in `_WorkbenchBottomConsoleState.initState`.

6. **Mobile task summary** — The current mobile task summary shows raw running/pending counts. Enhance with an ETA if available from `TaskQueueService.estimatedTimeRemaining`.

---

### 3.5 Comparator — Professional Feel

**Target:** Photography-grade comparison experience

**Changes:**

1. **Localize footer** — Replace the raw string `"Raw: ... | After: ..."` with:
   ```dart
   Text(l10n.comparatorFooter(rawName, afterName))  // or individual labels
   ```
   Show only filename (not full path). Add image dimensions when available.

2. **Scan handle polish** — In swap mode, make the scan handle:
   - Increase hit area to 60px wide
   - Animate the handle circle with a subtle pulse when at center (0.5 ratio)
   - Show `|` divider line with a glowing `boxShadow` using `colorScheme.primary`

3. **Empty state CTA** — Add drag targets in the empty state:
   ```
   ┌──────────────────┐  ┌──────────────────┐
   │    Drop RAW      │  │   Drop AFTER     │
   │    image here    │  │   image here     │
   │   or pick from   │  │   or pick from   │
   │    [Gallery]     │  │    [Gallery]     │
   └──────────────────┘  └──────────────────┘
   ```

4. **Metadata panel** — `MetadataInspector` (right panel, Tab 1) should show a side-by-side diff view of EXIF data, not just a list. Highlight differences with `colorScheme.error` for values that changed.

---

### 3.6 Mask Editor & Crop — Contextual Guidance

**Changes:**

1. **Empty state with action** — Both tools show no image when first opened. Add:
   ```dart
   ElevatedButton.icon(
     onPressed: () => appState.setWorkbenchTab(0), // go to gallery
     icon: Icon(Icons.photo_library_outlined),
     label: Text(l10n.selectFromGallery),
   )
   ```

2. **Mask Editor toolbar** — The current toolbar (`MaskEditorToolbar`) contains brush color, size slider, opacity slider, and action buttons all in one row. On narrow screens this scrolls. Consider a two-row layout: top row for actions (Undo, Clear, Save), bottom row for brush settings.

3. **Binary mode indicator** — When `isBinaryMode = true`, add a prominent banner at the top of the view:
   ```dart
   if (isBinaryMode)
     ColoredBox(
       color: colorScheme.tertiaryContainer,
       child: Padding(
         padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
         child: Text(l10n.binaryModeActive, style: ...),
       ),
     )
   ```

4. **Mask save feedback** — After saving, briefly flash the saved mask thumbnail in a `SnackBar` with an embedded preview image (32px × 32px) before the text.

---

### 3.7 Prompt Optimizer — Flow & Feedback

**Changes:**

1. **Animated arrow** — During refinement (`isRefining`), replace the static arrow icon with an `AnimatedRotation` spinner or a pulsing `AnimatedIcon`:
   ```dart
   isRefining
     ? SizedBox(
         width: 32, height: 32,
         child: CircularProgressIndicator(strokeWidth: 2),
       )
     : Icon(Icons.arrow_forward_rounded, size: 32)
   ```

2. **Streaming cursor** — Append a blinking `|` character to `_optRefinedPromptCtrl.text` while streaming, removed when done. Gives clear visual feedback of live generation.

3. **Inline copy button** — Add a `copyToClipboard` icon button in the top-right corner of the output `MarkdownEditor`:
   ```dart
   // In MarkdownEditor's trailing actions
   IconButton(
     icon: Icon(Icons.copy_all_outlined),
     onPressed: () => Clipboard.setData(ClipboardData(text: controller.text)),
   )
   ```

4. **Reference panel header** — `OptimizerReferencePanel` has images for context. Add a label count badge: `"3 reference images"` to clarify the panel's purpose.

---

### 3.8 Video Tab — Integration & Polish

**Changes:**

1. **Fix mobile frame picker** — `_FrameDropTarget` on mobile currently calls `openLeftPanel()` which opens the folder sidebar. Fix to open a `showModalBottomSheet` with the temp gallery images, or navigate to Tab 0 first:
   ```dart
   onTap: () {
     appState.setWorkbenchTab(0); // go to gallery
     // or: open dedicated image picker bottom sheet
   }
   ```
   This is a functional bug, not just a cosmetic issue.

2. **Localize "Tap to Pick"** — Add `tapToPick` to all `.arb` files and use `l10n.tapToPick`.

3. **Video overlay animation** — Wrap the `Positioned` card in `AnimatedSlide` + `AnimatedOpacity`:
   ```dart
   AnimatedSlide(
     offset: isVisible ? Offset.zero : const Offset(0, 0.2),
     duration: Duration(milliseconds: 300),
     curve: Curves.easeOutCubic,
     child: AnimatedOpacity(
       opacity: isVisible ? 1.0 : 0.0,
       duration: Duration(milliseconds: 200),
       child: videoCard,
     ),
   )
   ```

4. **Frame targets visual diff** — First Frame and Last Frame targets look identical. Differentiate:
   - First Frame: `colorScheme.primaryContainer` tint, `Icons.first_page` icon
   - Last Frame: `colorScheme.tertiaryContainer` tint, `Icons.last_page` icon

---

### 3.9 Theme Hardcoding Fixes

Replace all identified hardcoded colors with theme tokens. Priority order:

| Priority | Location | Change |
|----------|----------|--------|
| High | `workbench_bottom_console.dart:126` | `Colors.green` → `colorScheme.primary` |
| High | `workbench_bottom_console.dart:127` | `Colors.red` → `colorScheme.error` |
| High | `workbench_bottom_console.dart:126` | `Colors.grey` → `colorScheme.outline` |
| High | `gallery.dart:489` | `Colors.black.withAlpha(0.6)` label bar → `colorScheme.inverseSurface.withOpacity(0.85)` |
| Medium | `gallery.dart:464` | `Colors.black.withAlpha(0.4)` dimensions → `colorScheme.inverseSurface.withOpacity(0.6)` |
| Medium | `gallery.dart:700+` | Context menu icon colors → `colorScheme.primary` / `colorScheme.error` only |
| Medium | `comparator_view.dart` | `Colors.blueAccent` → `colorScheme.primary`; `Colors.orangeAccent` → `colorScheme.tertiary` |
| Low | `gallery.dart` | `Colors.grey[400]`, `Colors.grey[600]` → `colorScheme.outline` |

---

### 3.10 Multi-Screen Layout Improvements

#### Tablet (600–999px) — Currently Underserved

The tablet breakpoint hits `isNarrow = true` which triggers drawer mode for both panels, but still shows the full tab bar. Enhancements:

1. **Floating left panel** — Instead of a full-screen `Drawer`, use a side sheet that slides in over the content (partially transparent overlay) to keep context.
2. **Compact right panel** — Tablet right panel as `endDrawer` should have a max width of 320px (not 80% of screen which can be 800px on a large tablet).
3. **Tab 2/3 back affordance** — When Mask Editor or Crop & Resize hides both panels, show a small `Chip` or `ActionChip` at the top of the toolbar: `← Back to Gallery`. This is especially important on tablet where the top bar tabs are icon-only.

#### Mobile (<600px) — Refine Existing Patterns

1. **FAB context awareness** — Change FAB icon per tab:
   - Tab 0: `Icons.tune` (config)
   - Tab 1: `Icons.info_outline` (metadata)
   - Tab 4: `Icons.settings_suggest_outlined` (optimizer settings)
   - Tab 5: `Icons.tune` (video config)
   - Tabs 2, 3: Hide FAB (no right panel)

2. **Bottom sheet drag indicator** — Add the standard Material drag indicator at the top of all `DraggableScrollableSheet` instances (`Container(width: 32, height: 4, color: colorScheme.outlineVariant)`).

3. **Process button persistence** — The mobile bottom sheet already pins the Process button at top. Also show a mini version in the status bar when the sheet is closed (a small `FilledButton.tonal` showing selected count).

---

## 4. Implementation Priority

### Phase 1 — Quick Wins (High impact, low risk)

| Item | File(s) | Effort |
|------|---------|--------|
| Color token fixes | `workbench_bottom_console.dart`, `gallery.dart`, `comparator_view.dart` | S |
| Status bar height 36→44/48px | `workbench_bottom_console.dart` | S |
| Tab indicator: pill style | `workbench_top_bar.dart` | S |
| Console progress bar | `workbench_bottom_console.dart` | S |
| Streaming animated arrow | `workbench_screen.dart`, `prompt_optimizer_view.dart` | S |
| Fix "Tap to Pick" localization | `video_config_panel.dart` + all `.arb` | S |
| Fix mobile frame picker (functional bug) | `video_config_panel.dart` | M |

### Phase 2 — Visual Polish (Medium impact, medium effort)

| Item | File(s) | Effort |
|------|---------|--------|
| Gallery card hover pill redesign | `gallery.dart` | M |
| Gallery `BoxFit.cover` + remove padding | `gallery.dart` | S |
| Config panel section headers | `workbench_config_panel.dart` | M |
| Model selection → `ExpansionTile` | `workbench_config_panel.dart`, `model_selection_section.dart` | M |
| Empty state CTAs (Mask, Crop, Comparator) | `mask_editor_view.dart`, `comparator_view.dart`, `crop_resize_view.dart` | M |
| Video overlay entrance animation | `video_workbench_view.dart` | S |
| Frame targets visual differentiation | `video_config_panel.dart` | S |

### Phase 3 — Deep Improvements (High impact, higher effort)

| Item | File(s) | Effort |
|------|---------|--------|
| Persist console height | `workbench_bottom_console.dart`, `app_state.dart` | M |
| Tablet: floating side panel | `workbench_layout.dart` | L |
| Mobile FAB context awareness | `workbench_layout.dart`, `workbench_screen.dart` | M |
| Comparator: dual drop zone empty state | `comparator_view.dart` | M |
| Streaming cursor in optimizer | `workbench_screen.dart` | M |
| Mask editor 2-row toolbar (narrow) | `mask_editor_toolbar.dart` | M |
| Binary mode banner | `mask_editor_view.dart`, `workbench_screen.dart` | S |

---

## 5. Design Tokens Reference

For consistency, all new UI components should use these theme tokens:

```dart
// Surfaces (hierarchy: lowest → highest elevation)
colorScheme.surface              // base background
colorScheme.surfaceContainerLow  // slightly elevated cards
colorScheme.surfaceContainer     // standard cards
colorScheme.surfaceContainerHigh // panels, bottom sheets
colorScheme.surfaceContainerHighest // chips, badges

// Text
colorScheme.onSurface            // primary text
colorScheme.onSurfaceVariant     // secondary/caption text
colorScheme.outline              // borders, placeholders, icons

// Interactive
colorScheme.primary              // primary actions, selected state, active status
colorScheme.onPrimary            // text on primary
colorScheme.primaryContainer     // pill indicator background, hover state
colorScheme.onPrimaryContainer   // text in selected tab

// Semantic
colorScheme.error                // delete, error, failure
colorScheme.tertiary             // secondary accent (e.g., "AFTER" comparator label)

// Typography (use textTheme, not hardcoded sizes)
textTheme.labelSmall             // section headers, uppercase labels
textTheme.bodySmall              // captions, metadata
textTheme.bodyMedium             // form fields, normal content
textTheme.titleSmall             // panel section titles
textTheme.titleMedium            // card titles, panel headers
```

---

## 6. Accessibility Notes

- All interactive elements must maintain minimum 48×48px touch targets (especially on mobile): status bar, gallery cards on narrow screens, comparator scan handle.
- Color should never be the sole differentiator — selected image state currently uses color (blue tint) + border + checkmark; the checkmark is sufficient; keep it, but ensure the border uses adequate contrast ratio (≥3:1 for UI components per WCAG 2.1 AA).
- Tooltip coverage is already good (most icon buttons have tooltips). Verify `comparator_view.dart` scan handle has an accessible label.
- The streaming text in Prompt Optimizer should have `Semantics(liveRegion: true)` to announce updates to screen readers.

---

*End of document. See `execution_plan.md` for task scheduling context.*
