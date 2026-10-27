"""Guard temporary-mode boundaries; native policy and live tests are separate."""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


class WorkspaceModeIntegrationTests(unittest.TestCase):
    def source(self, path):
        return (ROOT / "Notchscape" / path).read_text(encoding="utf-8")

    def test_manager_never_rewrites_saved_preferences(self):
        manager = self.source("managers/WorkspaceModeManager.swift")
        self.assertNotIn("Defaults[", manager)
        self.assertNotIn("UserDefaults", manager)
        self.assertIn("NSWorkspace.didWakeNotification", manager)
        self.assertIn(".NSSystemClockDidChange", manager)
        self.assertIn("self.session?.id == value.id", manager)
        self.assertIn("!Task.isCancelled", manager)
        self.assertIn("WebcamManager.shared.stopSession()", manager)

    def test_presentation_cannot_expire(self):
        model = self.source("models/WorkspaceModeModels.swift")
        self.assertIn("mode.hidesPrivateContent ? nil : duration.seconds", model)

    def test_private_tools_cannot_reopen(self):
        view = self.source("components/Settings/ProductivityViews.swift")
        self.assertIn("guard WorkspaceModeManager.shared.active?.hidesPrivateContent != true", view)
        self.assertIn("if modes.active?.hidesPrivateContent == true { PresentationModePlaceholder() }", view)
        tools = self.source("managers/LocalToolsManager.swift")
        self.assertIn("paused = locked || userPaused || privateContentHidden", tools)
        self.assertEqual(tools.count("userPaused: userPaused || privateContentHidden"), 2)
        self.assertIn("!privateContentHidden, Defaults[.textCaptureEnabled], generation == captureGeneration", tools)

    def test_rotation_rechecks_mode_after_download(self):
        manager = self.source("managers/NotchWallpaperManager.swift")
        download_end = manager.index("try Task.checkCancellation()")
        desktop_change = manager.index("try NSWorkspace.shared.setDesktopImageURL")
        self.assertIn("!automatic || WorkspaceModeManager.shared.active?.pauseWallpapers != true", manager[download_end:desktop_change])
        self.assertIn("session?.mode.pauseWallpapers == true && automaticRequest", manager)

    def test_stale_camera_start_checks_desire_and_generation(self):
        manager = self.source("managers/WebcamManager.swift")
        start = manager.index("private func startRunningCaptureSession")
        actual = manager.index("session.startRunning()", start)
        self.assertIn("self.desiredRunning", manager[start:actual])
        self.assertIn("self.sessionGeneration == generation", manager[start:actual])
        stop = manager[manager.index("func stopSession()") :]
        self.assertIn("self.desiredRunning = false", stop)
        self.assertIn("self.sessionGeneration &+= 1", stop)


if __name__ == "__main__":
    unittest.main()
