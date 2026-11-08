#!/usr/bin/env python3
"""Build an isolated, unsigned Microsoft Store MSIX; never install or submit it."""
import argparse
import base64
import hashlib
import json
import os
import platform
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET
import zipfile

PINNED_FLUTTER = "3.47.8"
LANGUAGES = {"en-US", "zh-CN", "zh-TW", "ja-JP"}
CAPABILITIES = {"internetClient", "privateNetworkClientServer", "runFullTrust"}
MIN_OS = "10.0.17763.0"
PREPARATION = {
    "identity_name": "Joycai.StorePreparation",
    "publisher": "CN=Joycai Store Preparation",
    "publisher_display_name": "Joycai Store Preparation",
    "display_name": "Joycai Store Preparation",
    "previous_version": "first",
}
NS = {"p": "http://schemas.microsoft.com/appx/manifest/foundation/windows10"}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def require_safety_acceptance(preparation):
    # WIN-04: no route has completed content-safety acceptance yet. Keep this
    # reviewed-code gate until docs/testing/windows-store-ai-safety.md has evidence
    # for the final enabled routes. Identity alone cannot authorize a candidate.
    require(preparation,
            "WIN-04 content-safety acceptance is incomplete; only --preparation is available. "
            "See docs/testing/windows-store-ai-safety.md")


def version_tuple(value):
    require(isinstance(value, str) and re.fullmatch(r"\d+\.\d+\.\d+\.\d+", value),
            "Version must have four numeric components")
    parts = tuple(map(int, value.split(".")))
    require(0 < parts[0] <= 65535 and all(0 <= n <= 65535 for n in parts[1:]),
            "Version components are out of range")
    return parts


def validate_config(config, version, preparation=False):
    parts = version_tuple(version)
    require(parts[3] == 0, "The Store reserves the fourth version component; use zero")
    for key in PREPARATION:
        require(isinstance(config.get(key), str) and config[key].strip() == config[key]
                and config[key], f"Missing or invalid {key}")
        require(not any(ord(c) < 32 for c in config[key]), f"Control character in {key}")
    require(re.fullmatch(r"[A-Za-z0-9.-]{3,50}", config["identity_name"]),
            "Invalid package identity name")
    require(config["publisher"].startswith("CN="), "Expected Partner Center CN= publisher")
    for key in ("display_name", "publisher_display_name"):
        require(len(config[key]) <= 256, f"{key} exceeds 256 characters")
    if preparation:
        require(config == PREPARATION, "Preparation identity must be the fixed test identity")
    else:
        for key in ("publisher", "identity_name", "publisher_display_name", "display_name"):
            require(not re.search(r"testing|preparation|placeholder|example", config[key], re.I),
                    f"Test/placeholder value is forbidden in production {key}")
    previous = config["previous_version"]
    if previous != "first":
        require(parts > version_tuple(previous), "Version must exceed the highest Store version")


def verify_build_mode(cmake):
    matches = re.findall(r'"DART_DEFINES=([^"\r\n]*)"', cmake)
    require(len(matches) == 1, "Missing or ambiguous compiled Dart defines")
    defines = [base64.b64decode(x, validate=True).decode() for x in matches[0].split(",")]
    distribution = [x for x in defines if x.startswith("JOYCAI_DIRECT_DISTRIBUTION=")]
    require(distribution == ["JOYCAI_DIRECT_DISTRIBUTION=false"],
            "Build is not explicitly Store-configured")


def store_pubspec(pubspec, settings):
    # JSON flow mapping is valid YAML; avoids shell interpolation of publisher data.
    replacement = "msix_config: " + json.dumps(settings, ensure_ascii=True) + "\n"
    result, count = re.subn(r"(?m)^msix_config:[^\n]*\n(?:[ \t][^\n]*(?:\n|$)|\n)*",
                            lambda _: replacement, pubspec)
    require(count == 1, "Expected exactly one msix_config block")
    return result


