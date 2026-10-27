"""Privacy and coverage contracts for the optional settings guide."""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


class SettingsTourIntegrationTests(unittest.TestCase):
    def test_skipped_setup_is_not_forced_by_an_unsupported_music_source(self):
        app = (ROOT / "Notchscape/NotchscapeApp.swift").read_text()
        startup = app.split("if coordinator.firstLaunch {", 1)[1].split("previousScreens =", 1)[0]
        self.assertIn("self.showOnboardingWindow()", startup)
        self.assertNotIn("musicPermission", startup)
        self.assertNotIn("MusicManager.shared.isNowPlayingDeprecated", startup)

    def test_explains_every_real_settings_destination_once(self):
        destinations = (ROOT / "Notchscape/models/NotchUtilityModels.swift").read_text()
        destinations = destinations.split("struct NotchSettingsDestination:", 1)[1].split("enum WallpaperPolicy", 1)[0]
        expected = re.findall(r'\.init\(id: "([^"]+)"', destinations)
        guide = (ROOT / "Notchscape/models/SettingsTourPolicy.swift").read_text()
        actual = re.findall(r'\.init\(sectionID: "([^"]+)"', guide)
        self.assertCountEqual(actual, expected)
        self.assertEqual(len(actual), len(set(actual)))

    def test_tour_has_no_preference_or_permission_write_surface(self):
        for filename in ["Notchscape/models/SettingsTourPolicy.swift", "Notchscape/components/Onboarding/SettingsTourView.swift"]:
            source = (ROOT / filename).read_text()
            for forbidden in ["UserDefaults", "CFPreferences", "Defaults[", "requestAccess(", "promptIfNeeded:", "setActivationPolicy"]:
                self.assertNotIn(forbidden, source, filename)

    def test_calendar_destination_only_requests_access_from_explicit_connect_actions(self):
        manager = (ROOT / "Notchscape/managers/CalendarManager.swift").read_text()
        for method in ["checkCalendarAuthorization", "checkReminderAuthorization"]:
            signature = f"func {method}(requestIfNeeded: Bool = false) async"
            self.assertIn(signature, manager)
            body = manager.split(signature, 1)[1].split("    func ", 1)[0]
            self.assertLess(body.index("guard requestIfNeeded else { return }"),
                            body.index("calendarService.requestAccess("))
        settings = (ROOT / "Notchscape/components/Settings/SettingsView.swift").read_text()
        calendar = settings.split("struct CalendarSettings:", 1)[1].split("struct ActivitySettings:", 1)[0]
        refreshes = calendar.split(".onAppear {", 1)[1]
        self.assertNotIn("requestIfNeeded: true", refreshes)
        for kind, method in [("Calendar", "checkCalendarAuthorization"), ("Reminders", "checkReminderAuthorization")]:
            self.assertIn(f'Button("Connect {kind}…")', calendar)
            self.assertIn(f"calendarManager.{method}(requestIfNeeded: true)", calendar)


if __name__ == "__main__":
    unittest.main()
