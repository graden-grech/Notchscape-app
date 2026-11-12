#!/usr/bin/env bash
set -euo pipefail

geometry_repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
geometry_compiler="${DISPLAY_GEOMETRY_SWIFTC:-$(xcrun --find swiftc)}"
geometry_sdk="${DISPLAY_GEOMETRY_SDK:-$(xcrun --sdk macosx --show-sdk-path)}"
geometry_test_dir="$(mktemp -d "${TMPDIR:-/tmp}/notchscape-display-geometry.XXXXXX")"
trap 'rm -rf "$geometry_test_dir"' EXIT

"$geometry_compiler" -sdk "$geometry_sdk" -parse-as-library \
    "$geometry_repo/Notchscape/models/DisplayGeometryPolicy.swift" \
    "$geometry_repo/Notchscape/models/AppPresentationPolicy.swift" \
    "$geometry_repo/Notchscape/extensions/NSScreen+DisplayGeometry.swift" \
    "$geometry_repo/tests/DisplayGeometryPolicyTests.swift" \
    -o "$geometry_test_dir/display-geometry-tests"
"$geometry_test_dir/display-geometry-tests" "$@"
