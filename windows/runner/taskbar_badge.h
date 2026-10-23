#ifndef RUNNER_TASKBAR_BADGE_H_
#define RUNNER_TASKBAR_BADGE_H_

#include <windows.h>

#include <cstdint>

// Requires COM on the calling thread and an existing taskbar button.
// Zero removes the overlay. The caller retains the count for Explorer restarts.
bool SetTaskbarBadge(HWND window, int64_t count);

#endif  // RUNNER_TASKBAR_BADGE_H_
