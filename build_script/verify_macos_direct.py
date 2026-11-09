#!/usr/bin/env python3
"""Require a sandboxed non-Store app before direct-download packaging."""
import pathlib
import plistlib
import subprocess
import sys

app = pathlib.Path(sys.argv[1])
subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
result = subprocess.run(
    ["codesign", "-d", "--entitlements", ":-", str(app)],
    check=True, capture_output=True,
)
entitlements = plistlib.loads(result.stdout) if result.stdout.strip() else {}
for key in ("com.apple.security.app-sandbox", "com.apple.security.files.bookmarks.app-scope"):
    if entitlements.get(key) is not True:
        sys.exit(f"Direct distribution must enable {key}")
if (app / "Contents/embedded.provisionprofile").exists():
    sys.exit("Direct distribution must not contain a provisioning profile")
print("Verified direct-download package: App Sandbox enabled, no provisioning profile")
