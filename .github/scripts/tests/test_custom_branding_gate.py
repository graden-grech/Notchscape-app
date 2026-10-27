"""Branding checks are separate from, and never replace, signing identity gates."""
import plistlib
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


class BrandingGateContractTests(unittest.TestCase):
    def test_security_and_contribution_routes_belong_to_notchscape(self):
        security = (ROOT / "SECURITY.md").read_text()
        self.assertIn("https://github.com/graden-grech/Notchscape-app/security/advisories/new", security)
        self.assertNotIn("TheBoredTeam", security)
        template = (ROOT / ".github/PULL_REQUEST.md").read_text()
        self.assertNotIn("crowdin.com/project/boring-notch", template)
        self.assertNotIn("target `dev`", template)

    def test_restart_uses_current_bundle_not_an_older_installed_copy(self):
        source = (ROOT / "Notchscape/helpers/ApplicationRelauncher.swift").read_text()
        self.assertIn("let appURL = Bundle.main.bundleURL", source)
        self.assertNotIn("urlForApplication(withBundleIdentifier:", source)

    def test_old_product_folders_and_assets_do_not_return(self):
        self.assertTrue((ROOT / "Notchscape.xcodeproj/project.pbxproj").is_file())
        self.assertTrue((ROOT / "Notchscape/NotchscapeApp.swift").is_file())
        self.assertTrue((ROOT / "NotchscapeHelper/NotchscapeHelper.swift").is_file())
        for old_path in ("boringNotch", "boringNotch.xcodeproj", "BoringNotchXPCHelper",
                         "Notchscape/Assets.xcassets/theboringteam.imageset",
                         "Notchscape/Assets.xcassets/logo2.imageset", "Notchscape/boring.m4a"):
            self.assertFalse((ROOT / old_path).exists(), old_path)

    def test_localized_product_names_use_current_brand(self):
        catalog = json.loads((ROOT / "Notchscape/Localizable.xcstrings").read_text())
        for key, entry in catalog["strings"].items():
            values = [key] + [local.get("stringUnit", {}).get("value", "")
                              for local in entry.get("localizations", {}).values()]
            for value in values:
                self.assertNotIn("Boring Notch", value)
                self.assertNotIn("boring.notch", value)
                self.assertNotIn("boring not.people", value)

    def test_publishers_target_notchscape_not_original_maintainers(self):
        for name in ("release.yml", "nightly.yml"):
            workflow = (ROOT / ".github/workflows" / name).read_text()
            self.assertNotIn("TheBoredTeam", workflow)
            self.assertNotIn("repositories: boring.notch", workflow)
            self.assertIn("repositories: Notchscape", workflow)
        release = (ROOT / ".github/workflows/release.yml").read_text()
        self.assertNotIn('"com.apple.quarantine"', release)
        self.assertIn("vars.ENABLE_HOMEBREW_TAP == 'true'", release)

    def test_signed_build_requires_both_branding_and_identity_gates(self):
        script = (ROOT / ".github/scripts/build_custom_signed_app.sh").read_text()
        self.assertIn("verify_custom_app_branding.sh", script)
        self.assertIn("verify_custom_app_identity.sh", script)
        self.assertLess(script.index("verify_custom_app_branding.sh"), script.index("verify_custom_app_identity.sh"))


@unittest.skipUnless(sys.platform == "darwin", "PlistBuddy gate runs on macOS")
class BrandingGateFixtureTests(unittest.TestCase):
    def run_fixture(self, built_name, display_name, bundle_name="Notchscape.app", executable="Notchscape"):
        with tempfile.TemporaryDirectory(prefix="notch-branding-test-") as temp:
            directory = Path(temp)
            source = directory / "source.plist"
            source.write_bytes(plistlib.dumps({"CFBundleName": "Notchscape", "CFBundleDisplayName": "Notchscape"}))
            app = directory / bundle_name
            (app / "Contents").mkdir(parents=True)
            (app / "Contents/MacOS").mkdir()
            binary = app / "Contents/MacOS" / executable
            binary.write_bytes(b"fixture")
            binary.chmod(0o755)
            (app / "Contents/Info.plist").write_bytes(plistlib.dumps({"CFBundleName": built_name, "CFBundleDisplayName": display_name, "CFBundleExecutable": executable}))
            return subprocess.run(["bash", str(ROOT / ".github/scripts/verify_custom_app_branding.sh"), str(app), str(source)], capture_output=True).returncode

    def test_matching_names_pass(self):
        self.assertEqual(self.run_fixture("Notchscape", "Notchscape"), 0)

    def test_stale_bundle_name_fails_even_with_new_display_name(self):
        self.assertNotEqual(self.run_fixture("Boring Notch", "Notchscape"), 0)

    def test_stale_display_name_fails(self):
        self.assertNotEqual(self.run_fixture("Notchscape", "Boring Notch"), 0)

    def test_old_app_filename_fails_even_with_new_display_names(self):
        self.assertNotEqual(self.run_fixture("Notchscape", "Notchscape", bundle_name="Boring Notch.app"), 0)

    def test_old_executable_name_fails(self):
        self.assertNotEqual(self.run_fixture("Notchscape", "Notchscape", executable="Boring Notch"), 0)
