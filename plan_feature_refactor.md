### Feature Plan: Refactor Model Management & Fee Usage

**Objective:**
Refactor the model management system to support multiple providers (channels) for the same Model ID, decouple fee configuration into "Fee Groups", and redesign the Model Management and Usage screens for better usability.

**Proposed Changes:**

1.  **Database Schema Update (`lib/services/database_service.dart`):**
    *   **Create Table `fee_groups`:**
        *   `id` (INTEGER PK AUTOINCREMENT)
        *   `name` (TEXT)
        *   `billing_mode` (TEXT: 'token' or 'request')
        *   `input_price` (REAL)
        *   `output_price` (REAL)
        *   `request_price` (REAL)
    *   **Alter Table `llm_models`:**
        *   Add column `fee_group_id` (INTEGER, FK to `fee_groups.id`).
        *   *Note:* We will deprecate/ignore the existing fee columns (`input_fee`, etc.) in favor of the new relation, or migrate data and then ignore them.
        *   Ensure `model_id` is NOT unique (SQLite by default allows duplicates unless `UNIQUE` constraint is set. If set, we need to drop/recreate table or remove index). *Action:* Check if constraint exists, if so, migrate.
    *   **Alter Table `token_usage`:**
        *   Add column `model_instance_id` (INTEGER) to reference the specific `llm_models.id`.
        *   Migrate existing data to link to the first matching model ID if possible.

2.  **Logic & Backend Updates:**
    *   **`LLMService` (`lib/services/llm/llm_service.dart`):**
        *   Update logic to fetch model configurations by internal `id` (PK) when executing tasks, rather than string `model_id`.
        *   Update cost calculation to look up the `fee_group` associated with the model.
    *   **`AppState` & `TaskQueueService`:**
        *   Ensure task submissions pass the full model object or internal ID to the queue, not just the string ID.

3.  **UI Redesign - Models Screen (`lib/screens/models/models_screen.dart`):**
    *   **Grouped View:** Display models grouped by Channel (e.g., "Google GenAI (Free)", "Google GenAI (Paid)", "OpenAI API").
    *   **Direct Add:** Provide "Add Model" action specific to a channel (pre-filling Type and Paid status).
    *   **Add/Edit Dialog:**
        *   Remove Fee fields.
        *   Add "Fee Group" dropdown selection.
        *   Add visual tags for `chat`, `image`, `multimodal` with distinct colors.

4.  **UI Redesign - Usage Screen (`lib/screens/metrics/token_usage_screen.dart`):**
    *   Add a new tab or section for **"Fee Configuration"**.
    *   **Fee Groups Manager:** CRUD for `fee_groups`.
    *   **Usage Report:** Update report to aggregate costs by `Fee Group`. Individual model rows show Token/Request counts but cost is derived from group.

5.  **Localization:**
    *   Add new strings for "Fee Groups", "Channels", "Group Name", "Price Config", etc.

**Migration Strategy:**
*   On app start (DB init), create a default "Default Fee Group" and migrate existing models' fee settings into it (or create unique groups for each model to preserve custom pricing).
*   For now, we will create one group per model to preserve exact pricing, or user can consolidate later.

**Verification Plan:**
*   **Database:** Verify tables `fee_groups` exists and `llm_models` has `fee_group_id`.
*   **Models Screen:** Verify grouping works. Verify adding 2 models with same ID (e.g., `gemini-pro`) but different types works.
*   **Usage Screen:** Create a Fee Group. Assign it to a model. Run a task. Verify cost is calculated based on the group's rate.

**Questions:**
*   Should I migrate existing fees by creating one Fee Group per model (to preserve data exactly) or just create one default group and reset everyone? (Plan: One group per model to be safe).
