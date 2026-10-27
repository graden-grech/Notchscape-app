#!/bin/bash
# Local custom-release entry point; unsigned CI artifacts are not install builds.
set -euo pipefail
previous="${1:?Usage: build_custom_signed_app.sh previous-trusted.app derived-data-path}"
derived="${2:?Usage: build_custom_signed_app.sh previous-trusted.app derived-data-path}"
task_repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 "$task_repo_root/.github/scripts/verify_public_feature_flags.py" "$task_repo_root/Notchscape/Info.plist"
/usr/bin/xcodebuild -quiet \
    -project "$task_repo_root/Notchscape.xcodeproj" \
    -scheme Notchscape -configuration Release -derivedDataPath "$derived" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY='Apple Development: grechgraden@icloud.com (P45575RL23)' \
    DEVELOPMENT_TEAM=6H86CTRJCP build
bash "$task_repo_root/.github/scripts/verify_custom_app_branding.sh" \
    "$derived/Build/Products/Release/Notchscape.app" "$task_repo_root/Notchscape/Info.plist"
bash "$task_repo_root/.github/scripts/verify_custom_app_identity.sh" \
    "$derived/Build/Products/Release/Notchscape.app" "$previous"
python3 "$task_repo_root/.github/scripts/verify_public_feature_flags.py" \
    "$derived/Build/Products/Release/Notchscape.app/Contents/Info.plist"
