# Desktop Snow

Original optional Notchscape decoration. Enable **Add-ons → Desktop Snow** or **Appearance → Effects & Mirror → Let it snow**. It starts off, remains independent of themes and has no model download, account, microphone, camera, Accessibility or Screen Recording requirement.

## Controls

- Snowfall amount, fall speed and breeze.
- Optional static snow caps on Home’s Music, Calendar, Weather and Quick Actions tiles. These use the same rounded mound geometry and have no separate animation clock.
- Let snow settle; Clear settled snow leaves falling flakes in place.
- Optional window/macOS Dock edges. This reads geometric window metadata only; no window titles, contents or screenshots are used.
- All enabled displays, within the app's global external-display setting, or just the primary eligible display.
- Stop snow in Appearance, the app/Tools menu, or the snowflake button in an expanded notch when its left controls have sufficient room.

The basic renderer settles on the display bottom and the visible resting Notchscape Dock. With window edges enabled, exposed normal-window tops and a plausible horizontal system Dock strip are included. Verified window movement or resize can release a few gentle fragments, capped at8 per geometry update and12 alive. Focus changes, occlusion, resegmentation and disappearing banks clear quietly; switching windows does not trigger an avalanche. Full-window provenance distinguishes real motion from changes to exposed edges. Pointer eddies use a transient mouse position, without an event monitor or input history.

## Runtime

One app-owned physics clock, up to30Hz or15Hz on battery/low-impact mode. Native Core Animation layers interpolate between those samples, with stable identities and wrap fencing. There is no per-frame full-screen bitmap redraw. Hard caps apply to displays, flakes, banks, bins, burst size and geometric inputs. Optional window enumeration is at most2Hz while accumulation and window edges are on. There are no particle views, image downloads, network requests, display links, startup agents or rendering clock when disabled.

Lock, sleep, inactive session, Presentation mode, Reduce Motion, serious thermal pressure and critical unplugged battery stop rendering and remove overlays/snapshots. Quitting tears everything down. Enabling/disabling does not modify other apps, system Dock preferences or existing theme/layout choices. All clicks/drags pass through nonactivating overlays. Capture Studio pauses snow synchronously before its source picker and retains the pause through capture teardown.

## Limits and verification

Actual movement sheds gently; retained-bank acceleration, breaking sheets and exact physical snow mechanics are not implemented. Top banks are omitted for usable-area-filling and near-maximized top-attached windows, avoiding the menu-bar-clipped strip while retaining those windows as occluders. Ordinary windows retain separate rounded clumps; zero-height banks draw no hairline. Native Dock geometry covers a horizontal strip when available, not every Dock orientation/animation. Snow overlays are not claimed to be universally absent from third-party screen sharing; use Presentation mode for those workflows. The legacy NSWindow sharing flag alone is not capture exclusion.

Focused strict Swift 6 policy/runtime checks,97,691 Snow policy checks,66 catalog/security checks and40 actual Home-cap geometry checks pass with inert providers/synthetic data. Those checks are not evidence for actual compositor appearance, pointer feel, DisplayLink hardware, all display arrangements or physical HUD clearance. Local signed build/install/visual/resource results belong in the exact build checkpoint; no new release or hosted CI result is implied.


## Separate snow mountains — local build 321

Settled snow now forms distinct rounded mounds, including when every accumulation bin is full. Each supporting edge has stable mound zones with varied widths, peak positions and heights, with clear gaps at the baseline. Desktop windows/Dock retain their 11-point cap and the display bottom its 18-point cap. Zero deposits still draw no snow. Home tile caps use the same profile with a gentle static deposit; no additional animation timer was added.

Flakes land on the actual quadratic contour, including the bare baseline between piles. Collision height is evaluated with bounded scalar work and no per-particle path/array allocation. The existing cadence, elapsed-time clamp, compositor interpolation, window-occlusion handling, maximum surface/particle limits and privacy/lock/capture gates remain in place.

Validation: strict Swift 6 compilation and 125,582 synthetic snow checks passed; the 109 workflow/release-helper tests passed. Production geometry was rendered at 2× for dense window/Dock/bottom banks, sparse deposits and Home-sized edges. The exact Home cap shape also rendered at multiple tile widths. The signed local 321 app passed identity/profile/branding/Sparkle/accounts-disabled gates and was installed with a recoverable 320 backup. Actual Home captures show separate small hills on Music and Calendar. This is local validation, not hosted CI or a public release; a long, fully saturated real window/Dock buildup and every display arrangement remain separate coverage.

Artifacts and pre-test setting snapshot: `../notchscape-snow-mounds-2026-11-06`. No publication or update-feed change is part of this pass.

Build 321 completion: all 63 allowlisted settings matched after the temporary Snow preview was disabled and the original keys restored while the app was closed. HUD runtime checks passed after cold launch, Restart HUD, Settings close and final relaunch. The user confirmed the physical volume-key indicator appears inside Notchscape on build 321. Standard app capture selected the large transparent Snow overlay, so a window-specific Peekaboo capture was used to inspect the actual Home menu. Native accessibility controlled navigation; no screenshot-based clicking was needed for this pass. Dense desktop/window/Dock rendering remains a synthetic production-geometry check rather than a claim of long live saturation coverage.

## Organic spacing — local build 322

Responding to the request for less even spacing: widths now range from 24–82% of each zone, positions vary independently, and long edges include stable interior clearings. Small Home caps remain visible. Rendering and collision share the same decisions; animation cadence and flake motion are unchanged.

123,165 focused policy checks passed. The signed local build passed identity/profile/branding/Sparkle/accounts-disabled gates. Exact production path fixtures and the installed Home were visually inspected. All 63 checked preferences match the original snapshot with Snow restored off. Cold launch, Restart HUD, Settings close and final relaunch passed automatic enabled-tap checks. Human confirmation covers build 321; a new physical-key check for 322 was not obtained. No hosted CI, real updater run or publication occurred. Dense desktop/window/Dock deposits were fixture-reviewed; long live saturation and broad hardware coverage remain separate.
