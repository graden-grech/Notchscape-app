#!/bin/bash
# Run against the real SDK with synthetic in-memory data; never real credentials.
set -euo pipefail
task_repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
task_test_directory="$(mktemp -d "${RUNNER_TEMP:-/tmp}/notch-account-sdk.XXXXXX")"
cp "$task_repo_root/tests/accounts-sdk/Package.swift" "$task_test_directory/Package.swift"
cp "$task_repo_root/tests/accounts-sdk/StorageRegression.swift" "$task_test_directory/StorageRegression.swift"
cp "$task_repo_root/Notchscape/managers/AccountCredentialStorage.swift" "$task_test_directory/AccountCredentialStorage.swift"
swift run --package-path "$task_test_directory" \
  --scratch-path "$task_repo_root/tests/accounts-sdk/.build" AccountStorageRegression
