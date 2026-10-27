"""Keep the optional White House family complete without running the app."""

import json
import hashlib
import re
import struct
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
ASSETS = ROOT / "Notchscape/Assets.xcassets"


class WhiteHouseThemeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.models = (ROOT / "Notchscape/models/CustomizationModels.swift").read_text()
        cls.generic = (ROOT / "Notchscape/enums/generic.swift").read_text()
        cls.ids = set(re.findall(r'case \w+ = "(whiteHouse\w*)"', cls.models))

    def test_all_combinations_are_real_app_themes(self):
        self.assertEqual(len(self.ids), 24)
        app_theme = self.generic.split("enum AppTheme:", 1)[1].split("    var id:", 1)[0]
        self.assertEqual(set(re.findall(r"\bwhiteHouse\w*\b", app_theme)), self.ids)
        self.assertIn("(!$0.isWhiteHouse || $0 == .whiteHouse)", self.generic)

    def test_bounded_import_policies_accept_exactly_the_new_theme_values(self):
        for path in ("Notchscape/models/AccountSettingsPolicy.swift", "services/accounts/src/policy.js",
                     "tests/AppearanceRecipePolicyTests.swift"):
            source = (ROOT / path).read_text()
            values = set(re.findall(r"[\"'](whiteHouse\w*)[\"']", source))
            self.assertEqual(values, self.ids, path)

    def test_all_artwork_references_resolve_to_local_bounded_pngs(self):
        names = {f"WhiteHouse{scene}{style}{decoration}Backdrop"
                 for scene in ("Exterior", "OvalOffice", "EastRoom", "BlueRoom")
                 for style in ("", "Republican", "Democrat")
                 for decoration in ("", "Christmas")}
        self.assertEqual(len(names), 24)
        self.assertIn('whiteHouseVariant?.backdropName', self.generic)
        photo_hashes = set()
        photo_bytes = 0
        icon_names = {"AppIconWhiteHouse", "AppIconWhiteHouseRepublican", "AppIconWhiteHouseDemocrat",
                      "AppIconWhiteHouseRepublicanChristmas", "AppIconWhiteHouseDemocratChristmas"}
        icon_hashes = set()
        for name in names | icon_names:
            directory = ASSETS / (name + ".imageset")
            manifest = json.loads((directory / "Contents.json").read_text())
            entries = [entry for entry in manifest["images"] if "filename" in entry]
            self.assertEqual(len(entries), 1, name)
            filename = entries[0]["filename"]
            expected_filename = "AppIconWhiteHouse-v2.png" if name == "AppIconWhiteHouse" else name + ".png"
            self.assertEqual(filename, expected_filename)
            self.assertEqual({path.name for path in directory.glob("*.png")}, {expected_filename},
                             "Only the consumed artwork is packaged; superseded originals stay in Git history")
            payload = (directory / filename).read_bytes()
            self.assertLess(len(payload), 8_000_000, name)
            self.assertEqual(payload[:8], b"\x89PNG\r\n\x1a\n")
            width, height = struct.unpack(">II", payload[16:24])
            self.assertTrue(1024 <= width <= 2048, name)
            self.assertTrue(768 <= height <= 2048, name)
            if name in icon_names:
                self.assertEqual(width, height)
                self.assertEqual(payload[25], 6, "Dock artwork retains true RGBA transparency")
                icon_hashes.add(hashlib.sha256(payload).hexdigest())
            else:
                self.assertGreater(width, height, "Home uses panoramic artwork, not a separate tile")
                self.assertAlmostEqual(width / height, 16 / 9, delta=0.02, msg=name)
                photo_hashes.add(hashlib.sha256(payload).hexdigest())
                photo_bytes += len(payload)
        self.assertEqual(len(photo_hashes), 24, "Every style and seasonal choice has genuinely different artwork")
        self.assertEqual(len(icon_hashes), 5, "Neutral, red, blue and party Christmas icons are separate artwork")
        self.assertLessEqual(photo_bytes, 80_000_000, "Bounded bundled artwork avoids a growing runtime image service")

    def test_white_house_controls_do_not_change_independent_preferences(self):
        source = (ROOT / "Notchscape/components/Settings/CustomizationSettings.swift").read_text()
        panel = source.split("struct WhiteHouseThemeSettingsView:", 1)[1].split("struct StarWarsThemeSettingsView:", 1)[0]
        self.assertIn("variant.selecting(style:", panel)
        self.assertIn("variant.selecting(scene:", panel)
        self.assertIn("variant.selecting(christmas:", panel)
        self.assertIn('Toggle("Christmas decorations"', panel)
        self.assertIn("if Defaults[.appIconFollowsTheme]", panel)
        for key in ("useCustomAccentColor", "customAccentColorData", "homeWidgetOrder", "hiddenHomeWidgets",
                    "hudReplacement", "liveActivitiesEnabled", "showDockIcon", "nonNotchPresentation"):
            self.assertNotIn(f"Defaults[.{key}] =", panel, key)
        self.assertIn(".pickerStyle(.segmented)", panel)
        self.assertIn("performance.suppressAnimations", panel)

    def test_photo_previews_preserve_the_complete_image(self):
        home = (ROOT / "Notchscape/components/Notch/NotchHomeView.swift").read_text()
        panel = (ROOT / "Notchscape/components/Settings/CustomizationSettings.swift").read_text()
        panel = panel.split("struct WhiteHouseThemeSettingsView:", 1)[1].split("struct StarWarsThemeSettingsView:", 1)[0]
        cards = (ROOT / "Notchscape/components/Settings/SettingsView.swift").read_text()
        cards = cards.split("private struct ThemePreviewCard:", 1)[1].split("private struct SeasonalIconPicker:", 1)[0]
        recipes = (ROOT / "Notchscape/components/Settings/AppearanceRecipesView.swift").read_text()
        sample = recipes.split("private struct AppearanceRecipeSample:", 1)[1]
        self.assertIn("preserveEntirePhoto: Bool = false", home)
        self.assertIn("if preserveEntirePhoto", home)
        self.assertIn("Image(backdrop).resizable().scaledToFit()", home)
        for source in (panel, cards, sample):
            self.assertIn("preserveEntirePhoto: true", source)
        self.assertIn(".aspectRatio(16.0 / 9.0, contentMode: .fit)", panel)
        for source in (cards, sample):
            self.assertIn(".aspectRatio(theme.usesArchitecturalPhotoLayout ? 16.0 / 9.0 : 3.0, contentMode: .fit)", source)
        self.assertNotIn("height: 78", panel)
        self.assertNotIn("height: 82", cards)
        self.assertIn(".scaledToFit()", panel)
        self.assertIn("theme.usesArchitecturalPhotoLayout ? .trailing : imageAlignment", home,
                      "Home keeps the building/tree central band, not mostly upper sky")
        self.assertNotIn("theme.usesArchitecturalPhotoLayout ? .topTrailing", home)

    def test_existing_panoramic_theme_photos_keep_their_original_aspect(self):
        names = {"AutumnBackdrop", "HalloweenBackdrop", "ChristmasBackdrop", "WinterBackdrop", "EasterBackdrop",
                 "StarWarsJediBackdrop", "StarWarsDarkSideBackdrop", "StarWarsDesertBackdrop"}
        for name in names:
            directory = ASSETS / (name + ".imageset")
            manifest = json.loads((directory / "Contents.json").read_text())
            filenames = [entry["filename"] for entry in manifest["images"] if "filename" in entry]
            self.assertEqual(len(filenames), 1, name)
            payload = (directory / filenames[0]).read_bytes()
            self.assertEqual(payload[:8], b"\x89PNG\r\n\x1a\n", name)
            width, height = struct.unpack(">II", payload[16:24])
            self.assertGreaterEqual(width, 1600, name)
            self.assertLessEqual(len(payload), 8_000_000, name)
            self.assertAlmostEqual(width / height, 3, delta=0.035, msg=name)

    def test_mixed_aspect_theme_cards_fill_and_top_align_the_same_grid_row(self):
        source = (ROOT / "Notchscape/components/Settings/SettingsView.swift").read_text()
        card = source.split("private struct ThemePreviewCard:", 1)[1].split("private struct SeasonalIconPicker:", 1)[0]
        card_frame = ".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)"
        self.assertIn(card_frame, card)
        self.assertLess(card.index(card_frame), card.index(".background(.white.opacity(selected"),
                        "The complete outer background, not the photo, must fill the row height")
        self.assertIn("LazyVGrid(columns: [GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top)], spacing: 14)", source)
        picker = source.split("ForEach(AppTheme.pickerThemes)", 1)[1].split('Text("Menu theme")', 1)[0]
        self.assertIn(".buttonStyle(.plain)\n                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)", picker)
        self.assertIn("preserveEntirePhoto: true", card)
        self.assertIn(".aspectRatio(theme.usesArchitecturalPhotoLayout ? 16.0 / 9.0 : 3.0, contentMode: .fit)", card)
        self.assertNotIn("scaledToFill", card, "Equalizing cards must not crop or stretch photos")

    def test_new_icon_does_not_replace_global_default(self):
        source = (ROOT / "Notchscape/models/Constants.swift").read_text()
        self.assertIn('Key<AppIconVariant>("appIconVariant", default: .standard)', source)
        self.assertIn('Key<AppTheme>("appTheme", default: .system)', source)
        self.assertIn('Key<WhiteHouseThemeVariant>("whiteHousePreferredVariant", default: .exterior)', source)


if __name__ == "__main__":
    unittest.main()
