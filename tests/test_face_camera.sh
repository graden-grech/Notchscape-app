#!/usr/bin/env bash
set -euo pipefail

face_repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
face_compiler="${FACE_CAMERA_SWIFTC:-$(xcrun --find swiftc)}"
face_sdk="${FACE_CAMERA_SDK:-$(xcrun --sdk macosx --show-sdk-path)}"
face_temp="$(mktemp -d "${TMPDIR:-/tmp}/notchscape-face-camera.XXXXXX")"
trap 'rm -rf "$face_temp"' EXIT

"$face_compiler" -sdk "$face_sdk" -swift-version 6 -strict-concurrency=complete -parse-as-library \
    "$face_repo/Notchscape/models/FaceUnlockPolicy.swift" \
    "$face_repo/Notchscape/models/FaceCameraPolicy.swift" \
    "$face_repo/Notchscape/models/CoreMLFaceEmbeddingModel.swift" \
    "$face_repo/Notchscape/managers/FaceCameraPipeline.swift" \
    "$face_repo/Notchscape/components/Settings/FaceCameraPreviewView.swift" \
    "$face_repo/tests/FaceCameraPolicyTests.swift" \
    -o "$face_temp/face-camera-tests"
"$face_temp/face-camera-tests"
