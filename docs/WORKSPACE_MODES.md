# Temporary workspace Modes

Settings → Modes previews eight optional setups. The menu-bar menu and notch
context menu also offer quick activation. Only one Mode is active at a time.
An active-state indicator/menu and End Mode command keep the override visible.

Modes are in-memory effective-setting overlays, not a batch of saved preference
changes. Ending one uses the user's current settings, including manual edits made
while it was active. Nothing is restored from a stale snapshot. Quitting ends it.

| Mode | Implemented effective changes |
| --- | --- |
| Work | Quiet music, sports, weather and download activities; Calendar/actions first. |
| Study | Quiet AI, sports, weather and download activities; Calendar/actions first. |
| Presentation | Hide expanded notch/Tools content; close Tools and mirror; pause clipboard recording, all live activities and automatic wallpaper changes; click to open. |
| Gaming | Low-impact rendering/refresh, quiet live activities, click to open. |
| Travel | Low-impact rendering/refresh, quiet sports/download activities, pause automatic wallpaper changes. |
| Creative | Music-first priority/layout; quiet AI, Calendar, sports, weather and download activities. |
| Developer | AI-first priority; quiet music, sports and weather activities. |
| Minimal | Low-impact rendering/refresh, quiet live activities, click to open. |

Normal feature-off switches, selected activity profiles, lock-screen privacy and
permissions still win. A Mode never enables a disabled tile, recording, camera,
microphone, location, accounts or cloud sync. Low-impact never disables an existing
Low Power/Reduce Motion choice. Volume/brightness HUD permission is unchanged.

## Duration and privacy

Other modes optionally end after 30 minutes or one hour, using the visible local
wall-clock end. Wake and clock-change events reconcile that expiry without a
polling timer. Replacement/end cancels the old expiry task.

**Presentation never ends on a timer**, even if another duration was selected
before choosing it. End it explicitly when sharing is finished, or quit the app.
Its clipboard pause is separate from the user's pause, and delayed OCR results
are discarded. It does not secure/redact other apps, notifications, the desktop,
or an already-open system capture/image picker. Do not treat it as screen-sharing
security. Camera and lock-screen protections require separate live testing.

Wallpaper rotation pauses without changing the saved interval. An in-flight
automatic request is cancelled/rechecked; a deliberate manual Apply/Undo still
works. Clipboard recording never captures a copy from before resuming.

The remaining feature and theme proposals are listed separately in
[the research shortlist](FEATURE_GAPS_AND_MODES.md); they are not all implemented.

Policy regression: `tests/WorkspaceModePolicyTests.swift`. Build, permission,
live presentation/camera and supported-device checks remain separate.
