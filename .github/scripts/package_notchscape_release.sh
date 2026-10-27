#!/bin/bash
# Prepare a new immutable local candidate. Never uploads or modifies an appcast.
set -euo pipefail
candidate="${1:?Usage: package_notchscape_release.sh candidate.app trusted.app output-directory}"
previous="${2:?Usage: package_notchscape_release.sh candidate.app trusted.app output-directory}"
output="${3:?Usage: package_notchscape_release.sh candidate.app trusted.app output-directory}"
task_repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
archive="$output/Notchscape.zip"
[[ ! -e "$archive" ]] || { echo 'FAIL: never overwrite an existing release archive' >&2; exit 1; }
bash "$task_repo_root/.github/scripts/verify_custom_app_branding.sh" "$candidate" "$task_repo_root/Notchscape/Info.plist"
bash "$task_repo_root/.github/scripts/verify_custom_app_identity.sh" "$candidate" "$previous"
python3 "$task_repo_root/.github/scripts/verify_public_feature_flags.py" "$candidate/Contents/Info.plist"
python3 "$task_repo_root/.github/scripts/verify_shared_install.py" "$candidate"
mkdir -p "$output"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$candidate" "$archive"
python3 "$task_repo_root/.github/scripts/verify_distribution_archive.py" "$archive"
/usr/bin/shasum -a 256 "$archive"
printf 'Prepared local candidate only. Sparkle signature, notarization, runtime tests and publication remain separate.\n'
