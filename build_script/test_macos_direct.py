"""Packaging must reject ad-hoc apps that dyld cannot load under Hardened Runtime."""
import contextlib
import io
import pathlib
import plistlib
import runpy
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


class DirectPackagingTest(unittest.TestCase):
    def test_required_entitlements_and_profile(self):
        required = {
            "com.apple.security.app-sandbox": True,
            "com.apple.security.files.bookmarks.app-scope": True,
            "com.apple.security.cs.disable-library-validation": True,
        }
        cases = [("valid", required, False, True)]
        for key in required:
            cases.append((key, {k: v for k, v in required.items() if k != key}, False, False))
        cases.append(("store profile", required, True, False))
        for name, entitlements, profile, expected in cases:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as root:
                app = pathlib.Path(root) / "Test.app"
                (app / "Contents").mkdir(parents=True)
                (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
                    "CFBundleIdentifier": "cn.joycai.joycaiImageAiToolkits.direct",
                    "CFBundleName": "Joycai Image AI Toolkits Direct",
                }))
                if profile:
                    (app / "Contents/embedded.provisionprofile").write_text("fixture")

                def run(args, **kwargs):
                    return subprocess.CompletedProcess(args, 0, stdout=plistlib.dumps(entitlements))

                with patch.object(sys, "argv", ["verify", str(app)]), patch(
                    "subprocess.run", side_effect=run
                ), contextlib.redirect_stdout(io.StringIO()):
                    script = pathlib.Path(__file__).with_name("verify_macos_direct.py")
                    if expected:
                        runpy.run_path(str(script), run_name="__main__")
                    else:
                        with self.assertRaises(SystemExit):
                            runpy.run_path(str(script), run_name="__main__")

    def test_rejects_shared_store_identity_or_install_name(self):
        for key, wrong in (
            ("CFBundleIdentifier", "cn.joycai.joycaiImageAiToolkits"),
            ("CFBundleName", "Joycai Image AI Toolkits"),
        ):
            with self.subTest(key=key), tempfile.TemporaryDirectory() as root:
                app = pathlib.Path(root) / "Test.app"
                (app / "Contents").mkdir(parents=True)
                info = {
                    "CFBundleIdentifier": "cn.joycai.joycaiImageAiToolkits.direct",
                    "CFBundleName": "Joycai Image AI Toolkits Direct",
                }
                info[key] = wrong
                (app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
                with patch.object(sys, "argv", ["verify", str(app)]):
                    with self.assertRaises(SystemExit):
                        runpy.run_path(str(pathlib.Path(__file__).with_name("verify_macos_direct.py")), run_name="__main__")


if __name__ == "__main__":
    unittest.main()
