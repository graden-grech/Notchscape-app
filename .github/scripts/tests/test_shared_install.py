import importlib.util
import os
from pathlib import Path
import plistlib
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / ".github/scripts/verify_shared_install.py"
SPEC = importlib.util.spec_from_file_location("shared_install", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class SharedInstallTests(unittest.TestCase):
    def fixture(self):
        directory = tempfile.TemporaryDirectory(prefix="notchscape-shared-test-")
        self.addCleanup(directory.cleanup)
        app = Path(directory.name) / "Notchscape.app"
        binary = app / "Contents/MacOS/Notchscape"
        binary.parent.mkdir(parents=True)
        binary.write_bytes(b"isolated permission fixture, not an executable")
        for path in [app, app / "Contents", binary.parent, binary]:
            path.chmod(0o755)
        resource = app / "Contents/Info.plist"
        resource.write_bytes(plistlib.dumps({"fixture": True}))
        resource.chmod(0o644)
        return app

    def test_shared_bundle_passes(self):
        report = MODULE.validate_app(self.fixture())
        self.assertTrue(report["otherLocalUsersCanReadAndExecute"])
        self.assertEqual(report["sharedInstallPath"], "/Applications/Notchscape.app")

    def test_owner_only_directory_fails(self):
        app = self.fixture()
        (app / "Contents").chmod(0o700)
        with self.assertRaises(ValueError): MODULE.validate_app(app)

    def test_owner_only_resource_fails(self):
        app = self.fixture()
        (app / "Contents/Info.plist").chmod(0o600)
        with self.assertRaises(ValueError): MODULE.validate_app(app)

    def test_owner_only_executable_fails(self):
        app = self.fixture()
        (app / "Contents/MacOS/Notchscape").chmod(0o744)
        with self.assertRaises(ValueError): MODULE.validate_app(app)

    def test_world_writable_content_fails(self):
        app = self.fixture()
        (app / "Contents/Info.plist").chmod(0o666)
        with self.assertRaises(ValueError): MODULE.validate_app(app)

    def test_external_symlink_fails_but_internal_link_passes(self):
        app = self.fixture()
        link = app / "Contents/metadata-link"
        link.symlink_to("Info.plist")
        MODULE.validate_app(app)
        link.unlink()
        link.symlink_to("/Applications")
        with self.assertRaises(ValueError): MODULE.validate_app(app)

    def test_installer_can_only_target_shared_applications(self):
        dist = ET.parse(ROOT / "Configuration/installer/Distribution.xml").getroot()
        self.assertEqual(dist.find("domains").attrib, {"enable_localSystem": "true",
            "enable_currentUserHome": "false", "enable_anywhere": "false"})
        self.assertEqual(dist.find("options").get("require-scripts"), "false")
        os_gate = dist.find("volume-check/allowed-os-versions/os-version")
        self.assertIsNotNone(os_gate)
        self.assertEqual(os_gate.attrib, {"min": "15.0"})
        components = plistlib.loads((ROOT / "Configuration/installer/Components.plist").read_bytes())
        self.assertEqual(len(components), 1)
        self.assertEqual(components[0]["RootRelativeBundlePath"], "Notchscape.app")
        self.assertIs(components[0]["BundleIsRelocatable"], False)
        self.assertIs(components[0]["BundleHasStrictIdentifier"], True)
        source = (ROOT / ".github/scripts/package_shared_installer.sh").read_text()
        self.assertIn("--install-location /Applications", source)
        self.assertIn("--ownership recommended", source)
        self.assertIn("--unsigned-preview", source)
        self.assertIn("Developer ID Installer:", source)
        self.assertNotIn("sudo", source)
        self.assertNotIn("postinstall", source)

    def test_release_targets_agree_with_framework_minimum(self):
        import re
        project = (ROOT / "Notchscape.xcodeproj/project.pbxproj").read_text()
        self.assertEqual(re.findall(r"MACOSX_DEPLOYMENT_TARGET = ([^;]+);", project), ["15.0"] * 6)
        workflow = (ROOT / ".github/workflows/release.yml").read_text()
        self.assertIn("depends_on macos: :sequoia", workflow)
        self.assertNotIn("depends_on macos: :sonoma", workflow)

    def test_both_packaging_paths_require_shared_permission_check(self):
        for filename in ["package_shared_installer.sh", "package_notchscape_release.sh"]:
            source = (ROOT / ".github/scripts" / filename).read_text()
            self.assertIn("verify_shared_install.py", source)
            self.assertIn("verify_custom_app_identity.sh", source)


class PresentationIntegrationTests(unittest.TestCase):
    def test_requested_defaults_and_migration_are_wired(self):
        constants = (ROOT / "Notchscape/models/Constants.swift").read_text()
        self.assertIn('Key<Bool>("weatherEnabled", default: false)', constants)
        self.assertIn('Key<Bool>("showOnAllDisplays", default: true)', constants)
        self.assertIn('Key<Bool>("showOnExternalDisplays", default: true)', constants)
        source = (ROOT / "Notchscape/NotchscapeApp.swift").read_text()
        initializer = source.split("    init() {", 1)[1].split("    private static", 1)[0]
        self.assertLess(initializer.index("migrateSandboxPreferencesIfNeeded"),
                        initializer.index("applyInitialPresentationDefaults"))
        self.assertLess(initializer.index("applyInitialPresentationDefaults"),
                        initializer.index("SPUStandardUpdaterController"))
        policy = source.split("private static func applyInitialPresentationDefaults()", 1)[1].split("private static func migrateSandbox", 1)[0]
        self.assertIn("guard !defaults.bool", policy)
        self.assertIn("missingValues(in: persistent)", policy)
        self.assertIn('if let weather = missing["weatherEnabled"]', policy)
        self.assertIn('if let displays = missing["showOnAllDisplays"]', policy)

    def test_header_inset_is_shared_by_notched_and_notchless_layouts(self):
        source = (ROOT / "Notchscape/ContentView.swift").read_text()
        self.assertIn(".padding(.top, NotchHeaderMetrics.topInset)", source)
        self.assertIn("NotchHeaderLayoutPolicy.rowHeight(", source)
        self.assertNotIn(".padding(.top, sportsUsesPhysicalNotchLayout ? 0 : 8)", source)
        workflow = (ROOT / ".github/workflows/cicd.yml").read_text()
        self.assertIn("tests/AppPresentationPolicyTests.swift", workflow)


if __name__ == "__main__":
    unittest.main()
