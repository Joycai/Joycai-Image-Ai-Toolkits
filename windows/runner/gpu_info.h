#ifndef RUNNER_GPU_INFO_H_
#define RUNNER_GPU_INFO_H_

#include <optional>
#include <string>

// Name of the graphics adapter this process actually renders on, UTF-8, or
// nullopt when the graphics stack could not be asked. See gpu_info.cpp for why
// this is a measurement rather than a reading of the preference registry.
std::optional<std::string> ActiveGpuName();

#endif  // RUNNER_GPU_INFO_H_
