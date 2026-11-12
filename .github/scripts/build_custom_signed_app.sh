#!/bin/bash
# Local custom-release entry point; unsigned CI artifacts are not install builds.
set -euo pipefail
previous="${1:?Usage: build_custom_signed_app.sh previous-trusted.app derived-data-path}"
derived="${2:?Usage: build_custom_signed_app.sh previous-trusted.app derived-data-path}"
task_repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
variant="${NOTCHSCAPE_BUILD_VARIANT:-local}"
[[ "$variant" == local || "$variant" == public ]] || { echo 'FAIL: NOTCHSCAPE_BUILD_VARIANT must be local or public' >&2; exit 1; }
python3 "$task_repo_root/.github/scripts/verify_public_feature_flags.py" "$task_repo_root/Notchscape/Info.plist"
# The new ordinary Dock child has no profile/entitlements. Resolve its exact
# certificate from the trusted app without overriding existing target signing.
dock_signing_identity=$(python3 "$task_repo_root/.github/scripts/face_vault_signing.py" --dock-signing-identity "$previous")
profile_arguments=()
project_path="$task_repo_root/Notchscape.xcodeproj"
info_path="$task_repo_root/Notchscape/Info.plist"
if [[ "$variant" == local ]]; then
    # Only the local Face Vault broker uses Xcode-managed free development
    # provisioning. Main and original helper retain their existing signing.
    profile_arguments=(--select-profile)
    if [[ -n "${NOTCHSCAPE_FACE_PROFILE_PATH:-}" ]]; then
        profile_arguments+=(--profile "$NOTCHSCAPE_FACE_PROFILE_PATH")
    fi
    IFS=$'\t' read -r face_profile_path face_profile_uuid face_profile_expiration < <(
        python3 "$task_repo_root/.github/scripts/face_vault_signing.py" "${profile_arguments[@]}"
    )
    [[ -n "$face_profile_path" && -n "$face_profile_uuid" && -n "$face_profile_expiration" ]] || {
        echo 'FAIL: a valid local Face Vault development profile is required' >&2; exit 1;
    }
else
    # Public downloads must not contain this device-bound development broker
    # or its seven-day provisioning profile. Generate an isolated project copy
    # so the local project and developer workflow remain untouched.
    public_project_tmp=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/notchscape-public-project.XXXXXX")
    generated=$(python3 "$task_repo_root/.github/scripts/generate_public_project.py" \
        "$task_repo_root/Notchscape.xcodeproj" "$task_repo_root/Notchscape/Info.plist" "$public_project_tmp")
    project_path=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["project"])' "$generated")
    info_path=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["info_plist"])' "$generated")
fi

build_settings=(
    NOTCHSCAPE_DOCK_SIGNING_IDENTITY="$dock_signing_identity"
)
if [[ "$variant" == local ]]; then
    build_settings+=(NOTCHSCAPE_FACE_PROFILE_EXPIRATION="$face_profile_expiration")
else
    # SRCROOT is global so copied project references still resolve to this
    # checkout. The app-only generated Info.plist is set on the main target by
    # the project generator; never pass INFOPLIST_FILE globally because that
    # would overwrite the helper and Dock child plists too.
    build_settings+=(SRCROOT="$task_repo_root")
fi
if [[ -n "${NOTCHSCAPE_BUILD_NUMBER:-}" ]]; then
    build_settings+=(CURRENT_PROJECT_VERSION="$NOTCHSCAPE_BUILD_NUMBER")
fi
/usr/bin/xcodebuild -quiet \
    -project "$project_path" \
    -scheme Notchscape -configuration Release -derivedDataPath "$derived" \
    "${build_settings[@]}" build
bash "$task_repo_root/.github/scripts/verify_custom_app_branding.sh" \
    "$derived/Build/Products/Release/Notchscape.app" "$info_path"
bash "$task_repo_root/.github/scripts/verify_custom_app_identity.sh" \
    "$derived/Build/Products/Release/Notchscape.app" "$previous" \
    "${face_profile_path:-}" "$variant"
python3 "$task_repo_root/.github/scripts/verify_public_feature_flags.py" \
    "$derived/Build/Products/Release/Notchscape.app/Contents/Info.plist"
