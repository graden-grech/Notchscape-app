"""Keep the integrated wallpaper page inside Notchscape's update trust boundary."""

import plistlib
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]


class WallpaperUpdateBoundaryTests(unittest.TestCase):
    def test_combined_app_keeps_the_existing_update_identity(self):
        with (ROOT / "Notchscape/Info.plist").open("rb") as file:
            info = plistlib.load(file)
        # Xcode otherwise derives CFBundleName from the compatibility PRODUCT_NAME,
        # even with INFOPLIST_KEY_CFBundleName set. Keep public branding explicit.
        self.assertEqual(info["CFBundleDisplayName"], "Notchscape")
        self.assertEqual(info["CFBundleName"], "Notchscape")
        self.assertNotIn("CFBundleExecutable", info)
        self.assertEqual(
            info["SUFeedURL"],
            "https://raw.githubusercontent.com/graden-grech/Notchscape-app/main/appcast.xml",
        )
        self.assertEqual(
            info["SUPublicEDKey"], "nqZKiSN++X9uwH4MqHVLSJ9RQ6bvbT9Y2B07flQ34OQ="
        )

    def test_wallpaper_integration_does_not_bring_a_second_updater_or_analytics(self):
        for relative in (
            "Notchscape/managers/NotchWallpaperManager.swift",
            "Notchscape/components/Settings/WallpaperViews.swift",
            "Notchscape/models/WallpaperModels.swift",
            "Notchscape/models/WallpaperCatalog.swift",
            "Notchscape/models/WindowsWallpaperCatalog.swift",
        ):
            with self.subTest(file=relative):
                source = (ROOT / relative).read_text(encoding="utf-8")
                for forbidden in (
                    "import Sparkle",
                    "SPUStandardUpdaterController",
                    "SUFeedURL",
                    "macscapes-updates",
                    "import Sentry",
                    "import PostHog",
                    "AnalyticsManager",
                    "TelemetryManager",
                ):
                    self.assertNotIn(forbidden, source)


if __name__ == "__main__":
    unittest.main()
