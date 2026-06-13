# Release Notes - v2.2.0 (The Cinematic Update)

We are thrilled to announce version 2.2.0 of **Joycai Image AI Toolkits**, which introduces state-of-the-art AI video generation capabilities powered by Google Veo. Transform your images and text prompts into high-quality cinematic videos directly from the workbench.

## 🎥 Google Veo Integration
The app now integrates the Google Veo generative video model suite to provide three primary modes of video generation:
*   **Text-to-Video**: Generate stunning videos using rich natural language prompts.
*   **Image-to-Video (Reference asset)**: Guide the video style, characters, or assets using up to three reference images.
*   **Image-to-Video (Frame Interpolation)**: Seamlessly animate a transition by specifying both a starting frame and an ending frame (last frame).

## 🎛️ Dedicated Video Workbench Tab
A new dedicated workbench view is now available for managing all video creation workflows:
*   **Drag-and-Drop Image Slots**: Drag images from the gallery directly into the start frame, end frame, or reference asset slots.
*   **Floating Video Player**: Preview generated videos immediately with our floating, non-obtrusive `VideoWorkbenchOverlay` player.
*   **Configurable Parameters**: Control resolution (720p, 1080p, 4k) and aspect ratios (16:9, 9:16) with ease.
*   **Persistent Preferences**: Video configurations are automatically saved to the local SQLite database so you can resume your projects between sessions.

## ⚙️ Long-Running Operation (LRO) Engine
Because high-quality video generation takes time, we've designed an asynchronous execution queue:
*   **Polling Loop**: The task queue submits the request to the Google API and polls the LRO status in the background.
*   **Automated Downloader**: Once the generation completes, the background queue automatically downloads the final `.mp4` file and places it directly into your project's gallery directory.
*   **OpenAI Provider Compatibility**: Added simulated LRO support to OpenAI channel configurations to mock and test video generation pathways.

---
*v2.2.0 brings cinematic motion to your AI toolkit. We look forward to seeing your moving creations!*