def verify_package(package, config, version):
    with zipfile.ZipFile(package) as archive:
        names = {n.replace("\\", "/").lower() for n in archive.namelist()}
        require(not any(n.rsplit("/", 1)[-1] in {"dartjni.dll", "jvm.dll"} for n in names),
                "Windows package must not contain JNI/JVM libraries")
        require(not any(n.endswith((".pfx", ".p12", ".cer")) for n in names),
                "Package contains a certificate")
        require("appxsignature.p7x" not in names, "Store candidate must be unsigned")
        manifest = archive.read("AppxManifest.xml")
        root = ET.fromstring(manifest)
        identity = root.find("p:Identity", NS)
        require(identity is not None, "Missing package identity")
        for field, expected in {"Name": config["identity_name"], "Publisher": config["publisher"],
                                "Version": version, "ProcessorArchitecture": "x64"}.items():
            require(identity.get(field) == expected, f"Unexpected manifest {field}")
        for field, expected in {"DisplayName": config["display_name"],
                                "PublisherDisplayName": config["publisher_display_name"]}.items():
            require(root.findtext(f"p:Properties/p:{field}", namespaces=NS) == expected,
                    f"Unexpected {field}")
        languages = {e.get("Language") for e in root.findall("p:Resources/p:Resource", NS)}
        require(languages == LANGUAGES, "Package must declare all four supported languages")
        caps = root.find("p:Capabilities", NS)
        require(caps is not None and {e.get("Name") for e in caps} == CAPABILITIES,
                "Unexpected package capabilities")
        families = root.findall("p:Dependencies/p:TargetDeviceFamily", NS)
        require(len(families) == 1 and families[0].get("Name") == "Windows.Desktop"
                and families[0].get("MinVersion") == MIN_OS, "Unexpected OS requirements")
        apps = root.findall("p:Applications/p:Application", NS)
        require(len(apps) == 1 and apps[0].get("EntryPoint") == "Windows.FullTrustApplication",
                "Expected one full-trust desktop application")
        executable = apps[0].get("Executable", "").replace("\\", "/").lower()
        require(executable == "joycai_image_ai_toolkits.exe", "Unexpected executable")
        for name in (executable, "flutter_windows.dll", "sqlite3.dll", "data/app.so", "data/icudtl.dat",
                     "resources.pri", "msvcp140.dll", "vcruntime140.dll"):
            require(name in names, f"Missing runtime resource: {name}")
        logos = [root.findtext("p:Properties/p:Logo", namespaces=NS)]
        for node in root.iter():
            logos.extend(value for key, value in node.attrib.items()
                         if "Logo" in key or key == "Image")
        for logo in logos:
            require(logo, "Missing manifest image reference")
            name = logo.replace("\\", "/").lower()
            stem, extension = os.path.splitext(name)
            # MakePRI resolves the manifest's logical name to scale-qualified assets.
            require(name in names or f"{stem}.scale-100{extension}" in names,
                    f"Missing manifest image (including scale-100 fallback): {logo}")
        return manifest


def run(args, cwd, capture=False):
    print("Running: " + " ".join(map(str, args)), flush=True)
    return subprocess.run(args, cwd=cwd, check=True, text=True,
                          encoding="utf-8", errors="replace", capture_output=capture)


