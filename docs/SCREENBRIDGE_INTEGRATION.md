# Connected Devices local preview

ScreenBridge's Mac client is integrated into Notchscape Settings → Tools & Shortcuts → Connected Devices. This is local2.9.6/build332, separate from the published2.9.6/build330 download.

The Windows companion remains necessary: macOS software cannot receive input on Windows without a Windows process. Its compatible source/tests live in `companions/ScreenBridge`; the original project remains intact until physical migration checks pass. No existing standalone app is deleted automatically.

## Behavior

- Connect explicitly using the Windows address and current 10-character pairing code. No automatic connection or reconnect.
- Pick the Mac/Windows bridge displays and Windows' position. The existing edge-routing, emergency return shortcut and encrypted wire protocol remain compatible.
- Pairing codes/session keys stay in memory. Only address, side and selected displays are saved under separate screenBridge-prefixed preference keys.
- Disconnect releases input, cursor and modifiers. Lock, sleep, session resignation and app termination stop sharing. It cannot unlock a computer or type into loginwindow.
- Notchscape checks its own Accessibility/Input Monitoring authorization. Existing ScreenBridge authorization does not grant Notchscape additional access. Buttons only open the relevant macOS Settings page; the user controls approval.
- Standalone ScreenBridge's bundle ID is checked to avoid two clients capturing the same hardware.

## Verification on 2026-11-12

- Exact integrated Swift core ↔ .NET protocol harness passed pairing normalization, published derivation vector, wrong code, authenticated exchange, ciphertext tampering, replay rejection and four-side/selected-monitor geometry.
- RNG errors reject the handshake. Synthetic lifecycle tests use fake transport/input to verify dormant setup, cancellation, lock during readiness, ready after cancellation, reconnect, locked-message cleanup and capture failure. No OS input is injected by these tests.
- Windows companion cross-build succeeded on macOS with zero warnings/errors; platform-neutral queue tests passed. This is not a Windows runtime test.
- 114 repository Python tests and 26 signing tests (2 unavailable local fixtures skipped) passed.
- Signed local332 passed main/helper/Face/Dock identity and Sparkle-key gates. Local331 is recoverable. Existing68 checked app preferences and2 native Dock preference values stayed unchanged.
- Actual grouped Settings page, parent navigation, disconnected state, disabled remote-monitor selector and empty-address validation were inspected in the running app. No permission, camera, password, or actual remote session was operated by the agent.
- HUD event-tap checks passed after cold launch, Restart HUD and closing Settings. The user confirmed the physical volume indicator appears inside Notchscape.

## Remaining device checks

The user chose to test later and must still pair and test pointer/keyboard crossing and emergency return on both computers. The previously reported Windows-minimize failure has not been reproduced or fixed by this integration; test with the Windows window visible and minimized. Until that migration test succeeds, preserve the original standalone app and its source/recovery data. Public2.9.6 bytes/feed are unchanged by this local merge.

The custom ScreenBridge protocol has not received an independent security audit and does not provide forward secrecy. Clipboard/files are outside its current scope. Source provenance is recorded in `companions/ScreenBridge/PROVENANCE.md`.
