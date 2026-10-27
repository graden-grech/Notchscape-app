# Locked Home dropdown (experimental)

Advanced → Lock Screen → **Show locked Home dropdown** reuses the existing
`showOnLockScreen` preference. It remains off by default. No other appearance,
privacy, permission or display preference is changed by installation.

When the session locks and the option is enabled, the app hides its notch
windows, detaches the entire normal SwiftUI menu hierarchy and installs an
isolated `LockedNotchHomeView` before moving windows into the inherited SkyLight
lock-screen space. It does not overlay a lock image over accessible private
widgets. The closed notch/island remains plain and at its normal width, with
no lock badge or extra side lanes. Hovering (when hover-to-open is enabled)
or clicking shows only a lock symbol inside the expanded Home dropdown.
The unlock instruction is provided to accessibility users, not as visible text.

The isolated view has no references to account, calendar, Shelf, music metadata,
weather/location or AI managers. It has no Settings, Mirror, file-drop, shortcut
or private-data actions. Expanded drag detection is disabled while locked. Only
this app's Mirror camera session is stopped; it is not resumed automatically.

Unlocking keeps the privacy tree through the short transition, leaves the
lock-screen space and then restores the normal menu. A rapid re-lock cancels
any pending restoration. A missing launch session dictionary fails closed.
The existing distributed lock notifications and `CGSSessionScreenIsLocked`
session key are private/best-effort platform details, not a new authentication
boundary. The OS still owns and enforces unlocking.

**Preview Locked Home** swaps in the same isolated view while the Mac is unlocked.
It does not lock the Mac, change the preference, or join the lock-screen space.
End Preview or the 30-second timer returns to Settings. Ending a preview after
a real screen lock cannot restore private content.

This depends on the repository's existing **private SkyLight** integration.
It is not an official macOS lock-screen extension and must not be advertised as
working on every macOS release. Do not broaden permissions, create credential
prompts or inject input into loginwindow to work around mouse-event limitations.

Before claiming a live pass: verify the isolated preview's expanded accessibility
tree and visual layout; lock/unlock on the signed installed app with the option
on and off; check actual hover/click delivery, multiple displays, rapid re-lock,
and HUD recovery. Keep untested cases explicit in release notes.

## Verification on 2026-10-15

The signed 2.9.0-beta.1/build 285 preview passed the isolated preview layout and
accessibility-tree inspection: only the lock, unlock message and preview-only
exit button were present. Automatic preview exit restored normal Settings.
The owner confirmed that the real locked dropdown opened, Home returned after
unlocking, and a real volume key still displayed the notch HUD. The enabled HUD
event-tap check also passed after unlock. The existing enabled lock-screen
preference and ten other protected stored preferences were preserved.

Pure policy checks cover locked/on, locked/off, unlocked and preview combinations.
Real lock-screen off/on transitions, rapid re-lock, multiple screens, startup
while already locked, and other macOS versions remain unverified.

The subsequent local 2.9.0-beta.2/build 286 correction removes the closed lock
badge and its extra width, and removes the visible unlock text. The isolated
preview was inspected collapsed (no lock image) and expanded (only the lock,
plus the preview-only exit button). Signing identity, 107 policy checks and HUD
event-tap checks after cold launch, Restart HUD and closing Settings pass; all
eleven stored protected preferences are unchanged. A new real lock/unlock or
Sparkle installation was not repeated for this visual-only correction. This
local build has not replaced or modified the published beta.1 archive.
