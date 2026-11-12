#!/bin/bash
set -euo pipefail
task_repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
task_test_dir="$(mktemp -d "${TMPDIR:-/tmp}/notchscape-addons-clipboard.XXXXXX")"
trap 'rm -rf "$task_test_dir"' EXIT

# Only pure synthetic fixtures: no app launch, clipboard, Keychain or vault access.
xcrun swiftc -swift-version 5 \
  "$task_repo_root/Notchscape/models/ProductivityModels.swift" \
  "$task_repo_root/tests/ProductivityPolicyTests.swift" \
  -o "$task_test_dir/productivity"
"$task_test_dir/productivity"
xcrun swiftc -swift-version 5 \
  "$task_repo_root/Notchscape/models/ProductivityModels.swift" \
  "$task_repo_root/tests/ClipboardProPolicyTests.swift" \
  -o "$task_test_dir/clipboard-pro"
"$task_test_dir/clipboard-pro"
xcrun swiftc -swift-version 5 \
  "$task_repo_root/Notchscape/models/AddOnCatalog.swift" \
  "$task_repo_root/tests/AddOnCatalogPolicyTests.swift" \
  -o "$task_test_dir/addon-catalog"
"$task_test_dir/addon-catalog"
