### Feature Plan: Improve Prompts Management and Library UI

**Objective:** Enhance the usability of the Prompt Library and Prompts Management screen by separating "Refiner" system prompts from user prompts and improving the visual layout for scalability.

**Proposed Changes:**

1.  **Modify `lib/screens/workbench/control_panel.dart` (Library Button):**
    *   **Logic:** Update `_loadPrompts` (or the usage site) to **exclude** prompts tagged with `Refiner` from the `_groupedPrompts` list used by the library.
    *   **UI:** Refactor `_showPromptPickerMenu` to use a larger, two-pane dialog:
        *   **Left Pane:** A list of tags/categories (e.g., General, Characters, Styles).
        *   **Right Pane:** A list (or grid) of prompts belonging to the selected tag.
        *   This replaces the current long vertical scrollable list which is hard to navigate.

2.  **Modify `lib/screens/prompts/prompts_screen.dart` (Prompts Manager):**
    *   **Structure:** Introduce a `TabBar` (or SegmentedButton) to separate the view into two distinct sections:
        *   **"User Prompts"**: Shows all prompts *except* 'Refiner'.
        *   **"Refiner Prompts"**: Shows *only* prompts tagged with 'Refiner'.
    *   **UI:** Maintain the current CRUD functionality but scoped to the active tab.

3.  **Localization (`lib/l10n/app_en.arb`):**
    *   Add new strings:
        *   `"userPrompts"`: "User Prompts"
        *   `"refinerPrompts"`: "Refiner Prompts"
        *   `"selectCategory"`: "Select Category"

**Verification Plan:**
*   **Library Dialog:** Open the library in Workbench. Verify "Refiner" prompts are missing. Verify the new 2-pane layout works.
*   **Prompts Screen:** Open Prompts screen. Verify the two tabs exist. Verify "Refiner" prompts only appear in the second tab.
*   **Create/Edit:** Ensure creating a prompt with tag "Refiner" moves it to the correct tab automatically.

**Questions:**
*   Do you prefer a `TabBar` (tabs at the top) or just a filter chips row for the Prompts Screen? (I am proposing Tabs for a cleaner separation).
