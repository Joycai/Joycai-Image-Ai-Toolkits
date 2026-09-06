#include "gpu_info.h"

#include <d3d11.h>
#include <dxgi.h>
#include <windows.h>
#include <wrl/client.h>

#include "utils.h"

namespace {

using Microsoft::WRL::ComPtr;

std::optional<std::string> QueryActiveGpuName() {
  // A null adapter means "whatever Windows picks for this process". That is
  // the same call the engine's ANGLE device makes, and it is the point at
  // which Windows applies the per-app graphics preference — so the adapter
  // that comes back is the one Flutter is drawing on, not an inference from
  // the registry. (Reading UserGpuPreferences instead would report a wish:
  // it says nothing when the entry is absent, and still names a discrete GPU
  // that has since been disabled or removed.)
  ComPtr<ID3D11Device> device;
  if (FAILED(::D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, 0,
                                 nullptr, 0, D3D11_SDK_VERSION, &device,
                                 nullptr, nullptr))) {
    return std::nullopt;
  }

  ComPtr<IDXGIDevice> dxgi_device;
  if (FAILED(device.As(&dxgi_device))) {
    return std::nullopt;
  }
  ComPtr<IDXGIAdapter> adapter;
  if (FAILED(dxgi_device->GetAdapter(&adapter))) {
    return std::nullopt;
  }
  DXGI_ADAPTER_DESC desc = {};
  if (FAILED(adapter->GetDesc(&desc))) {
    return std::nullopt;
  }

  std::string name = Utf8FromUtf16(desc.Description);
  if (name.empty()) {
    return std::nullopt;
  }
  return name;
}

}  // namespace

std::optional<std::string> ActiveGpuName() {
  // The adapter is fixed for the life of the process and asking costs a device
  // creation, so the first answer is the only one taken.
  static const std::optional<std::string> cached = QueryActiveGpuName();
  return cached;
}
