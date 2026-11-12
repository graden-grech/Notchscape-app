#!/bin/bash
# Synthetic/default-deny checks only: no valid setup/auth, camera or input output.
set -euo pipefail
task_repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
task_test_dir="$(mktemp -d "${TMPDIR:-/tmp}/notchscape-face-tests.XXXXXX")"
trap 'rm -rf "$task_test_dir"' EXIT
task_swiftc="$(xcrun --find swiftc)"
task_sdk="$(xcrun --sdk macosx --show-sdk-path)"
"$task_swiftc" -sdk "$task_sdk" -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
  "$task_repo_root/Notchscape/models/FaceUnlockPolicy.swift" \
  "$task_repo_root/tests/FaceUnlockPolicyTests.swift" -o "$task_test_dir/policy"
"$task_test_dir/policy"
"$task_swiftc" -sdk "$task_sdk" -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
  "$task_repo_root/Notchscape/models/FaceUnlockPolicy.swift" \
  "$task_repo_root/NotchscapeFaceVault/FaceVaultXPCProtocol.swift" \
  "$task_repo_root/Notchscape/managers/FaceVaultKeyBrokerClient.swift" \
  "$task_repo_root/Notchscape/managers/FaceUnlockVault.swift" \
  "$task_repo_root/tests/FaceUnlockVaultTests.swift" -o "$task_test_dir/vault"
"$task_test_dir/vault"
"$task_swiftc" -sdk "$task_sdk" -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
  "$task_repo_root/Notchscape/models/FaceUnlockPolicy.swift" \
  "$task_repo_root/NotchscapeFaceVault/FaceVaultXPCProtocol.swift" \
  "$task_repo_root/Notchscape/managers/FaceVaultKeyBrokerClient.swift" \
  "$task_repo_root/Notchscape/managers/FaceUnlockVault.swift" \
  "$task_repo_root/tests/FaceUnlockVaultIntegrationTests.swift" -o "$task_test_dir/vault-integration"
"$task_test_dir/vault-integration"
"$task_swiftc" -sdk "$task_sdk" -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
  "$task_repo_root/Notchscape/models/FaceUnlockPolicy.swift" \
  "$task_repo_root/Notchscape/models/ScreenUnlockPolicy.swift" \
  "$task_repo_root/tests/ScreenUnlockPolicyTests.swift" -o "$task_test_dir/screen-policy"
"$task_test_dir/screen-policy"
"$task_swiftc" -sdk "$task_sdk" -swift-version 6 -strict-concurrency=complete -warnings-as-errors -typecheck \
  "$task_repo_root/Notchscape/models/FaceUnlockPolicy.swift" \
  "$task_repo_root/Notchscape/models/ScreenUnlockPolicy.swift" \
  "$task_repo_root/Notchscape/managers/ScreenUnlockAction.swift"
bash "$task_repo_root/tests/test_face_recognition_session.sh"
FACE_CAMERA_MODEL_PACKAGE="$task_repo_root/Notchscape/Resources/FaceModels/SFace.mlpackage" \
FACE_CAMERA_SYNTHETIC_REFERENCE="$task_repo_root/tests/fixtures/sface-synthetic-reference.json" \
  bash "$task_repo_root/tests/test_face_camera.sh"
