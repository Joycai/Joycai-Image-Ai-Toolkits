# Testing Strategy

This document outlines the testing strategy for the Joycai Image AI Toolkits.

## Unit & Widget Tests

We use the standard `flutter_test` package.

### Configuration
- **Database:** We use `sqflite_common_ffi` to mock the SQLite database for desktop environments during tests.
- **Screen Size:** Tests are configured with a resolution of 1920x1080 to simulate a desktop environment and prevent layout overflows that would not occur in the actual application.
- **State Management:** `AppState` is provided via `ChangeNotifierProvider` in the test widget tree.

### Running Tests
To run the tests:
```bash
flutter test
```

## Manual Verification
- **Build:** Always ensure the app compiles for the target platform (Windows).
  ```bash
  flutter build windows --debug
  ```
