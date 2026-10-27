"""Validate Cityscapes theme/schema agreement and bounded bundled artwork."""

import hashlib
import json
import re
import struct
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
ASSETS = ROOT / "Notchscape/Assets.xcassets"


class CityscapeThemeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.models = (ROOT / "Notchscape/models/CustomizationModels.swift").read_text()
        cls.generic = (ROOT / "Notchscape/enums/generic.swift").read_text()
        cls.ids = set(re.findall(r'case \w+ = "(city\w+)"', cls.models))
        cls.names = set(re.findall(r'"(City\w+Backdrop)"', cls.models))

    def test_all_twelve_cities_are_atomic_themes(self):
        self.assertEqual(len(self.ids), 12)
        self.assertEqual(len(self.names), 12)
        app_theme = self.generic.split("enum AppTheme:", 1)[1].split("    var id:", 1)[0]
        self.assertEqual(set(re.findall(r"\bcity\w+\b", app_theme)), self.ids)

    def test_import_and_account_allowlists_accept_exact_city_values(self):
        for path in ("Notchscape/models/AccountSettingsPolicy.swift", "services/accounts/src/policy.js",
                     "tests/AppearanceRecipePolicyTests.swift"):
            source = (ROOT / path).read_text()
            self.assertEqual(set(re.findall(r"[\"'](city\w*)[\"']", source)), self.ids, path)

    def test_each_city_has_one_distinct_bounded_bundled_photo(self):
        hashes = set()
        total_bytes = 0
        for name in self.names:
            directory = ASSETS / (name + ".imageset")
            manifest = json.loads((directory / "Contents.json").read_text())
            entries = [entry for entry in manifest["images"] if "filename" in entry]
            self.assertEqual(len(entries), 1, name)
            filename = name + ".png"
            self.assertEqual(entries[0]["filename"], filename)
            self.assertEqual({path.name for path in directory.glob("*.png")}, {filename})
            payload = (directory / filename).read_bytes()
            self.assertEqual(payload[:8], b"\x89PNG\r\n\x1a\n", name)
            width, height = struct.unpack(">II", payload[16:24])
            self.assertTrue(1024 <= width <= 2048 and 768 <= height <= 2048, name)
            self.assertAlmostEqual(width / height, 16 / 9, delta=0.02, msg=name)
            self.assertLess(len(payload), 8_000_000, name)
            total_bytes += len(payload)
            hashes.add(hashlib.sha256(payload).hexdigest())
        self.assertEqual(len(hashes), 12, "Every selected city must display different artwork")
        self.assertLessEqual(total_bytes, 48_000_000, "City scenes remain a bounded local photo collection")


if __name__ == "__main__":
    unittest.main()
