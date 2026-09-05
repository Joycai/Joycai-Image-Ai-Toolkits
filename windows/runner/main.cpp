#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>

#include "flutter_window.h"
#include "utils.h"

namespace {

// Where Windows keeps its per-app GPU choice: one string value per exe path,
// written by Settings > Display > Graphics and by this app's own
// "Prefer high-performance GPU" toggle (lib/services/gpu_preference_service.dart).
constexpr wchar_t kGpuPreferenceKey[] =
    L"Software\\Microsoft\\DirectX\\UserGpuPreferences";

std::wstring GetExecutablePath() {
  std::wstring path(MAX_PATH, L'\0');
  while (true) {
    const DWORD length =
        ::GetModuleFileName(nullptr, path.data(), static_cast<DWORD>(path.size()));
    if (length == 0) {
      return std::wstring();
    }
    // A truncated path fills the buffer exactly; anything shorter is complete.
    if (length < path.size()) {
      path.resize(length);
      return path;
    }
    path.resize(path.size() * 2);
  }
}

// Which adapter to render on. The default is the low-power one: on a hybrid
// machine the display is usually driven by the integrated GPU, and rendering on
// the discrete card then pays a cross-adapter copy for every frame. Users who
// want the dedicated card turn the setting on, which records GpuPreference=2
// for this exe; the Windows graphics page writes the same entry, so a choice
// made in either place is honoured here.
flutter::GpuPreference GetGpuPreference() {
  const std::wstring exe_path = GetExecutablePath();
  if (exe_path.empty()) {
    return flutter::GpuPreference::LowPowerPreference;
  }

  wchar_t value[256] = {};
  DWORD size = sizeof(value);
  if (::RegGetValue(HKEY_CURRENT_USER, kGpuPreferenceKey, exe_path.c_str(),
                    RRF_RT_REG_SZ, nullptr, value, &size) != ERROR_SUCCESS) {
    return flutter::GpuPreference::LowPowerPreference;
  }

  // The data reads like "GpuPreference=2;", sometimes with further tokens the
  // Settings page appends. 2 is "High performance" in that page's terms.
  return ::wcsstr(value, L"GpuPreference=2") != nullptr
             ? flutter::GpuPreference::HighPerformancePreference
             : flutter::GpuPreference::LowPowerPreference;
}

}  // namespace

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

  project.set_gpu_preference(GetGpuPreference());

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
