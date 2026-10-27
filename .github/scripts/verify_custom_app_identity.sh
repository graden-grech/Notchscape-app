#!/bin/bash
# Read-only gate: compare the candidate against the previously trusted app.
set -euo pipefail
candidate="${1:?Usage: verify_custom_app_identity.sh candidate.app previous.app}"
previous="${2:?Usage: verify_custom_app_identity.sh candidate.app previous.app}"

for app in "$candidate" "$previous"; do
    /usr/bin/codesign --verify --deep --strict "$app"
    identifier=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Contents/Info.plist")
    team=$(/usr/bin/codesign -dv --verbose=2 "$app" 2>&1 | sed -n 's/^TeamIdentifier=//p')
    update_key=$(/usr/libexec/PlistBuddy -c 'Print SUPublicEDKey' "$app/Contents/Info.plist")
    [[ "$identifier" == "theboringteam.boringnotch" ]] || { echo 'FAIL: bundle identity changed'; exit 1; }
    [[ "$team" == "6H86CTRJCP" ]] || { echo 'FAIL: wrong signing team or unsigned build'; exit 1; }
    [[ "$update_key" == "nqZKiSN++X9uwH4MqHVLSJ9RQ6bvbT9Y2B07flQ34OQ=" ]] || { echo 'FAIL: update trust key changed'; exit 1; }
done

# Match helpers by their stable signing identifier, not their old product filename.
# This permits cosmetic app/helper renames without weakening the trust comparison.
helper_path() {
    local app="$1" found='' service identifier
    for service in "$app"/Contents/XPCServices/*.xpc; do
        [[ -d "$service" ]] || continue
        identifier=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$service/Contents/Info.plist")
        if [[ "$identifier" == 'theboringteam.boringnotch.BoringNotchXPCHelper' ]]; then
            [[ -z "$found" ]] || { echo 'FAIL: duplicate helpers' >&2; return 1; }
            found="$service"
        fi
    done
    [[ -n "$found" ]] || { echo 'FAIL: expected signed helper is missing' >&2; return 1; }
    printf '%s\n' "$found"
}
candidate_helper=$(helper_path "$candidate")
previous_helper=$(helper_path "$previous")
for component in app helper; do
    if [[ "$component" == app ]]; then
        candidate_path="$candidate"; previous_path="$previous"
    else
        candidate_path="$candidate_helper"; previous_path="$previous_helper"
    fi
    candidate_requirement=$(/usr/bin/codesign -dr - "$candidate_path" 2>&1 | sed -n 's/^designated => //p')
    previous_requirement=$(/usr/bin/codesign -dr - "$previous_path" 2>&1 | sed -n 's/^designated => //p')
    [[ -n "$candidate_requirement" && "$candidate_requirement" == "$previous_requirement" ]] || {
        echo "FAIL: signing requirement changed for app/helper; plan permission migration before release"
        exit 1
    }
done
echo 'PASS: app/helper signing identity and update key preserved'
