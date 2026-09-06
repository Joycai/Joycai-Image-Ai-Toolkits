#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  // No set_gpu_preference call on purpose: the project defaults to
  // NoPreference, which leaves the adapter choice to Windows. It applies the
  // per-app entry under HKCU\Software\Microsoft\DirectX\UserGpuPreferences
  // (Settings > System > Display > Graphics) to the engine's device the same
  // way it does to any other process, so that page is the one place the choice
  // is made. The app used to force LowPowerPreference and carry a toggle that
  // wrote that registry entry itself; both are gone, and the settings pane now
  // only reports which adapter the choice landed on (see gpu_info.cpp).

  // Impeller (OpenGLESSDF) cannot import the DXGI shared-handle textures
  // video_player_win publishes, so every video frame fails with "Could not
  // create external texture" and the player draws black while audio and the
  // position keep running. Skia renders the same textures fine, so the video
  // preview is what pins the renderer here; drop this once the engine can
  // import them.
  project.set_impeller_switch(flutter::ImpellerSwitch::Disabled);

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Joycai Image AI Toolkits", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
