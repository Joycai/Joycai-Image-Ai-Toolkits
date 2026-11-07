#include "windows_store_host.h"
#include <windows.h>
#include <appmodel.h>
#include <shlobj.h>
#include <wincrypt.h>

std::optional<std::vector<uint8_t>> ProtectWindowsSecret(
    const std::vector<uint8_t>& input, bool decrypt) {
  if (input.empty() || input.size() > 1024 * 1024) return std::nullopt;
  DATA_BLOB source{static_cast<DWORD>(input.size()),
                   const_cast<BYTE*>(input.data())};
  // Domain separation, not a secret or a replacement for user-scoped DPAPI.
  const char context[] = "Joycai.Windows.Credentials.v1";
  DATA_BLOB entropy{sizeof(context),
                    reinterpret_cast<BYTE*>(const_cast<char*>(context))};
  DATA_BLOB output{};
  const BOOL ok = decrypt
      ? CryptUnprotectData(&source, nullptr, &entropy, nullptr, nullptr,
                           CRYPTPROTECT_UI_FORBIDDEN, &output)
      : CryptProtectData(&source, L"Joycai credentials", &entropy, nullptr,
                         nullptr, CRYPTPROTECT_UI_FORBIDDEN, &output);
  if (!ok) return std::nullopt;
  std::vector<uint8_t> result(output.pbData, output.pbData + output.cbData);
  SecureZeroMemory(output.pbData, output.cbData);
  LocalFree(output.pbData);
  return result;
}

std::optional<std::string> WindowsPackageDataPath() {
  UINT32 length = 0;
  if (GetCurrentPackageFamilyName(&length, nullptr) != ERROR_INSUFFICIENT_BUFFER) {
    return std::nullopt;
  }
  std::vector<wchar_t> family(length);
  if (GetCurrentPackageFamilyName(&length, family.data()) != ERROR_SUCCESS) {
    return std::nullopt;
  }
  PWSTR local = nullptr;
  if (FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData,
                                 KF_FLAG_NO_PACKAGE_REDIRECTION, nullptr, &local))) {
    return std::nullopt;
  }
  const std::wstring path = std::wstring(local) + L"\\Packages\\" +
                            family.data() + L"\\LocalState\\Joycai";
  CoTaskMemFree(local);
  const int bytes = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, path.data(),
                                       static_cast<int>(path.size()), nullptr, 0,
                                       nullptr, nullptr);
  if (bytes <= 0) return std::nullopt;
  std::string result(bytes, '\0');
  if (!WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, path.data(),
                           static_cast<int>(path.size()), result.data(), bytes,
                           nullptr, nullptr)) return std::nullopt;
  return result;
}
