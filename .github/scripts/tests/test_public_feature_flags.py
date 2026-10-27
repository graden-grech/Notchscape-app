import importlib.util
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location("public_flags", ROOT / ".github/scripts/verify_public_feature_flags.py")
PUBLIC_FLAGS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PUBLIC_FLAGS)


class PublicFeatureFlagTests(unittest.TestCase):
    def test_only_explicit_false_passes(self):
        PUBLIC_FLAGS.check_public_features({"NotchAccountsEnabled": False})

    def test_missing_enabled_or_malformed_flag_fails(self):
        for info in [{}, *({"NotchAccountsEnabled": value} for value in [True, 0, 1, "false", None, [], {}])]:
            with self.subTest(info=info), self.assertRaises(ValueError):
                PUBLIC_FLAGS.check_public_features(info)

    def test_ci_and_signed_build_run_the_gate(self):
        for path in [".github/workflows/cicd.yml", ".github/scripts/build_custom_signed_app.sh"]:
            self.assertIn("verify_public_feature_flags.py", (ROOT / path).read_text())


if __name__ == "__main__":
    unittest.main()
