#include "flutter_window.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {

// Channel the Dart side uses to keep the OS title bar in step with the theme
// the user picked inside the app. See WindowChromeService on the Dart side.
constexpr const char kWindowChromeChannel[] = "joycai/window_chrome";

// Flutter hands colours over as ARGB ints; DwmSetWindowAttribute wants a
// COLORREF, which orders the same bytes backwards and has no alpha.
COLORREF ToColorRef(int32_t argb) {
  return RGB((argb >> 16) & 0xFF, (argb >> 8) & 0xFF, argb & 0xFF);
}

// The engine's Windows accessibility bridge is constructed lazily, the first
// time a client asks the Flutter view for an accessibility object via
// WM_GETOBJECT. From then on every semantics update is mirrored into a
// ui::AXTree, and that mirror desyncs when an overlay route (dropdown menu,
// tooltip) is torn down while its dismiss animation is still running, or when
// the semantics tree is rebuilt during a resize. The symptom is a stream of
//   Failed to update ui::AXTree, error: N will not be in the tree and is not
//   the new root
// followed, often, by the process going down. Upstream: flutter/flutter#182444
// and #100610, still open as of Flutter 3.44.
//
// No screen reader is needed to trigger it: launching from an IDE that loads
// the Java Access Bridge (IntelliJ IDEA / Android Studio) is enough for
// something to probe the window, which is why it shows up in development.
//
// Swallowing WM_GETOBJECT on the Flutter view means the bridge is never built,
// so there is no AXTree to desync. Trade-off: screen readers cannot introspect
// the Flutter content. Remove this once the upstream fix lands.
WNDPROC g_original_view_proc = nullptr;

LRESULT CALLBACK ViewWndProc(HWND hwnd, UINT message, WPARAM wparam,
                             LPARAM lparam) {
  if (message == WM_GETOBJECT) {
    return 0;
  }
  return CallWindowProc(g_original_view_proc, hwnd, message, wparam, lparam);
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  HWND view_window = flutter_controller_->view()->GetNativeWindow();
  SetChildContent(view_window);

  // See ViewWndProc above: keep the accessibility bridge from ever activating.
  g_original_view_proc = reinterpret_cast<WNDPROC>(SetWindowLongPtr(
      view_window, GWLP_WNDPROC, reinterpret_cast<LONG_PTR>(ViewWndProc)));

  window_chrome_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kWindowChromeChannel,
          &flutter::StandardMethodCodec::GetInstance());
  window_chrome_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() != "setCaptionColors") {
          result->NotImplemented();
          return;
        }

        const auto* args =
            std::get_if<flutter::EncodableMap>(call.arguments());
        if (!args) {
          result->Error("bad_args", "Expected a map of caption colours");
          return;
        }

        auto read_int = [&](const char* key, int32_t* out) {
          auto it = args->find(flutter::EncodableValue(key));
          if (it == args->end()) {
            return false;
          }
          const auto* value = std::get_if<int32_t>(&it->second);
          if (!value) {
            return false;
          }
          *out = *value;
          return true;
        };

        int32_t caption = 0;
        int32_t text = 0;
        if (!read_int("caption", &caption) || !read_int("text", &text)) {
          result->Error("bad_args", "caption and text must be ARGB ints");
          return;
        }

        bool dark = false;
        auto dark_it = args->find(flutter::EncodableValue("dark"));
        if (dark_it != args->end()) {
          if (const auto* value = std::get_if<bool>(&dark_it->second)) {
            dark = *value;
          }
        }

        SetCaptionColors(ToColorRef(caption), ToColorRef(text), dark);
        result->Success();
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Blocked on the view window too (see ViewWndProc). The engine also answers
  // WM_GETOBJECT for the top-level window through HandleTopLevelWindowProc, so
  // it has to be swallowed here as well, before the controller sees it.
  if (message == WM_GETOBJECT) {
    return 0;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
