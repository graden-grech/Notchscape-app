import importlib.util
import plistlib
from pathlib import Path
import tempfile
import unittest
import zipfile


SCRIPT = Path(__file__).resolve().parents[1] / "verify_distribution_archive.py"
SPEC = importlib.util.spec_from_file_location("distribution_archive", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class DistributionArchiveTests(unittest.TestCase):
    def fixture(self, root="Notchscape.app", extra=None, **overrides):
        directory = tempfile.TemporaryDirectory(prefix="notchscape-archive-test-")
        self.addCleanup(directory.cleanup)
        path = Path(directory.name) / "Notchscape.zip"
        info = dict(CFBundleName="Notchscape", CFBundleDisplayName="Notchscape",
                    CFBundleExecutable="Notchscape", NotchAccountsEnabled=False,
                    LSMinimumSystemVersion="15.0",
                    NSCalendarsFullAccessUsageDescription="Show selected calendar events.",
                    NSRemindersFullAccessUsageDescription="Show selected reminders.",
                    SUFeedURL="https://raw.githubusercontent.com/graden-grech/Notchscape-app/main/appcast.xml")
        info.update(overrides)
        if info.get("LSMinimumSystemVersion") is None:
            info.pop("LSMinimumSystemVersion", None)
        with zipfile.ZipFile(path, "w") as archive:
            archive.writestr(root + "/Contents/Info.plist", plistlib.dumps(info))
            archive.writestr(root + "/Contents/MacOS/Notchscape", b"fixture only")
            if extra:
                archive.writestr(extra, b"fixture only")
        return path

    def test_branded_download_passes(self):
        report = MODULE.validate_archive(self.fixture())
        self.assertEqual(report["app"], "Notchscape.app")
        self.assertEqual(report["minimumSystemVersion"], "15.0")

    def test_minimum_os_matches_linked_framework_requirement(self):
        for version in [None, "", "14.0", "14.9.9", "-15", "15.beta", 15, "15.0.0.1"]:
            with self.subTest(version=version), self.assertRaises(ValueError):
                MODULE.validate_archive(self.fixture(LSMinimumSystemVersion=version))
        for version in ["15", "15.0", "15.0.1", "26.0"]:
            self.assertEqual(MODULE.validate_archive(self.fixture(LSMinimumSystemVersion=version))["minimumSystemVersion"], version)

    def test_explicit_full_access_requests_have_system_purpose_strings(self):
        for key in ("NSCalendarsFullAccessUsageDescription", "NSRemindersFullAccessUsageDescription"):
            for value in ("", " ", False):
                with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                    MODULE.validate_archive(self.fixture(**{key: value}))

    def test_branded_zip_with_old_app_inside_fails(self):
        with self.assertRaises(ValueError):
            MODULE.validate_archive(self.fixture(root="Boring Notch.app"))

    def test_old_executable_fails(self):
        with self.assertRaises(ValueError):
            MODULE.validate_archive(self.fixture(CFBundleExecutable="Boring Notch"))

    def test_old_display_name_fails(self):
        with self.assertRaises(ValueError):
            MODULE.validate_archive(self.fixture(CFBundleDisplayName="Boring Notch"))

    def test_second_app_fails(self):
        with self.assertRaises(ValueError):
            MODULE.validate_archive(self.fixture(extra="Old.app/Contents/Info.plist"))

    def test_path_traversal_fails(self):
        with self.assertRaises(ValueError):
            MODULE.validate_archive(self.fixture(extra="Notchscape.app/../outside"))

    def test_accounts_cannot_slip_back_in(self):
        with self.assertRaises(ValueError):
            MODULE.validate_archive(self.fixture(NotchAccountsEnabled=True))

    def test_other_update_server_fails(self):
        with self.assertRaises(ValueError):
            MODULE.validate_archive(self.fixture(SUFeedURL="https://example.com/feed.xml"))

    def test_old_helper_filename_fails(self):
        with self.assertRaises(ValueError):
            MODULE.validate_archive(self.fixture(extra="Notchscape.app/Contents/XPCServices/BoringNotchXPCHelper.xpc/Contents/Info.plist"))
