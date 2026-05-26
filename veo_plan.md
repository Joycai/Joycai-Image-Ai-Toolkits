# Veo Video Generation Implementation Plan

This document outlines the plan for integrating Google's Veo video generation API into the Joycai Image AI Toolkits.

## 1. Core Changes (Models & Constants)

### `lib/core/constants.dart`
- Add `video` to `ModelTag` enum.
- Add `videoGenerate` to `TaskType` enum in `lib/services/task_queue_service.dart`.
- Define `VeoResolution` and `VeoAspectRatio` enums if they differ from existing ones (Veo supports 720p, 1080p, 4k and 9:16, 16:9).

### `lib/models/llm_model.dart`
- Ensure the `tag` property correctly handles the new `video` tag.

### `lib/models/llm_types.dart`
- Add `videoUri` and `operationName` to `LLMResponse` or create a specific `LLMVideoResponse`.
- Update `LLMAttachment` to support different reference types (asset, first frame, last frame).

## 2. Service Layer Extensions

### `lib/services/llm/llm_provider_interface.dart`
- Add a method for Long Running Operations (LRO):
  ```dart
  Future<String> startLongRunning(LLMModelConfig config, List<LLMMessage> history, {Map<String, dynamic>? options});
  Future<Map<String, dynamic>> checkOperation(LLMModelConfig config, String operationName);
  ```

### `lib/services/llm/providers/google_genai_provider.dart`
- Implement `predictLongRunning` targeting `${config.endpoint}/models/${config.modelId}:predictLongRunning`.
- Implement polling logic for `/v1beta/{operation_name}`.
- Add logic to parse `generatedSamples[0].video.uri`.
- Handle multi-image inputs for `referenceImages`, `image` (first frame), and `lastFrame`.

### `lib/services/task_queue_service.dart`
- Add `_executeVideoGenerateTask(TaskItem task)`:
  1. Call provider to start LRO.
  2. Enter a polling loop (e.g., every 10 seconds).
  3. Emit progress updates.
  4. Once `done: true`, download the video using the provided URI.
  5. Save the video to the output directory and update task results.

### `lib/services/llm/llm_service.dart`
- Add a wrapper for video generation requests to handle the LRO flow seamlessly for the UI.

## 3. UI Implementation (Workbench)

### `lib/state/app_state.dart`
- Add `videoModels` getter.
- Add state for video-specific parameters: `videoResolution`, `videoAspectRatio`, `firstFramePath`, `lastFramePath`, `referenceImagePaths`.
- Update `setWorkbenchTab` to support a new index (e.g., index 4 for Video).

### `lib/screens/workbench/workbench_screen.dart`
- Add a "Video" tab to the workbench navigation.
- Implement `VideoWorkbenchPanel` (New Widget).

### `lib/screens/workbench/widgets/video_config_panel.dart` (New)
- UI for selecting Veo models.
- Resolution and Aspect Ratio toggles.
- Image Drop targets for:
  - **Reference Images**: A list of images for style/content reference.
  - **First Frame**: For image-to-video (start).
  - **Last Frame**: For image-to-video (end/interpolation).
- "Generate Video" button.

### `lib/screens/workbench/widgets/video_preview_area.dart` (New)
- Display a video player for generated results.
- Recommend adding `video_player` or `chewie` package for inline playback.
- Fallback: "Open in System Player" button if a video is present but cannot be played inline.

## 4. Multi-device Adaptation

### Desktop
- **Layout**: Standard workbench layout with a dedicated Video tab. Settings panel on the right, large preview area in the center.
- **Interactions**: Drag and drop support for all frame/reference image slots.

### iPad / Tablet
- **Layout**: Use `Responsive` builder. In landscape, keep sidebar. In portrait, move settings to a collapsible bottom panel or a dedicated tab.
- **Interactions**: Touch-friendly image pickers for frame slots.

### Mobile
- **Layout**: Stacked layout. Settings sections at the bottom (scrollable or in a Modal Bottom Sheet). Large preview at the top.
- **Interactions**: Simplified UI focusing on text-to-video, with "Advanced" toggle for image references.

## 5. Implementation Phases

1.  **Phase 1 (Core)**: [DONE] Update enums, database schema (if needed), and basic `LLMService` plumbing.
    - [x] Add `video` to `ModelTag` enum in `lib/core/constants.dart`.
    - [x] Add `videoGenerate` to `TaskType` enum in `lib/services/task_queue_service.dart`.
    - [x] Define `VeoResolution` and `VeoAspectRatio` enums in `lib/core/constants.dart`.
    - [x] Update `LLMResponse` and `LLMAttachment` in `lib/services/llm/llm_types.dart`.
    - [x] Update `ILLMProvider` interface with LRO methods.
    - [x] Add `videoModels` getter in `AppState`.
2.  **Phase 2 (Provider)**: [DONE] Implement Veo API calling and polling in `GoogleGenAIProvider`.
    - [x] Implement `startLongRunning` and `checkOperation` in `GoogleGenAIProvider`.
    - [x] Implement `_prepareVeoPayload` with support for reference images and frames.
    - [x] Add LRO wrapper methods to `LLMService`.
    - [x] Add dummy LRO methods to `OpenAIAPIProvider` for compatibility.
3.  **Phase 3 (Task Queue)**: [DONE] Implement background video generation and downloading.
    - [x] Implement `_executeVideoGenerateTask` with LRO polling.
    - [x] Implement video file downloading with authentication support.
    - [x] Emit progress and result events for video tasks.
4.  **Phase 4 (UI)**: [DONE] Build the Video workbench tab and configuration panels.
    - [x] Add a "Video" tab to the workbench navigation.
    - [x] Implement `VideoWorkbenchView` (center panel).
    - [x] Implement `VideoConfigPanel` (sidebar).
    - [x] Update `WorkbenchScreen` to handle the new tab.
    - [x] Add localization for all video-related UI elements.
5.  **Phase 5 (Refinement)**: [DONE] Add video playback support and optimize for mobile/tablet.
    - [x] Integrate `video_player` for inline playback.
    - [x] Add "Open in System Player" fallback.
    - [x] Ensure responsive layout works for Video tab.

## 6. Dependencies to Consider
- `video_player` or `chewie`: For previewing generated videos within the app.
- `dio` or `http`: For downloading the video file from the URI returned by Veo. (Existing `http` is sufficient).
