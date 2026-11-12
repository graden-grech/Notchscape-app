#!/bin/bash
# Read-only gate: compare the candidate against the previously trusted app.
set -euo pipefail
candidate="${1:?Usage: verify_custom_app_identity.sh candidate.app previous.app}"
previous="${2:?Usage: verify_custom_app_identity.sh candidate.app previous.app}"
selected_face_profile="${3:-}"
variant="${4:-${NOTCHSCAPE_BUILD_VARIANT:-local}}"
[[ "$variant" == local || "$variant" == public ]] || { echo 'FAIL: build variant must be local or public'; exit 1; }

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
gate_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# macOS ships Bash3.2, where expanding an empty array under set -u fails.
# Both branches run the complete gate; the third argument only pins the exact
# profile bytes selected by the local build wrapper. Public builds have an
# explicit separate verifier and never invoke local profile selection.
if [[ "$variant" == public ]]; then
    [[ -z "$selected_face_profile" ]] || { echo 'FAIL: public build received a local Face Vault profile path'; exit 1; }
    python3 "$gate_directory/face_vault_signing.py" --verify-public-app "$candidate" "$previous" --require-dock-widget
elif [[ -n "$selected_face_profile" ]]; then
    python3 "$gate_directory/face_vault_signing.py" --verify-app "$candidate" "$previous" --require-dock-widget --profile "$selected_face_profile"
else
    python3 "$gate_directory/face_vault_signing.py" --verify-app "$candidate" "$previous" --require-dock-widget
fi
if [[ "$variant" == public ]]; then
    echo 'PASS: public app identity/update key and original helper preserved; Face Vault/profile excluded; Dock widget signature validated'
else
    echo 'PASS: main/all existing helper identities and update key preserved; exact Face Vault and Dock widget signatures validated'
fi
