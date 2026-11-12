#!/bin/bash
set -euo pipefail
task_repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
task_test_dir="$(mktemp -d "${TMPDIR:-/tmp}/notchscape-display-tests.XXXXXX")"
trap 'rm -rf "$task_test_dir"' EXIT
xcrun swiftc -swift-version 5 \
  "$task_repo_root/Notchscape/models/AppPresentationPolicy.swift" \
  "$task_repo_root/Notchscape/models/DisplayGeometryPolicy.swift" \
  "$task_repo_root/Notchscape/extensions/NSScreen+DisplayGeometry.swift" \
  "$task_repo_root/tests/DisplayGeometryPolicyTests.swift" \
  -o "$task_test_dir/display-geometry-tests"
"$task_test_dir/display-geometry-tests" "$@"
xcrun swiftc -swift-version 5 \
  "$task_repo_root/Notchscape/models/IslandClickPolicy.swift" \
  "$task_repo_root/tests/IslandClickPolicyTests.swift" \
  -o "$task_test_dir/island-click-tests"
"$task_test_dir/island-click-tests"
