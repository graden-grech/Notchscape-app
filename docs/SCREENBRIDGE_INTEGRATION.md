# Connected Devices local preview

ScreenBridge's Mac client is integrated into Notchscape Settings → Tools & Shortcuts → Connected Devices. This is local2.9.6/build333, separate from the published2.9.6/build330 download.

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
- Signed local333 passed main/helper/Face/Dock identity and Sparkle-key gates. Local331 is recoverable. Existing68 checked app preferences and2 native Dock preference values stayed unchanged.
- Actual grouped Settings page, parent navigation, disconnected state, disabled remote-monitor selector and empty-address validation were inspected in the running app. No permission, camera, password, or actual remote session was operated by the agent.
- HUD event-tap checks passed on final333 after cold launch, Restart HUD and closing Settings. The user confirmed the physical volume indicator on332 before the final tour-grouping/local-network-purpose refinement.95 guided-settings checks pass, keeping Connected Devices under the Tools tour card.

## Remaining device checks

The user chose to test later and must still pair and test pointer/keyboard crossing and emergency return on both computers. The previously reported Windows-minimize failure has not been reproduced or fixed by this integration; test with the Windows window visible and minimized. Until that migration test succeeds, preserve the original standalone app and its source/recovery data. Public2.9.6 bytes/feed are unchanged by this local merge.

The custom ScreenBridge protocol has not received an independent security audit and does not provide forward secrecy. Clipboard/files are outside its current scope. Source provenance is recorded in `companions/ScreenBridge/PROVENANCE.md`.

## Recoverable cleanup

After local integration checks, three standalone ScreenBridge compiler outputs (1,027,216 bytes) were moved to Trash. The original app/source and Windows companion remain for the deferred physical test. The external checkpoint folder holds the original-to-Trash manifest; no settings, credentials, biometric data or source were deleted.

## Control direction

The local direction update adds a native Control direction picker: Both computers (the compatibility default), Mac controls Windows, and Windows controls Mac. It is separate from Windows' physical screen position. A direction change releases current keys/buttons and returns control locally before applying the new rule; it does not disconnect the socket or swap monitor arrangement. Windows' existing v1 enter/reject messages remain compatible, so no companion replacement is needed for this setting.

The user confirmed Mac-to-Windows control on November13. Windows-to-Mac physical validation is deferred because the user left the PC. Read-only Windows checks confirmed the existing opposite-edge portal and outgoing enter/move/key handling. Synthetic direction/lifecycle/persistence checks and exact Swift/.NET interoperability passed. The expired local Face helper development profile was renewed on the existing team through November20; it remains device-bound and excluded from public downloads. No camera, vault, password or biometric test was performed.

Direction update local334 was installed and visually checked. The picker was tested with Windows controls Mac and restored to Both computers. Signed identity,114 repository checks, protocol/lifecycle tests and three HUD runtime checks passed;68 checked existing app settings and2 native Dock values stayed unchanged. Physical reverse control remains untested pending the user’s return to Windows.
