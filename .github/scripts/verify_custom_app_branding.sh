#!/bin/bash
# Xcode may reuse generated plist output during an incremental build. Signing
# trust alone cannot establish that the artifact contains the requested branding.
set -euo pipefail
candidate="${1:?Usage: verify_custom_app_branding.sh candidate.app source-Info.plist}"
source_info="${2:?Usage: verify_custom_app_branding.sh candidate.app source-Info.plist}"
built_info="$candidate/Contents/Info.plist"
expected_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$source_info")"
if [[ "$(basename "$candidate")" != "$expected_name.app" ]]; then
    printf 'FAIL: app bundle filename must be %s.app, not just its display label.\n' "$expected_name" >&2
    exit 1
fi
for key in CFBundleName CFBundleDisplayName; do
    expected="$(/usr/libexec/PlistBuddy -c "Print :$key" "$source_info")"
    actual="$(/usr/libexec/PlistBuddy -c "Print :$key" "$built_info")"
    if [[ -z "$expected" || "$actual" != "$expected" ]]; then
        printf 'FAIL: built %s does not match the requested source branding; rebuild before install.\n' "$key" >&2
        exit 1
    fi
done
executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$built_info")"
if [[ "$executable" != "$expected_name" || ! -x "$candidate/Contents/MacOS/$executable" ]]; then
    printf 'FAIL: executable must use the current product name and exist.\n' >&2
    exit 1
fi
printf 'PASS: app filename, executable and display names match source branding\n'
