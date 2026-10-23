#include "taskbar_badge.h"

#include <gdiplus.h>
#include <shobjidl.h>
#include <wrl/client.h>

#include <algorithm>
#include <string>

namespace {

HICON DrawBadge(int64_t count, int size) {
  Gdiplus::Bitmap bitmap(size, size, PixelFormat32bppARGB);
  Gdiplus::Graphics graphics(&bitmap);
  graphics.Clear(Gdiplus::Color(0, 0, 0, 0));
  graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
  graphics.SetTextRenderingHint(Gdiplus::TextRenderingHintAntiAliasGridFit);

  // Native OS chrome is independent of the application's accent/theme.
  Gdiplus::SolidBrush background(Gdiplus::Color(255, 194, 49, 47));
  Gdiplus::SolidBrush foreground(Gdiplus::Color(255, 255, 255, 255));
  const float extent = static_cast<float>(size);
  graphics.FillEllipse(&background, 0.0f, 0.0f, extent, extent);

  const std::wstring label = std::to_wstring(count);
  Gdiplus::FontFamily family(L"Segoe UI");
  Gdiplus::StringFormat format;
  format.SetAlignment(Gdiplus::StringAlignmentCenter);
  format.SetLineAlignment(Gdiplus::StringAlignmentCenter);
  format.SetFormatFlags(Gdiplus::StringFormatFlagsNoWrap);
  const Gdiplus::RectF bounds(0.0f, 0.0f, extent, extent);
  float font_size = extent * 0.75f;
  // Preserve the exact count, shrinking multi-digit labels to fit the badge.
  Gdiplus::Font measuring_font(&family, font_size, Gdiplus::FontStyleBold,
                               Gdiplus::UnitPixel);
  Gdiplus::RectF measured;
  graphics.MeasureString(label.c_str(), -1, &measuring_font,
                         Gdiplus::RectF(0.0f, 0.0f, 10000.0f, extent * 2.0f), &format,
                         &measured);
  if (measured.Width > extent * 0.9f) {
    font_size *= extent * 0.9f / measured.Width;
  }
  Gdiplus::Font font(&family, font_size, Gdiplus::FontStyleBold,
                     Gdiplus::UnitPixel);
  if (graphics.DrawString(label.c_str(), -1, &font, bounds, &format,
                          &foreground) != Gdiplus::Ok) {
    return nullptr;
  }
  HICON icon = nullptr;
  bitmap.GetHICON(&icon);
  return icon;
}

}  // namespace

bool SetTaskbarBadge(HWND window, int64_t count) {
  Microsoft::WRL::ComPtr<ITaskbarList3> taskbar;
  if (FAILED(CoCreateInstance(CLSID_TaskbarList, nullptr, CLSCTX_INPROC_SERVER,
                              IID_PPV_ARGS(taskbar.GetAddressOf()))) ||
      FAILED(taskbar->HrInit())) {
    return false;
  }
  if (count == 0) {
    return SUCCEEDED(taskbar->SetOverlayIcon(window, nullptr, L""));
  }
  Gdiplus::GdiplusStartupInput startup;
  ULONG_PTR token = 0;
  if (Gdiplus::GdiplusStartup(&token, &startup, nullptr) != Gdiplus::Ok) {
    return false;
  }
  // Render at least 32px for smooth downsampling, and scale for high DPI.
  const int size = std::max(32, MulDiv(16, static_cast<int>(GetDpiForWindow(window)), 96));
  HICON icon = DrawBadge(count, size);
  const std::wstring description = std::to_wstring(count);
  const bool success = icon && SUCCEEDED(
      taskbar->SetOverlayIcon(window, icon, description.c_str()));
  // Explorer copies the icon; all drawing resources can be released now.
  if (icon) DestroyIcon(icon);
  Gdiplus::GdiplusShutdown(token);
  return success;
}