def stage_sources(root, staging):
    # Copy versioned source only. Never copy ignored build outputs, credentials,
    # local settings or independent .claude/worktrees checkouts.
    paths = run(["git", "ls-files", "-z"], root, True).stdout.split("\0")
    folders = {"lib", "assets", "windows", "test", "tool"}
    files = {"pubspec.yaml", "pubspec.lock", "analysis_options.yaml", "l10n.yaml", "dart_test.yaml"}
    untracked = run(["git", "ls-files", "--others", "--exclude-standard", "-z"], root, True).stdout.split("\0")
    require(not any(p and (Path(p).parts[0] in folders or p in files) for p in untracked),
            "Stage newly added application/test sources in Git before packaging")
    inventory = {}
    for relative in paths:
        path = Path(relative)
        if not relative or (path.parts[0] not in folders and relative not in files):
            continue
        source = root / path
        require(source.is_file() and not source.is_symlink(), f"Unavailable source: {relative}")
        require(source.resolve().is_relative_to(root), f"Source escapes repository: {relative}")
        target = staging / path
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        inventory[relative] = hashlib.sha256(target.read_bytes()).hexdigest()
    return inventory


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument("--preparation", action="store_true", help="Test identity; NOT for submission")
    modes.add_argument("--config", type=Path, help="Confirmed Partner Center identity JSON")
    parser.add_argument("--allow-sdk-mismatch", action="store_true",
                        help="Preparation only; record local SDK instead of enforcing CI pin")
    args = parser.parse_args()
    require_safety_acceptance(args.preparation)
    require(os.name == "nt", "Windows build host required")
    require(platform.machine().lower() in ("amd64", "x86_64"), "Use an x64 Windows build host")
    require(not args.allow_sdk_mismatch or args.preparation,
            "Production candidates require the pinned Flutter SDK")
    root = Path(__file__).resolve().parent.parent
    script_hash = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    source_revision = run(["git", "rev-parse", "HEAD"], root, True).stdout.strip()
    source_status = run(["git", "status", "--porcelain"], root, True).stdout
    config = PREPARATION.copy() if args.preparation else json.loads(args.config.read_text("utf-8"))
    pubspec = (root / "pubspec.yaml").read_text("utf-8")
    match = re.search(r"^version:\s*(\d+\.\d+\.\d+)(?:\+\d+)?\s*$", pubspec, re.M)
    require(match is not None, "Expected a stable pubspec version")
    version = match[1] + ".0"
    validate_config(config, version, args.preparation)
    flutter = shutil.which("flutter")
    dart = shutil.which("dart")
    require(flutter and dart, "Flutter and Dart must be on PATH")
    sdk = json.loads(run([flutter, "--version", "--machine"], root, True).stdout)
    require(sdk["frameworkVersion"] == PINNED_FLUTTER or args.allow_sdk_mismatch,
            f"Use Flutter {PINNED_FLUTTER}; preparation can explicitly allow a local SDK mismatch")
    output_root = root / "build" / "windows-store"
    output_root.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="preparation-" if args.preparation else "candidate-",
                                 dir=output_root))
    staging = work / "source"
    staging.mkdir()
    inventory = stage_sources(root, staging)
    artifacts = work / "artifacts"
    artifacts.mkdir()
    settings = {key: config[key] for key in ("identity_name", "publisher", "publisher_display_name", "display_name")}
    settings.update(store=True, sign_msix=False, install_certificate=False,
                    msix_version=version, architecture="x64", os_min_version=MIN_OS,
                    logo_path="assets/icon/icon.png", languages=",".join(sorted(LANGUAGES)),
                    capabilities="internetClient,privateNetworkClientServer",
                    output_path=str(artifacts), output_name="joycai-store-preparation" if args.preparation else "joycai-store")
    staged_pubspec = store_pubspec(pubspec, settings)
    (staging / "pubspec.yaml").write_text(staged_pubspec, encoding="utf-8")
    run([flutter, "pub", "get", "--enforce-lockfile"], staging)
    run([dart, "tool/merge_l10n.dart"], staging)
    run([flutter, "gen-l10n"], staging)
    tests = ["test/core/safety_settings_test.dart", "test/services/llm/safety_payload_test.dart",
             "test/screens/settings/safety_settings_section_test.dart"]
    run([flutter, "test", "--dart-define=JOYCAI_DIRECT_DISTRIBUTION=false", *tests], staging)
    run([flutter, "build", "windows", "--release",
         "--dart-define=JOYCAI_DIRECT_DISTRIBUTION=false"], staging)
    cmake = (staging / "windows/flutter/ephemeral/generated_config.cmake").read_text("utf-8")
    verify_build_mode(cmake)
    run([dart, "run", "msix:create", "--build-windows", "false"], staging)
    package = artifacts / (settings["output_name"] + ".msix")
    manifest = verify_package(package, config, version)
    (artifacts / "AppxManifest.xml").write_bytes(manifest)
    provenance = {
        "purpose": "preparation-only-not-for-submission" if args.preparation else "store-candidate-not-certified",
        "source_revision": source_revision,
        "source_status": source_status,
        "source_sha256": inventory, "flutter": sdk, "pinned_flutter": PINNED_FLUTTER,
        "dart_defines": ["JOYCAI_DIRECT_DISTRIBUTION=false"], "msix_config": settings,
        "previous_version": config["previous_version"],
        "package_sha256": hashlib.sha256(package.read_bytes()).hexdigest(),
        "build_script_sha256": script_hash,
        "native_acceptance": "not run", "wack": "not run",
    }
    (artifacts / "provenance.json").write_text(json.dumps(provenance, indent=2), encoding="utf-8")
    print(f"Verified unsigned package: {artifacts}")
    if args.preparation:
        print("PREPARATION ONLY. Do not submit this identity to the Store.")


if __name__ == "__main__":
    main()
