"""Validate shared city/landmark schemas and bounded, traceable artwork."""

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
        cls.ids = set(re.findall(r'case \w+ = "((?:city|landmark)\w+)"', cls.models))
        cls.city_names = set(re.findall(r'"(City\w+Backdrop)"', cls.models))
        cls.landmark_names = set(re.findall(r'"(Landmark\w+Backdrop)"', cls.models))

    def test_cities_and_landmarks_are_atomic_values_in_the_same_theme_schema(self):
        self.assertEqual(len(self.ids), 24)
        self.assertEqual(len(self.city_names), 12)
        self.assertEqual(len(self.landmark_names), 12)
        app_theme = self.generic.split("enum AppTheme:", 1)[1].split("    var id:", 1)[0]
        self.assertEqual(set(re.findall(r"\b(?:city|landmark)\w+\b", app_theme)), self.ids)

    def test_import_and_account_allowlists_accept_exact_scene_values(self):
        for path in ("Notchscape/models/AccountSettingsPolicy.swift", "services/accounts/src/policy.js",
                     "tests/AppearanceRecipePolicyTests.swift"):
            source = (ROOT / path).read_text()
            self.assertEqual(set(re.findall(r"[\"']((?:city|landmark)\w*)[\"']", source)), self.ids, path)

    def assert_collection_artwork(self, names, provenance_name):
        provenance = json.loads((ROOT / "docs" / provenance_name).read_text())
        records = provenance["records"]
        self.assertEqual(len(records), len(names), "Provenance contains exactly one record per bundled scene")
        metadata = {record["asset"]: record for record in records}
        consumed_paths = set()
        hashes = set()
        total_bytes = 0
        for name in names:
            directory = ASSETS / (name + ".imageset")
            manifest = json.loads((directory / "Contents.json").read_text())
            entries = [entry for entry in manifest["images"] if "filename" in entry]
            self.assertEqual(len(entries), 1, name)
            filename = entries[0]["filename"]
            self.assertEqual(Path(filename).name, filename, "Artwork filenames stay local to their asset set")
            self.assertTrue(filename.endswith(".png"), name)
            self.assertEqual({path.name for path in directory.glob("*.png")}, {filename})
            payload = (directory / filename).read_bytes()
            self.assertEqual(payload[:8], b"\x89PNG\r\n\x1a\n", name)
            width, height = struct.unpack(">II", payload[16:24])
            self.assertTrue(1024 <= width <= 2048 and 768 <= height <= 2048, name)
            self.assertAlmostEqual(width / height, 16 / 9, delta=0.02, msg=name)
            self.assertLess(len(payload), 8_000_000, name)
            digest = hashlib.sha256(payload).hexdigest()
            asset_path = (directory / filename).relative_to(ROOT).as_posix()
            consumed_paths.add(asset_path)
            self.assertIn(asset_path, metadata, "Provenance follows the exact filename consumed by the asset catalog")
            record = metadata[asset_path]
            self.assertEqual(record["dimensions"], [width, height], name)
            self.assertEqual(record["bytes"], len(payload), name)
            self.assertEqual(record["sha256"], digest, name)
            total_bytes += len(payload)
            hashes.add(digest)
        self.assertEqual(len(hashes), len(names), "Every selected view must display different artwork")
        self.assertEqual(set(metadata), consumed_paths, "Provenance covers exactly the catalog's consumed artwork")
        self.assertLessEqual(total_bytes, 48_000_000, "Each collection remains a bounded local photo library")
        return hashes

    def test_city_artwork_retains_its_distinct_bounded_photos_and_provenance(self):
        self.assert_collection_artwork(self.city_names, "CITYSCAPES_ARTWORK.json")

    def test_landmarks_have_distinct_bounded_photos_and_matching_provenance(self):
        landmark_hashes = self.assert_collection_artwork(self.landmark_names, "LANDMARKS_ARTWORK.json")
        city_hashes = self.assert_collection_artwork(self.city_names, "CITYSCAPES_ARTWORK.json")
        self.assertTrue(landmark_hashes.isdisjoint(city_hashes), "Landmarks must not reuse a city's photo")


if __name__ == "__main__":
    unittest.main()
