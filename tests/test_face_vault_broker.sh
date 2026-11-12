#!/usr/bin/env bash
set -euo pipefail
broker_repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
broker_compiler="${FACE_CAMERA_SWIFTC:-$(xcrun --find swiftc)}"
broker_sdk="${FACE_CAMERA_SDK:-$(xcrun --sdk macosx --show-sdk-path)}"
broker_temp="$(mktemp -d "${TMPDIR:-/tmp}/notchscape-face-broker.XXXXXX")"
trap 'rm -rf "$broker_temp"' EXIT
"$broker_compiler" -sdk "$broker_sdk" -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
    "$broker_repo/NotchscapeFaceVault/FaceVaultXPCProtocol.swift" \
    "$broker_repo/NotchscapeFaceVault/FaceVaultBrokerPolicy.swift" \
    "$broker_repo/NotchscapeFaceVault/FaceVaultBrokerPeerVerifier.swift" \
    "$broker_repo/tests/FaceVaultBrokerPolicyTests.swift" -o "$broker_temp/tests"
"$broker_temp/tests"
"$broker_compiler" -sdk "$broker_sdk" -swift-version 6 -strict-concurrency=complete -warnings-as-errors -typecheck \
    "$broker_repo/NotchscapeFaceVault/FaceVaultXPCProtocol.swift" \
    "$broker_repo/NotchscapeFaceVault/FaceVaultBrokerPolicy.swift" \
    "$broker_repo/NotchscapeFaceVault/FaceVaultBrokerPeerVerifier.swift" \
    "$broker_repo/NotchscapeFaceVault/FaceVaultBrokerService.swift" \
    "$broker_repo/NotchscapeFaceVault/main.swift"
python3 "$broker_repo/tests/test_face_vault_signing.py"
