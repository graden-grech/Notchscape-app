# ScreenBridge Integration Implementation Plan

**Goal:** Merge the existing Mac ScreenBridge client into Notchscape as an optional Connected Devices page, while retaining the Windows companion.

**Architecture:** Reuse the user's authenticated wire format and event-routing core with scoped names. A main-thread service owns one session, enabled only by Connect. Native SwiftUI settings expose pairing, monitor selection, side, status, Disconnect and Return Control. No extra Mac app/window is launched. Existing Windows protocol remains compatible.

**Tech Stack:** SwiftUI, AppKit/CoreGraphics, Network, CryptoKit/CommonCrypto; existing .NET Windows companion.

## Constraints and decisions

- Integration adds a module; no major rewrite of either app or changes to public2.9.6 bytes/feed.
- Connection and input capture are off by default, never automatically reconnect, and stop on lock, sleep, session resignation and app termination.
- Pairing codes/session keys stay in memory, never in defaults or logs. Host/display/side choices use separate screenBridge-prefixed keys; original app settings stay untouched.
- Controls do not request unexpected privileges. Permissions open only through explicit user action.
- Keep the tested background handoff and protocol. Windows minimize issue remains unverified until tested on Windows; no remote input tests through agent tools.
- Original ScreenBridge sources remain untouched. Keep provenance and Windows build/test source in companions/ScreenBridge, no binary caches or user connection files.

## Implementation

- [x] Import scoped protocol/geometry/input core and add synthetic protocol/tamper/replay/geometry checks against those exact files.
- [x] Add explicit session service, stale-callback cancellation, lock/sleep disconnect and safe local return; test dormant/invalid input states without installing an event tap.
- [x] Add native grouped Connected Devices page under Tools, monitor pickers, side controls, secure code entry, search/deep link, privacy/compatibility explanation.
- [x] Build signed local candidate using trusted local331 identity; run policy checks and inspect actual UI with no connection/camera/permission changes.
- [x] Preserve current settings and recovery copy; install only validated build, test HUD lifecycle and ask human for physical cross-device checks.

## Review focus

Stale pairing callbacks after Cancel; lock/sleep during remote control; unavailable/changing monitor IDs; two simultaneous Mac clients; input tap coexistence with HUD; Windows minimized behavior. Synthetic tests cannot prove actual device handoff or Windows injection.
