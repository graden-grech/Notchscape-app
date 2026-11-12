#!/usr/bin/env bash
set -euo pipefail

face_session_repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
face_session_compiler="${FACE_CAMERA_SWIFTC:-$(xcrun --find swiftc)}"
face_session_sdk="${FACE_CAMERA_SDK:-$(xcrun --sdk macosx --show-sdk-path)}"
face_session_temp="$(mktemp -d "${TMPDIR:-/tmp}/notchscape-face-session.XXXXXX")"
trap 'rm -rf "$face_session_temp"' EXIT

"$face_session_compiler" -sdk "$face_session_sdk" -swift-version 6 -strict-concurrency=complete -parse-as-library \
    "$face_session_repo/Notchscape/models/FaceUnlockPolicy.swift" \
    "$face_session_repo/Notchscape/models/FaceCameraPolicy.swift" \
    "$face_session_repo/Notchscape/models/FaceRecognitionSessionPolicy.swift" \
    "$face_session_repo/tests/FaceRecognitionSessionPolicyTests.swift" \
    -o "$face_session_temp/face-session-tests"
"$face_session_temp/face-session-tests"
