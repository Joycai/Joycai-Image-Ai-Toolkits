"""Exercise the Windows native-asset install rule without compiling Flutter."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class WindowsNativeAssetsTest(unittest.TestCase):
    def test_clean_configure_installs_assets_created_later(self):
        cmake = os.environ.get("CMAKE") or shutil.which("cmake")
        if not cmake:
            self.skipTest("CMake is required for the native-asset install regression")
        source = (Path(__file__).resolve().parents[1] / "windows/CMakeLists.txt").read_text()
        rule = 'set(NATIVE_ASSETS_DIR' + source.split('set(NATIVE_ASSETS_DIR', 1)[1].split(
            "# Fully re-copy", 1)[0]
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            assets = root / "flutter-build/native_assets/windows"
            bundle = root / "bundle"
            (root / "CMakeLists.txt").write_text(
                'cmake_minimum_required(VERSION 3.14)\nproject(AssetInstall NONE)\n'
                f'set(PROJECT_BUILD_DIR "{root.as_posix()}/flutter-build/")\n'
                f'set(INSTALL_BUNDLE_LIB_DIR "{bundle.as_posix()}")\n' + rule)
            self.assertFalse(assets.exists())
            configured = subprocess.run(
                [cmake, "-S", str(root), "-B", str(root / "cmake-build")],
                capture_output=True, text=True)
            self.assertEqual(configured.returncode, 0, configured.stdout + configured.stderr)
            # Flutter's build hook runs only after CMake has configured.
            assets.mkdir(parents=True)
            payload = b"native SQLite fixture"
            (assets / "sqlite3.dll").write_bytes(payload)
            installed = subprocess.run(
                [cmake, "--install", str(root / "cmake-build"), "--component", "Runtime"],
                capture_output=True, text=True)
            self.assertEqual(installed.returncode, 0, installed.stdout + installed.stderr)
            self.assertEqual((bundle / "sqlite3.dll").read_bytes(), payload)


if __name__ == "__main__":
    unittest.main()
