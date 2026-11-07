#include "../runner/windows_store_host.h"
#include <fcntl.h>
#include <io.h>
#include <iostream>
#include <iterator>

int main(int argc, char* argv[]) {
  // Binary stdin/stdout bridge allows Dart database tests to use the production
  // DPAPI implementation with synthetic secrets, never command-line secrets.
  if (argc == 2) {
    const std::string mode(argv[1]);
    if (mode != "seal" && mode != "open") return 2;
    _setmode(_fileno(stdin), _O_BINARY);
    _setmode(_fileno(stdout), _O_BINARY);
    const std::vector<uint8_t> input{std::istreambuf_iterator<char>(std::cin), {}};
    const auto output = ProtectWindowsSecret(input, mode == "open");
    if (!output) return 1;
    std::cout.write(reinterpret_cast<const char*>(output->data()), output->size());
    return 0;
  }
  const std::vector<uint8_t> input{'s', 'y', 'n', 't', 'h', 'e', 't', 'i', 'c'};
  const auto first = ProtectWindowsSecret(input, false);
  const auto second = ProtectWindowsSecret(input, false);
  if (!first || !second || *first == *second || *first == input) return 1;
  const auto plain = ProtectWindowsSecret(*first, true);
  if (!plain || *plain != input) return 1;
  auto corrupt = *first;
  corrupt.back() ^= 1;
  if (ProtectWindowsSecret(corrupt, true)) return 1;
  if (ProtectWindowsSecret({}, true)) return 1;
  std::cout << "DPAPI round-trip, randomized rotation, tamper and empty input checks passed\n";
  std::cout << "Package storage: " << (WindowsPackageDataPath() ? "available" : "unpackaged/unavailable") << "\n";
  return 0;
}
