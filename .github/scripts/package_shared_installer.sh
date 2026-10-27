#!/bin/bash
# Build only; never installs, uploads, changes an appcast or grants permissions.
set -euo pipefail
candidate="${1:?Usage: package_shared_installer.sh candidate.app trusted.app output-directory [--unsigned-preview]}"
previous="${2:?Trusted app required}"
output="${3:?Output directory required}"
preview="${4:-}"
task_repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
package="$output/Notchscape.pkg"
[[ ! -e "$package" ]] || { echo 'FAIL: never overwrite an installer' >&2; exit 1; }
signer="${NOTCHSCAPE_INSTALLER_SIGN_IDENTITY:-}"
if [[ -z "$signer" && "$preview" != --unsigned-preview ]]; then
    echo 'FAIL: Developer ID Installer identity required; use --unsigned-preview only for an unpublished local test.' >&2
    exit 1
fi
if [[ -n "$signer" && "$signer" != 'Developer ID Installer: '* ]]; then
    echo 'FAIL: installer signing requires a Developer ID Installer identity, not an app development identity.' >&2
    exit 1
fi
bash "$task_repo_root/.github/scripts/verify_custom_app_branding.sh" "$candidate" "$task_repo_root/Notchscape/Info.plist"
bash "$task_repo_root/.github/scripts/verify_custom_app_identity.sh" "$candidate" "$previous"
python3 "$task_repo_root/.github/scripts/verify_public_feature_flags.py" "$candidate/Contents/Info.plist"
python3 "$task_repo_root/.github/scripts/verify_shared_install.py" "$candidate"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$candidate/Contents/Info.plist")"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'FAIL: invalid installer version' >&2; exit 1; }
mkdir -p "$output"
task_stage="$(mktemp -d "$output/installer-stage.XXXXXX")"
mkdir "$task_stage/root"
/usr/bin/ditto "$candidate" "$task_stage/root/Notchscape.app"
/usr/bin/pkgbuild --root "$task_stage/root" --install-location /Applications \
    --component-plist "$task_repo_root/Configuration/installer/Components.plist" \
    --identifier com.notchscape.installer.app --version "$version" \
    --ownership recommended "$task_stage/Notchscape-component.pkg"
build_args=(--distribution "$task_repo_root/Configuration/installer/Distribution.xml"
    --resources "$task_repo_root/Configuration/installer/Resources" --package-path "$task_stage")
if [[ -n "$signer" ]]; then build_args+=(--sign "$signer"); fi
/usr/bin/productbuild "${build_args[@]}" "$package"
/usr/bin/shasum -a 256 "$package"
if [[ -z "$signer" ]]; then
    echo 'UNSIGNED LOCAL PREVIEW ONLY: not a customer release; installer signing and notarization are still required.'
else
    /usr/sbin/pkgutil --check-signature "$package"
    echo 'Prepared signed installer only. Notarization, live installation and publication remain separate.'
fi
