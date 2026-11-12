# Glasswave and supplied reels: verified scope

Research date: 2 November 2026. This compares public vendor descriptions with the actual Notchscape source, not installed competitor binaries. “Existing” means a source implementation, not a complete hardware/live QA or release claim. Proposals below have not shipped merely because they appear here.

The gap matrix records the baseline before this task's implementation increments. See the implementation note at the end for subsequent source changes; the broader Dock/WidgetKit/developer gaps remain real.

## Sources and commercial scope

The official [Glasswave site](https://glasswave.app/) currently lists seven available apps: [Dock](https://glasswave.app/dock), [Island](https://glasswave.app/island), [Widgets](https://glasswave.app/widgets), [Tiles](https://glasswave.app/tiles), [Unlock](https://glasswave.app/unlock), [Clipboard](https://glasswave.app/clipboard), and [MenuBar](https://glasswave.app/menubar). Each is advertised at US$19.99 once, for one Mac, including 1.x updates; a launch offer gives a third app when buying two. No separate free edition was identified. Dock explicitly has no trial. Prices and offers can change. The site advertises macOS 14+, with native glass on macOS 26 and frosted fallbacks on 14/15. “Second Dock” and a separate dropdown terminal are homepage future products, not additional shipped products; Island already has a Terminal module.

Source access: the web renderer could not fetch Glasswave reliably; official public HTML was read directly. Instagram web fetches were throttled, but the two exact reels opened in the user's existing Chrome session. No competitor software was downloaded, installed, purchased, or copied.

## What the two reels actually show

1. [Ania Kubow: frosted glass](https://www.instagram.com/reel/DcwFH02NF3i/). Inspected changing video frames and visible captions: a weather-card demonstration refracts diagonal background lines, with SVG turbulence/displacement filter primitives shown. This is web refraction guidance, not a native macOS framework. We did not obtain a full audio transcript.
2. [guhmp4: native glass](https://www.instagram.com/reel/DdSm2VSsnKe/). Inspected changing frames and the caption recommending Expo's native iOS glass component. [Expo's own documentation](https://docs.expo.dev/versions/latest/sdk/glass-effect/) confirms iOS/tvOS React components and iOS 26 support, with a plain View fallback elsewhere. That package is not the implementation for this SwiftUI macOS app. No full audio transcript was obtained.

Apply the intent with [Apple's SwiftUI glass APIs](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views), grouped control surfaces and native buttons. Follow [Apple's materials guidance](https://developer.apple.com/design/human-interface-guidelines/materials): controls and navigation should remain distinct from readable content. Avoid a second fake refraction layer, whole-tile glass blankets, opacity/shadow stacks, and timers simulating light. Preserve Reduce Motion, Reduce Transparency, Increase Contrast and low-impact mode. Current source already uses native `GlassEffectContainer`/`glassEffect` in tab navigation and wallpaper controls; a visual audit is still required before claiming consistency everywhere.

## Product-level gap matrix

| Product / verified capability | Notchscape source status | Implementation / boundary |
| --- | --- | --- |
| Dock: full replacement launcher, magnification, placement, autohide, folders, Trash, widget pages/stacks | Missing product surface; existing app Dock-icon preference is unrelated | Separate architecture. Public launcher panels are possible; do not silently alter the user's Dock or claim private integration is public API. |
| Dock: 47 utility widgets | Mixed underlying capabilities, listed below | Reuse one local data model; adding a named button does not establish widget parity. |
| Island: music, lyrics, timer, battery, agenda, shelf, clipboard, notes, AI usage, color sampler, awake, mirror, downloads, devices, stats | Existing core capabilities | Different layouts/coverage. Notchscape also has weather, sports, themes, Modes and capture tools. |
| Island: embedded user shell Terminal | Missing | Opt-in PTY/session architecture, user-run commands only; stop/close lifecycle and output bounds required. Not an automatic AI command runner. |
| Island: connectivity and Focus transitions, recording indicator | Partial / verify specific events | Existing privacy/meeting indicators and Modes are not equivalent to universal OS Focus or recording detection. No dependable public API promised for arbitrary third-party recording. |
| Widgets: real desktop/Notification Center WidgetKit extension, independent instances and sizes | Missing extension target | Underlying providers are mixed; all 56 native widget presentations remain absent. Requires extension, safe shared snapshots/App Group/signing and timelines. |
| Tiles: current half/corner/fill/center actions and saved layouts | Existing limited subset | Source has 10 positions, explicit preview/restore and Undo. Requires Accessibility to move windows. |
| Tiles: thirds/fourths/sixths, custom grid, resize variants and individual shortcuts | Missing / next implementation batch | Extend pure geometry and current AX pipeline; on demand, undoable, no global preferences changed. |
| Tiles: edge snap, modifier-drag-anywhere, repeat-cycle, reserved sidebar and reconnect restore | Missing | Dedicated optional event engine later; no default global hooks or automatic window moves. |
| Unlock: face recognition and password entry convenience | Development-only implementation | Existing source is extensive; AGENTS documents a seven-day Personal Team broker. Not public-distributable and not Apple Face ID. Never first FileVault login. |
| Clipboard: encrypted opt-in history, protected-type/app exclusions, pins, image/text, retention, lock/Presentation pause | Existing | Preserve off-by-default collection, vault migration, existing records and explicit copy semantics. |
| Clipboard: fuzzy/type/date filters, named pinboards, transform preview | Missing | Suitable next local-only increment. No automatic paste/event interception necessary. |
| Clipboard: detected sensitive blur/short expiry | Missing | Best-effort detection only, never a promise that passwords cannot be saved. Short expiry must also constrain pinned records and cached previews. |
| Clipboard: direct paste, sequential paste stack, rich text/files, syntax/large preview | Missing | Separate increments with explicit permissions; copy-only fallback. No global Cmd-V interception in initial batch. |
| MenuBar: 33 independently optional status items, stable widths, style/order | Missing multi-item surface | Existing menu icon is a single app menu, not these live modules. Share providers, no duplicate sampling. |
| MenuBar: sensors, per-core/GPU, Wi-Fi details, process usage | Missing / aggregate subset only | Current System provider has aggregate CPU/RAM/storage/thermal/network/disk I/O. Read-only sensor availability varies by hardware; no fan writes. |
| Developer utilities: Git, GitHub checks/reviews, local servers, Docker, simulator state, health endpoints | Missing | Read-only bounded local adapters; separately opt-in network/CLI authorization. Never fetch/push, execute arbitrary scripts or scan ports by default. |

## Exact advertised widget/module inventories

These preserve the vendor's feature names for scope tracking, not copied UI/artwork. Shared names are one capability, not dozens of new Notchscape features.

### Dock: 47

- Time/calendar (5): Clock, Up Next, Countdown, Progress, Moon.
- Focus (7): Timer, Stopwatch, Pomodoro, To-Do, Counter, Breathe, Screen Time.
- Media (3): Now Playing, Photo Frame, Mirror.
- Mac (11): Battery, Sound, Keep Awake, Activity, Network, Mic & Camera, Storage, Lock & Sleep, Desktop Icons, Controls, Spaces.
- Developer (8): Dev Servers, Git, GitHub, Containers, Simulators, Endpoints, Timestamp, AI Usage.
- Tools (13): Note, Color Picker, Shortcuts, Appearance, Calculator, Emoji, Clipboard, Dictionary, Converter, QR Code, Generator, Text Tools, Shelf.

Existing logic includes clocks, agenda/countdown, timers/focus/stopwatch, media, mirror, battery/audio/awake/system, privacy, notes/color/calculator/snippets/links, clipboard and shelf. Gaps include progress/moon, tasks/counter/breathe, photos, Dock/system-control presentation, broader developer adapters, dictionary/generator/QR generation and richer text tools. Existing OCR recognizes QR codes; that is not QR generation. Existing Calendar supports Apple Reminders; do not list all reminders as missing. Current AI usage adapters are Codex/Claude, not the Dock page's six-provider breadth (Gemini CLI, OpenCode, Copilot CLI, Droid additionally).

### Widgets: exact 56

Every item below lacks a **native WidgetKit presentation** in Notchscape. Provider coverage is a separate question.

| Group | Exact names | Existing provider coverage / genuinely missing logic |
| --- | --- | --- |
| Music/media (4) | Now Playing; Lyrics; Photo Frame; On This Day | Music/lyrics exist; folder slideshow and Photos anniversary logic missing. |
| Clocks (8) | Sky Clock; Clock; Numerals Clock; Day and Night; Minimal Clock; Digital Clock; Flip Clock; Modular Clock | World-clock data exists; these faces, solar globe and progress compositions absent. |
| Day (17) | Up Next; Calendar Month; Countdown; Today at a Glance; Timer; Pomodoro; Focus Time; Stopwatch; Weekend; Birthdays; Progress; To-Do; Note; Year in Dots; Moon; Daylight; Word of the Day | Agenda/month/countdown/timer/focus/stopwatch/note exist. Focus history/goals, weekend/holidays, Contacts birthdays, local task list, period/year progress, moon/daylight/dictionary logic absent. |
| Mac (11) | Battery; Devices; Temperature and Fans; Activity; Network; Mac Health; Wi-Fi Signal; Storage and Drives; Top Apps; Disk Activity; Time Machine | Battery/devices/aggregate activity/network/disk I/O exist. Hardware sensors/GPU/process ranking/Wi-Fi metrics/multi-drive eject/backup status missing; health has only aggregate pressure/thermal subset. |
| Screen Time (6) | Screen Time; Screen Time Week; Categories; Breaks; App Time; Most Used | Missing. The vendor requests Full Disk Access to existing Screen Time records; do not mirror that private database approach. A transparent opt-in own-session focus/break tracker is a different feature. |
| Developer (10) | AI Usage; GitHub Actions; GitHub; Git; GitHub Contributions; Dev Servers; Containers; Endpoints; Commands; Reviews | Codex/Claude usage exists; remaining adapters absent. Commands is a security-sensitive user-script feature, not an automatic follow-up to Quicklinks. |

Widget engineering caveat: [Apple documents WidgetKit reload budgets and non-continuous extension execution](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date). Do not repeat a blanket promise of arbitrary live updates every two seconds; use timeline-driven dates/countdowns and system-supported refresh policy. A widget is not a second always-running dashboard.

### Tiles: exact 42 advertised placements/actions

- Halves (5): Left, Right, Centre Half, Top, Bottom.
- Corners (4): Top Left, Top Right, Bottom Left, Bottom Right.
- Thirds (6): First, Centre, Last Third; First, Centre, Last Two Thirds.
- Fourths (7): First, Second, Third, Last Fourth; First, Centre, Last Three Fourths.
- Sixths (6): Top/Bottom × Left/Centre/Right.
- Size (6): Maximize, Almost Maximize, Maximize Height, Maximize Width, Make Larger, Make Smaller.
- Place (8): Center, Restore, Move Left/Right/Up/Down, Next/Previous Display.

Do not confuse these named actions with a complete edge-drag engine. Existing Notchscape saved layouts use explicit review and skip unopened apps. Preserve that safer restore behavior; automatic monitor-reconnect moves are a separate opt-in policy.

### MenuBar: exact 33

- System (8): Overview, CPU, Memory, Disk, Network, Battery, GPU, Sensors.
- Developer (8): AI Usage, Git, Dev Servers, Docker, Ping, VPN, Wi-Fi, Uptime.
- Day (5): Calendar, World Clocks, Timers, Keep Awake, Now Playing.
- Everyday (12): Notes, To-Dos, Countdown, Stopwatch, Shelf, Colours, Appearance, Device Batteries, Reminders, Eject, Sun and Moon, Date.

This app adds its own items; it does not hide other vendors' icons. It is not Bartender parity. Monitoring should stop at lock/sleep/session change, keep brief history in bounded memory only and avoid constant-width jitter. New modules default off. Network probes and location-derived daylight require separate explicit enablement. Do not change macOS appearance automatically as part of enabling a module.

## Practical implementation batches

1. **Shared visual/lifecycle foundation:** native control glass, grouped containers, readable content, no fake shader blanket. Use one accent/material system across existing pages and new modules. Verify accessibility and both display shapes; honor existing performance mode.
2. **Clipboard local increment:** encrypted optional named boards, whole-content fuzzy/type search, preview-and-copy transformations, best-effort sensitive hiding with brief retention. No real-clipboard test capture or account/network permission needed. Keep old records decodable. This batch is now assigned, not yet implemented at the time of this audit.
3. **Precision windows:** extend geometry and grid, preserve existing permission/Undo/preview boundaries. No silent Dock/tiling/Stage Manager preferences, global dragging, app launching or automatic monitor restore.
4. **Optional menu snapshots:** start with a small reusable set backed by existing providers; enable items individually, stable widths, visible-only sampling. Expand read-only developer/system sources after the provider and lifecycle contract is verified.
5. **New product architectures later:** WidgetKit extension, replacement Dock and user shell require dedicated review/build/distribution work. Unlock distribution remains blocked by the documented development-signing limitation. Do not claim full-suite parity while these remain absent.

## Source evidence checked in Notchscape

- `Notchscape/models/ProductivityModels.swift`: original Codable clipboard, protected types, bounds/retention; Quick Notes and reminder-safe Notes sync models.
- `Notchscape/managers/LocalToolsManager.swift`: encrypted vault, optional clipboard polling, lock/Presentation gates, explicit copy.
- `Notchscape/components/Settings/ProductivityViews.swift`: original substring search, text/image list and simple pin UI.
- `Notchscape/models/WindowGeometry.swift`, `Notchscape/managers/WindowTools.swift`: 10 placements, bounded AX scan/move, explicit saved layouts/Undo.
- `Notchscape/managers/SystemPerformanceManager.swift`: aggregate metrics and lifecycle task, not per-process/SMC fan control.
- `Notchscape/models/WorkspaceToolsModels.swift`, `Notchscape/managers/WorkspaceClockManager.swift`, `Notchscape/managers/WorkspaceActions.swift`: existing calculator, personal tools, clocks/focus/awake and opening-only Shortcuts.
- `Notchscape/components/Settings/FeatureCatalogueView.swift`: feature coverage and unavailable real music queue disclosed.
- `Notchscape/components/LiquidGlassStyle.swift`, `Notchscape/components/Tabs/TabSelectionView.swift`, `Notchscape/components/Settings/WallpaperViews.swift`: native controls/glass already in use; consistency still needs live QA.
- `Notchscape.xcodeproj/project.pbxproj`: no current WidgetKit extension target; `Notchscape/menu/StatusBarMenu.swift` is the existing single menu surface.

No competitor code, protected brand assets, license system or marketing performance numbers were adopted. Research is not proof that competitor privacy, anti-spoofing, latency or battery claims hold in independent testing.

## Subsequent implementation note

Clipboard source now adds encrypted local named boards; type/date/pins filters; whole-text exact and bounded loose search; local image/text preview; and 12 preview-and-copy transforms. Best-effort token/card/code detection hides results until Reveal. Newly captured/re-copied detections have a 10-minute expiry even when pinned; legacy saved copies are classified/hidden but preserved without imposing a new destructive expiry. Existing recording defaults, encrypted key/path, count/byte bounds and protected-type exclusions remain.

The new native Add-ons Store source lists Features, Theme Packs and Installed with honest bundled/unpublished/local-only status. Its image-only content policy verifies a signed payload, fixed publishers/pack IDs, exact own-repository HTTPS paths, compatibility, byte/file/hash/path/type/pixel rules and regular-file staging. Shipping publisher trust is deliberately unconfigured. There is no actual downloader/installer and no published pack represented as available.

Synthetic checks pass: 59 new clipboard policies, 90 unchanged existing productivity policies, and 50 add-on policies. The Add-ons model/view typecheck with a no-op Settings-controller stub; all three clipboard files parse. Combined-app build, live UI, install and release outcomes are separate parent-agent checks, not claimed here. Tests never read the real clipboard, decrypt the user's vault, enable recording, or activate a module. [Core/add-on architecture proposal](OPTIONAL_ADDONS_ARCHITECTURE_PROPOSAL.md) documents the remaining packaging and removal work.


## Current-site refresh and Dock increment

Later on2November2026 the official https://glasswave.app/dock redirected to https://zincwolf.app/dock and the page displayed ZincWolf branding,47Dockwidgets and2.x update terms. Earlier brand/version observations above are historical, not a current naming claim. The Dock workspace increment is an independent native implementation with five starter cards, explicitly user-opened app/folder pins and saved reordering. It does not replace the macOS Dock or implement the full47-widget inventory. This source increment must still pass its own signed-build/install/live checks before being called installed. The Store now has search and native feature details, but genuine downloadable modules/WidgetKit remain outstanding.
