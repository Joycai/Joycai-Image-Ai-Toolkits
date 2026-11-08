"""Negative release checks using synthetic packages; no SDK or app launch needed."""
import base64
import copy
import io
import json
import subprocess
import sys
import unittest
import zipfile

import build_windows_store as store


class StoreValidationTest(unittest.TestCase):
    def test_unresolved_safety_blocks_candidate_but_not_preparation(self):
        store.require_safety_acceptance(True)
        with self.assertRaisesRegex(ValueError, "WIN-04"):
            store.require_safety_acceptance(False)

    def test_candidate_cli_stops_before_reading_identity_or_invoking_sdk(self):
        result = subprocess.run(
            [sys.executable, store.__file__, "--config", "missing-identity.json"],
            capture_output=True, text=True, check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("WIN-04 content-safety acceptance is incomplete", result.stderr)
        self.assertNotIn("Running:", result.stdout)

    def test_temporary_config_preserves_other_yaml_sections(self):
        source = 'name: joycai\nmsix_config:\n  store: false\n  publisher: old\n\nnext_section:\n  keep: true\n'
        settings = {"store": True, "publisher": 'CN=Name & "Co"'}
        result = store.store_pubspec(source, settings)
        self.assertTrue(result.startswith("name: joycai\n"))
        self.assertTrue(result.endswith("next_section:\n  keep: true\n"))
        self.assertEqual(json.loads(result.splitlines()[1].removeprefix("msix_config: ")), settings)
        with self.assertRaises(ValueError):
            store.store_pubspec("name: joycai\n", settings)

    def test_versions_and_identity(self):
        config = dict(store.PREPARATION)
        store.validate_config(config, "4.31.8.0", preparation=True)
        with self.assertRaisesRegex(ValueError, "Test/placeholder"):
            store.validate_config(config, "4.31.8.0")
        config.update(identity_name="12345.Joycai", publisher="CN=12345678-1234-1234-1234-123456789abc",
                      display_name="Joycai", publisher_display_name="Joycai", previous_version="4.31.7.9")
        store.validate_config(config, "4.31.8.0")
        for version in ("4.31.8.1", "4.31.7.0", "0.1.0.0", "4.65536.0.0", "4.31.8"):
            with self.subTest(version=version), self.assertRaises(ValueError):
                store.validate_config(config, version)
        config["previous_version"] = "4.31.8.0"
        with self.assertRaisesRegex(ValueError, "exceed"):
            store.validate_config(config, "4.31.8.0")

    def test_rejects_missing_direct_and_duplicate_build_flags(self):
        for values in ([], ["JOYCAI_DIRECT_DISTRIBUTION=true"],
                       ["JOYCAI_DIRECT_DISTRIBUTION=false", "JOYCAI_DIRECT_DISTRIBUTION=true"]):
            encoded = ",".join(base64.b64encode(v.encode()).decode() for v in values)
            with self.subTest(values=values), self.assertRaises(ValueError):
                store.verify_build_mode(f'"DART_DEFINES={encoded}"')
        encoded = base64.b64encode(b"JOYCAI_DIRECT_DISTRIBUTION=false").decode()
        store.verify_build_mode(f'"DART_DEFINES={encoded}"')
        with self.assertRaises(ValueError):
            store.verify_build_mode("")

    def fixture(self):
        languages = "".join(f'<Resource Language="{lang}"/>' for lang in sorted(store.LANGUAGES))
        caps = "".join(f'<Capability Name="{cap}"/>' for cap in sorted(store.CAPABILITIES))
        manifest = f'''<Package xmlns="{store.NS['p']}">
          <Identity Name="Joycai.StorePreparation" Publisher="CN=Joycai Store Preparation"
            Version="4.31.8.0" ProcessorArchitecture="x64"/>
          <Properties><DisplayName>Joycai Store Preparation</DisplayName>
            <PublisherDisplayName>Joycai Store Preparation</PublisherDisplayName>
            <Logo>Images/StoreLogo.png</Logo></Properties>
          <Resources>{languages}</Resources><Capabilities>{caps}</Capabilities>
          <Dependencies><TargetDeviceFamily Name="Windows.Desktop" MinVersion="{store.MIN_OS}"/></Dependencies>
          <Applications><Application Executable="joycai_image_ai_toolkits.exe"
            EntryPoint="Windows.FullTrustApplication"/></Applications></Package>'''
        files = {name: b"fixture" for name in (
            "joycai_image_ai_toolkits.exe", "flutter_windows.dll", "sqlite3.dll", "data/app.so", "data/icudtl.dat",
            "resources.pri", "msvcp140.dll", "vcruntime140.dll", "Images/StoreLogo.png")}
        files["AppxManifest.xml"] = manifest.encode()
        return files

    def verify(self, files):
        package = io.BytesIO()
        with zipfile.ZipFile(package, "w") as archive:
            for name, content in files.items():
                archive.writestr(name, content)
        package.seek(0)
        store.verify_package(package, store.PREPARATION, "4.31.8.0")

    def test_package_and_rejects_manifest_or_payload_mismatch(self):
        original = self.fixture()
        self.verify(original)
        qualified = copy.copy(original)
        qualified["Images/StoreLogo.scale-100.png"] = qualified.pop("Images/StoreLogo.png")
        self.verify(qualified)
        for old, new in ((b"4.31.8.0", b"4.31.7.0"), (b'Architecture="x64"', b'Architecture="arm64"'),
                         (b"CN=Joycai Store Preparation", b"CN=Msix Testing"),
                         (b'Language="ja-JP"', b'Language="fr-FR"'),
                         (b"runFullTrust", b"broadFileSystemAccess")):
            files = copy.copy(original)
            files["AppxManifest.xml"] = files["AppxManifest.xml"].replace(old, new)
            with self.subTest(old=old), self.assertRaises(ValueError):
                self.verify(files)
        for missing in ("flutter_windows.dll", "sqlite3.dll", "Images/StoreLogo.png", "data/app.so"):
            files = copy.copy(original)
            del files[missing]
            with self.subTest(missing=missing), self.assertRaises(ValueError):
                self.verify(files)
        for forbidden in ("test_certificate.pfx", "AppxSignature.p7x"):
            files = copy.copy(original)
            files[forbidden] = b"fixture"
            with self.subTest(forbidden=forbidden), self.assertRaises(ValueError):
                self.verify(files)

    def test_rejects_jni_and_jvm_even_in_nested_or_mixed_case_paths(self):
        for name in ("dartjni.dll", "jvm.dll", "plugins/DartJNI.DLL", "runtime\\JVM.dll"):
            files = self.fixture()
            files[name] = b"fixture"
            with self.subTest(name=name), self.assertRaisesRegex(ValueError, "JNI/JVM"):
                self.verify(files)

    def test_sqlite_must_be_beside_the_executable(self):
        files = self.fixture()
        files["native_assets/sqlite3.dll"] = files.pop("sqlite3.dll")
        with self.assertRaisesRegex(ValueError, "Missing runtime resource: sqlite3.dll"):
            self.verify(files)


if __name__ == "__main__":
    unittest.main()
