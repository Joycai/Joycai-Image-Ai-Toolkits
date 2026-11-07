#ifndef RUNNER_WINDOWS_STORE_HOST_H_
#define RUNNER_WINDOWS_STORE_HOST_H_
#include <cstdint>
#include <optional>
#include <string>
#include <vector>

// User-scoped DPAPI; no machine-wide key, UI, or plaintext fallback.
std::optional<std::vector<uint8_t>> ProtectWindowsSecret(
    const std::vector<uint8_t>& input, bool decrypt);
std::optional<std::string> WindowsPackageDataPath();
#endif
