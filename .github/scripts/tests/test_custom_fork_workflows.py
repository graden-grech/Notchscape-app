"""Keep optional upstream services from failing in an unconfigured custom fork."""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]


class CustomForkWorkflowTests(unittest.TestCase):
    def test_ai_chat_title_checks_run_in_ci(self):
        workflow = (ROOT / ".github/workflows/cicd.yml").read_text()
        self.assertIn("Notchscape/models/AgentChatTitle.swift tests/AgentChatTitleTests.swift", workflow)
        self.assertIn('"$RUNNER_TEMP/agent-chat-title-tests"', workflow)

    def test_nightly_is_opt_in_for_forks(self):
        workflow = (ROOT / ".github/workflows/nightly.yml").read_text()
        prepare = workflow.split("  prepare:\n", 1)[1].split("  build:\n", 1)[0]
        self.assertIn("vars.ENABLE_NIGHTLY_BUILDS == 'true'", prepare)
        self.assertNotIn("TheBoredTeam", prepare)

    def test_website_deployment_is_opt_in_for_forks(self):
        workflow = (ROOT / ".github/workflows/static.yml").read_text()
        self.assertIn("vars.ENABLE_GITHUB_PAGES == 'true'", workflow)
        self.assertNotIn("TheBoredTeam", workflow)

    def test_incomplete_translation_workflow_is_not_registered(self):
        self.assertFalse((ROOT / ".github/workflows/crowdin.yml").exists())

    def test_app_build_and_security_checks_still_run_on_push(self):
        for name in ("cicd.yml", "codeql.yml"):
            workflow = (ROOT / ".github/workflows" / name).read_text()
            self.assertIn("  push:\n", workflow)
            self.assertNotIn("ENABLE_NIGHTLY_BUILDS", workflow)
            self.assertNotIn("ENABLE_GITHUB_PAGES", workflow)

    def test_native_sdk_build_retains_intel_runner_and_feature_policy_checks(self):
        workflow = (ROOT / ".github/workflows/cicd.yml").read_text()
        self.assertIn("runs-on: macos-26-intel", workflow)
        self.assertIn("          - ^26", workflow)
        self.assertIn("          - Notchscape", workflow)
        self.assertIn("tests/CustomizationPolicyTests.swift", workflow)
        self.assertIn("tests/ProductivityPolicyTests.swift", workflow)
        self.assertIn("tests/NotchUtilitiesPolicyTests.swift", workflow)
        self.assertIn("Notchscape/models/WorkspaceModeModels.swift", workflow)
        self.assertIn("tests/WorkspaceModePolicyTests.swift", workflow)
        self.assertIn('"$RUNNER_TEMP/workspace-mode-tests"', workflow)
        self.assertIn("tests/AccountSettingsPolicyTests.swift", workflow)

    def test_new_feature_policy_steps_compile_and_run_without_skipping_failures(self):
        workflow = (ROOT / ".github/workflows/cicd.yml").read_text()
        cases = (
            (
                "Check AI chat titles and read-only metadata fallbacks",
                ("Notchscape/models/AgentChatTitle.swift", "tests/AgentChatTitleTests.swift"),
                "agent-chat-title-tests",
            ),
            (
                "Check personal workspace tools and input-safety policies",
                (
                    "Notchscape/models/WorkspaceToolsModels.swift",
                    "Notchscape/models/WindowGeometry.swift",
                    "tests/WorkspaceToolsPolicyTests.swift",
                ),
                "workspace-tools-tests",
            ),
            (
                "Check bounded appearance recipe import and export policies",
                ("Notchscape/models/AppearanceRecipe.swift", "tests/AppearanceRecipePolicyTests.swift"),
                "appearance-recipe-tests",
            ),
            (
                "Check local capture redaction and QR policies",
                ("Notchscape/models/CapturePolicy.swift", "tests/CapturePolicyTests.swift"),
                "capture-policy-tests",
            ),
            (
                "Check portable window layout geometry policies",
                ("Notchscape/models/WindowGeometry.swift", "tests/WindowGeometryTests.swift"),
                "window-geometry-tests",
            ),
            (
                "Check synthetic media export without screen capture",
                ("Notchscape/managers/MediaToolsManager.swift", "tests/MediaToolsSmoke.swift"),
                "media-tools-smoke",
            ),
        )
        for title, sources, executable in cases:
            with self.subTest(step=title):
                step = workflow.split(f"    - name: {title}\n", 1)[1].split("    - name:", 1)[0]
                self.assertIn("set -euo pipefail", step)
                self.assertIn("swiftc ", step)
                for source in sources:
                    self.assertTrue((ROOT / source).is_file(), source)
                    self.assertIn(source, step)
                self.assertIn(f'        "$RUNNER_TEMP/{executable}"', step)
                self.assertNotIn("continue-on-error", step)
                self.assertNotIn("      if:", step)


if __name__ == "__main__":
    unittest.main()
