"""Synthetic metadata, signature and old-baseline checks. Never runs a host app."""
import contextlib
import hashlib
import importlib.util
import io
import pathlib
import plistlib
import subprocess
import tempfile
import unittest
from unittest import mock

ROOT = pathlib.Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location("dock_signing_gate", ROOT / ".github/scripts/face_vault_signing.py")
gate = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(gate)


class DockWidgetSigningTests(unittest.TestCase):
    def setUp(self):
        self.main_info = {"CFBundleIdentifier": gate.MAIN, "CFBundleVersion": "310", "CFBundleShortVersionString": "2.9.5"}
        self.info = {"CFBundleIdentifier": gate.DOCK_WIDGET, "CFBundleExecutable": "NotchscapeDockWidget",
                     "CFBundleName": "Notchscape Dock Widget", "CFBundleDisplayName": "Notchscape Dock Widget",
                     "CFBundlePackageType": "APPL", "CFBundleVersion": "310", "CFBundleShortVersionString": "2.9.5",
                     "LSUIElement": False, "LSMinimumSystemVersion": "15.0"}
        self.certificate = b"synthetic public certificate, never a key or actual signer"
        self.details = subprocess.CompletedProcess([], 0, stdout="", stderr=(
            "CodeDirectory flags=0x10000(runtime)\nTeamIdentifier=" + gate.TEAM + "\nIdentifier=" + gate.DOCK_WIDGET + "\n"))

    def fixture(self, root, include_host=True):
        app = root / "candidate.app"
        previous = root / "previous.app"
        for bundle, info in [(app, self.main_info), (previous, {**self.main_info, "CFBundleVersion": "309"})]:
            (bundle / "Contents").mkdir(parents=True)
            (bundle / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
        host = app / gate.DOCK_WIDGET_PATH
        if include_host:
            (host / "Contents/MacOS").mkdir(parents=True)
            (host / "Contents/Info.plist").write_bytes(plistlib.dumps(self.info))
            executable = host / "Contents/MacOS/NotchscapeDockWidget"
            executable.write_bytes(b"inert fixture, not executable code")
            executable.chmod(0o755)
        return app, previous, host

    @contextlib.contextmanager
    def signing_fixture(self, entitlements=b"", details=None, command_error=None):
        def command(arguments):
            if command_error:
                raise ValueError(command_error)
            return entitlements if "--entitlements" in arguments else b""
        with mock.patch.object(gate, "CERT_SHA256", hashlib.sha256(self.certificate).hexdigest()), \
             mock.patch.object(gate, "certificate_data", return_value=self.certificate), \
             mock.patch.object(gate, "command", side_effect=command), \
             mock.patch.object(gate.subprocess, "run", return_value=details or self.details), \
             contextlib.redirect_stdout(io.StringIO()):
            yield

    def test_plain_dock_app_configuration(self):
        gate.validate_dock_widget_configuration(self.info, self.main_info)
        gate.validate_dock_widget_configuration({**self.info, "LSBackgroundOnly": False}, self.main_info)

    def test_wrong_identity_type_and_minimum_are_rejected(self):
        for key, value in {"CFBundleIdentifier": "foreign.helper", "CFBundleExecutable": "../other",
                           "CFBundleName": "Other", "CFBundleDisplayName": "Other", "CFBundlePackageType": "XPC!",
                           "LSUIElement": True, "LSBackgroundOnly": True, "LSMinimumSystemVersion": "26.0",
                           "LSMultipleInstancesProhibited": True}.items():
            with self.subTest(key=key), self.assertRaises(ValueError):
                gate.validate_dock_widget_configuration({**self.info, key: value}, self.main_info)
        with self.assertRaises(ValueError):
            gate.validate_dock_widget_configuration(self.info, {**self.main_info, "CFBundleIdentifier": "another.app"})

    def test_booleans_and_versions_must_be_well_typed(self):
        for key, value in [("LSUIElement", 0), ("LSUIElement", "NO"), ("LSBackgroundOnly", 0),
                           ("LSMultipleInstancesProhibited", 1), ("CFBundleVersion", 310),
                           ("CFBundleVersion", "309"), ("CFBundleShortVersionString", "2.9.4")]:
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                gate.validate_dock_widget_configuration({**self.info, key: value}, self.main_info)

    def test_permission_and_service_declarations_are_rejected(self):
        for key in ["NSCameraUsageDescription", "NSMicrophoneUsageDescription", "NSAppleEventsUsageDescription",
                    "NSLocationUsageDescription", "XPCService", "MachServices", "NSExtension", "CFBundleURLTypes", "LSEnvironment"]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                gate.validate_dock_widget_configuration({**self.info, key: "unexpected"}, self.main_info)

    def test_missing_and_relocated_host_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            app, _, host = self.fixture(pathlib.Path(directory))
            self.assertEqual(gate.dock_widget_path(app), host)
            host.rename(host.with_name("Renamed.app"))
            with self.assertRaises(ValueError):
                gate.dock_widget_path(app)

    def test_profile_and_indirect_files_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            app, _, host = self.fixture(pathlib.Path(directory))
            for name in ["embedded.provisionprofile", "embedded.mobileprovision"]:
                profile = host / "Contents" / name
                profile.write_bytes(b"synthetic profile")
                with self.assertRaises(ValueError):
                    gate.dock_widget_path(app)
                profile.unlink()
            (host / "Contents/indirect").symlink_to(pathlib.Path(directory))
            with self.assertRaises(ValueError):
                gate.dock_widget_path(app)

    def test_non_runnable_binary_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            app, _, host = self.fixture(pathlib.Path(directory))
            (host / "Contents/MacOS/NotchscapeDockWidget").chmod(0o644)
            with self.assertRaises(ValueError):
                gate.dock_widget_path(app)

    def test_309_without_host_is_valid_baseline_for_new_signed_host(self):
        with tempfile.TemporaryDirectory() as directory:
            app, previous, _ = self.fixture(pathlib.Path(directory))
            self.assertFalse((previous / gate.DOCK_WIDGET_PATH).exists())
            with self.signing_fixture():
                gate.verify_dock_widget_app(app, previous)

    def test_empty_signed_entitlement_dictionary_also_supported(self):
        with tempfile.TemporaryDirectory() as directory:
            app, previous, _ = self.fixture(pathlib.Path(directory))
            with self.signing_fixture(entitlements=plistlib.dumps({})):
                gate.verify_dock_widget_app(app, previous)

    def test_signature_failure_and_any_signed_entitlement_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            app, previous, _ = self.fixture(pathlib.Path(directory))
            with self.signing_fixture(command_error="synthetic signature refusal"), self.assertRaises(ValueError):
                gate.verify_dock_widget_app(app, previous)
            for entitlements in [{"com.apple.security.get-task-allow": False}, {"keychain-access-groups": ["wrong"]},
                                 {"com.apple.security.app-sandbox": True}, ["malformed"]]:
                with self.subTest(entitlements=entitlements), self.signing_fixture(entitlements=plistlib.dumps(entitlements)), self.assertRaises(ValueError):
                    gate.verify_dock_widget_app(app, previous)

    def test_every_component_must_use_the_pinned_public_certificate(self):
        with tempfile.TemporaryDirectory() as directory:
            app, previous, host = self.fixture(pathlib.Path(directory))
            for wrong in [host, app, previous]:
                def certificate(bundle):
                    return b"different certificate" if bundle == wrong else self.certificate
                with self.subTest(bundle=wrong.name), self.signing_fixture(), \
                     mock.patch.object(gate, "certificate_data", side_effect=certificate), self.assertRaises(ValueError):
                    gate.verify_dock_widget_app(app, previous)

    def test_team_identifier_and_runtime_are_required(self):
        with tempfile.TemporaryDirectory() as directory:
            app, previous, _ = self.fixture(pathlib.Path(directory))
            for details in [self.details.stderr.replace("(runtime)", ""),
                            self.details.stderr.replace(gate.TEAM, "FOREIGN"),
                            self.details.stderr.replace(gate.DOCK_WIDGET, "wrong.identifier")]:
                result = subprocess.CompletedProcess([], 0, stdout="", stderr=details)
                with self.subTest(details=details), self.signing_fixture(details=result), self.assertRaises(ValueError):
                    gate.verify_dock_widget_app(app, previous)

    def test_existing_host_requirement_must_remain_exact(self):
        with tempfile.TemporaryDirectory() as directory:
            app, previous, host = self.fixture(pathlib.Path(directory))
            (previous / gate.DOCK_WIDGET_PATH).mkdir(parents=True)
            with self.signing_fixture(), mock.patch.object(gate, "requirement", return_value="same exact DR"):
                gate.verify_dock_widget_app(app, previous)
            with self.signing_fixture(), mock.patch.object(gate, "requirement", side_effect=["changed DR", "old DR"]), self.assertRaises(ValueError):
                gate.verify_dock_widget_app(app, previous)

    def test_only_approved_additions_and_all_existing_requirements_preserved(self):
        old = {gate.OLD_HELPER: (None, "old DR"), "org.sparkle-project.Installer": (None, "Sparkle DR")}
        candidate = {**old, gate.BROKER: (None, "broker DR"), gate.DOCK_WIDGET: (None, "Dock DR")}
        gate.compare_inventories(candidate, old)
        for invalid in [{**candidate, "unexpected.app": (None, "new")},
                        {key: value for key, value in candidate.items() if key != gate.OLD_HELPER},
                        {**candidate, "org.sparkle-project.Installer": (None, "changed")}]:
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                gate.compare_inventories(invalid, old)

    def test_required_candidate_host_fails_before_any_face_profile_access(self):
        with tempfile.TemporaryDirectory() as directory:
            app, previous, _ = self.fixture(pathlib.Path(directory), include_host=False)
            old = {gate.OLD_HELPER: (None, "old DR"), gate.BROKER: (None, "broker DR")}
            with mock.patch.object(gate, "helper_inventory", return_value=old), mock.patch.object(gate, "decode_profile") as profile:
                with self.assertRaises(ValueError):
                    gate.verify_app(app, previous, require_dock_widget=True)
                profile.assert_not_called()

    def test_new_host_always_verified_even_without_required_flag(self):
        with tempfile.TemporaryDirectory() as directory:
            app, previous, _ = self.fixture(pathlib.Path(directory), include_host=False)
            old = {gate.OLD_HELPER: (None, "old DR"), gate.BROKER: (None, "broker DR")}
            with mock.patch.object(gate, "helper_inventory", side_effect=[{**old, gate.DOCK_WIDGET: (None, "Dock DR")}, old]), \
                 mock.patch.object(gate, "decode_profile") as profile:
                with self.assertRaises(ValueError):
                    gate.verify_app(app, previous)
                profile.assert_not_called()

    def test_wrapper_identity_is_exact_baseline_leaf_hash(self):
        with tempfile.TemporaryDirectory() as directory:
            _, previous, _ = self.fixture(pathlib.Path(directory))
            with self.signing_fixture():
                self.assertEqual(gate.dock_signing_identity(previous), hashlib.sha1(self.certificate).hexdigest().upper())
            with self.signing_fixture(), mock.patch.object(gate, "certificate_data", return_value=b"another certificate"), self.assertRaises(ValueError):
                gate.dock_signing_identity(previous)
            (previous / "Contents/Info.plist").write_bytes(plistlib.dumps({**self.main_info, "CFBundleIdentifier": "foreign.app"}))
            with self.signing_fixture(), self.assertRaises(ValueError):
                gate.dock_signing_identity(previous)


if __name__ == "__main__":
    unittest.main()
