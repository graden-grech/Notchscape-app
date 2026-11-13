#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
DOTNET="${SCREENBRIDGE_DOTNET:-dotnet}"
TMP="$(mktemp -d)"
HARNESS_PID=""
cleanup() {
  if [[ -n "$HARNESS_PID" ]]; then kill "$HARNESS_PID" 2>/dev/null || true; fi
  rm -rf "$TMP"
}
trap cleanup EXIT
swiftc Notchscape/ScreenBridge/ScreenBridgeConnectionPolicy.swift Notchscape/ScreenBridge/ScreenBridgeWire.swift Notchscape/ScreenBridge/ScreenBridgeInput.swift Notchscape/ScreenBridge/ScreenBridgeManager.swift tests/ScreenBridgeIntegrationTests.swift -o "$TMP/integration"
"$TMP/integration"
"$DOTNET" build companions/ScreenBridge/tests/ProtocolHarness -o "$TMP/harness" --artifacts-path "$TMP/artifacts"
swiftc Notchscape/ScreenBridge/ScreenBridgeConnectionPolicy.swift Notchscape/ScreenBridge/ScreenBridgeWire.swift Notchscape/ScreenBridge/ScreenBridgeInput.swift tests/ScreenBridgeProtocolTests.swift -framework Cocoa -framework Network -framework CryptoKit -o "$TMP/protocol"
"$DOTNET" "$TMP/harness/ProtocolHarness.dll" "$TMP/frame.txt" > "$TMP/harness.log" 2>&1 &
HARNESS_PID=$!
for ((i=0;i<50;i++)); do
  if [[ -f "$TMP/frame.txt" ]]; then break; fi
  sleep 0.1
done
"$TMP/protocol" "$TMP/frame.txt"
wait "$HARNESS_PID"
HARNESS_PID=""
cat "$TMP/harness.log"
