# Expanded feature implementation

Scope approved: 21 October 2026. Updated 23 October. All 30 research candidates
have been addressed below, but **addressed does not mean all implemented or fully
tested**. Version **2.9.0 (289)** integrates this feature batch with the published
2.8.5 AI chat-title fix. The older release/download and feed entries are retained.
Accounts remain disabled. The detailed table distinguishes implemented features,
completed isolated tests, and hardware/live checks that remain unverified; this
is not a claim of Apple certification or universal production readiness.

| # | Feature | Current status |
| --- | --- | --- |
| 1 | Shared action registry / command palette | Implemented; installed search→Capture/Settings/Windows and app-local ⇧⌘K after cold launch passed. Native Tools menu added; no default global shortcut stolen from other apps. |
| 2 | Local calculator, units and dates | Implemented; policy checks and installed `2*(3+4)=14` passed. No shell/eval/network currency guessing. |
| 3 | Encrypted text snippets | Implemented, explicit Copy/edit/remove, 100 records/20k text. Pure bounds/legacy optional-field checks pass; live save/copy/delete not exercised against user storage. |
| 4 | Named Quicklinks / searches / folders | Implemented; http(s), escaped query templates and scoped folder bookmarks. URL safety checks pass; real folder/browser opening pending. |
| 5 | Color formats and saved swatches | Implemented; Hex/RGB/HSL/Swift and encrypted swatches. Pure format/bounds tests pass; swatch save/remove not live-tested. |
| 6 | Stopwatch and laps | Implemented; ContinuousClock includes sleep, visible-only rendering. Installed start/lap/pause/reset passed; test laps reset. |
| 7 | Focus work/break cycles | Implemented, work/break/round bounds and pause/resume/end. Installed start/end passed; full multi-round/wake test pending. |
| 8 | Pinned event countdown | Implemented for the currently loaded calendar day using existing access only. Selection follows edits/deletions/day changes, session-only; real event selection test pending. |
| 9 | Real player Up Next | **Not implemented: capability limitation.** Current Spotify/Apple Music scripting and system connections expose no reliable real queue. UI explains this and opens the player; never substitutes a playlist/fake queue. A separately authorized player-supported integration is still required. |
| 10 | Watched download folders | Implemented, 8 explicit bookmarks, bounded metadata, idle filesystem events / active progress checks. Off/lock/Presentation releases observers/scopes. Additional-folder native test pending. |
| 11 | Local QR/barcode recognition | Implemented alongside existing OCR. Harmless generated Vision QR fixture passed; bounded payloads and no automatic link opening. |
| 12 | Screenshot markup / flattened redaction | Implemented arrows/text/crop/opaque redaction, keyboard coordinate alternative, bounded preview cache. Pixel/crop/metadata fixtures pass; installed choose→place redaction→PNG export passed, exported pixels checked black/opaque and original remained red. |
| 13 | Opt-in searchable capture library | Implemented explicit saves only, 200 captures/500 MB, up to 100 memory-only OCR indexes, reviewed 7/30/90-day Trash cleanup. Temporary-folder choose/save/index/disconnect passed; bookmark removed, no user folder/history indexed. Retention deletion not live-tested. |
| 14 | Explicit screen recording / trim | Implemented Apple source picker, silent H.264, max 4K/30 fps, 30 min/2 GB, visible Stop, stop on lock/Presentation/close. User selected the authorized temporary Preview window; Stop/finalization produced a valid MP4 with 1 video and 0 audio tracks. Synthetic MP4/M4A export through the production path verifies selected trim duration. Full picker/range UI and external-codec matrix remain pending. |
| 15 | Audio/video/GIF conversions | Implemented new-file-only MP4≤1080p/M4A/GIF. Twelve synthetic production-path checks pass: GIF frame/size/length bounds, valid MP4/M4A tracks and trim ranges, no overwrite and byte-for-byte unchanged source. Additional real codec/input-format coverage remains pending. |
| 16 | Preferred output-device order | Implemented stable UID order, opt-in hot-plug events, disconnected-entry removal. Default off. No live audio route changed; hardware test pending. |
| 17 | Input selection / supported mic mute | Implemented public CoreAudio input choice, writable hardware mute only, event readback. Unsupported devices show disabled controls; no microphone capture or fake software mute. Hardware mutation test pending. |
| 18 | Accessory low-battery alerts | Implemented opt-in thresholds, per-device dedup/recovery, known readings only. No permission prompt forced or accessory drained; real alert test pending. |
| 19 | Timed Keep Awake | Implemented 15/30/60/120-minute public idle-system-sleep assertion. Installed start verified via `pmset`; Stop released the named assertion. No assertion left active. |
| 20 | Window positioning | Implemented Accessibility-gated halves/quarters/center/fill and Undo. IPC runs off main, bounded and cancellation/lock guarded; 32 geometry tests pass. Live move/restore test stopped before any move because Mac locked. |
| 21 | Saved window workspaces | Implemented encrypted app-ID/window-order/relative-bounds layouts (no saved titles/previews), review before restore, missing-display fallback, no launches/closures. Real save/restore pending; no test layout saved. |
| 22 | App/window switcher / optional previews | Implemented on-demand app/window list, explicit activate, optional one-shot Screen Recording-gated thumbnail. Installed list found approved test Preview window. No real switching/preview capture test completed. |
| 23 | Aggregate network throughput | Implemented visible-System-only physical en* interface rates; no packets/endpoints/history. Signed build passes; rate accuracy/multi-interface hardware test pending. |
| 24 | Memory pressure / disk activity | Implemented visible-only pressure observer and available IOKit disk byte rates. Unavailable counters stay unavailable; signed build passes; live System layout/accuracy check pending. |
| 25 | Named theme recipes / editor | Implemented native preview/editor, 20 saved records, safe tokens only. 124 recipe/theme policy checks pass; installed Spring Bloom editor preview/cancel visually passed, current System theme unchanged. Live saved-record lifecycle pending. |
| 26 | Bounded appearance/layout import/export | Implemented 16 KB strict allowlist JSON, preview-before-apply, exact accent/icon/layout and seasonal preference Undo, 400 KB local collection. Policy checks pass; real file import/apply/Undo/export round trip pending. Excludes private content/permissions/display IDs. |
| 27 | Private pinned scratchpad | Implemented separate native floating note panel, encrypted existing Notes storage, pin/close/flush, hide on lock/Presentation/off. Signed build passes; editing/pin live check pending. |
| 28 | Feature catalogue / lifecycle | Implemented native module switches/resource descriptions and private-window stop paths. Installed catalogue/control navigation checked. This is lifecycle coordination, not a claim to unload all Swift types or zero resource use when a tab is hidden. |
| 29 | Finder Quick Actions | Implemented native **Finder Services** for selected files: Add to Shelf, PNG conversion, Create PDF via existing backends. Not a Finder extension. macOS Services registration/selected-file invocation needs live testing; users may need to enable Services in Keyboard settings. |
| 30 | Public Shortcuts actions | Implemented App Intents for foreground Commands/Workspace Tools plus safe open-only deeplinks. Compiled `Metadata.appintents` present; actual Shortcuts invocation/deeplink routing still pending. No shell/recording/action execution via URLs. |

Also implemented: Spring Bloom, Summer Coast, Night Sky, Botanical, Desert Dusk
and Graphite using original static vector scenes, adaptive accents and optional
static scene details (default off). Existing photo themes/icons remain. These
are palette scenes, not new photorealistic artwork. The existing seasonal
schedule remains unchanged; new themes can be chosen manually. The broader
Hello/anniversary/focus-flourish/day-night/favorite/scheduled-theme ideas remain
roadmap items, not hidden implemented features.

## Verification and remaining work

- Local signed Release entry point passed branding, app/helper designated
  requirement, bundle/team and Sparkle trust-key gates. Installed path unchanged.
- Native tests passed: customization 247, productivity 90, Apple Notes script 8,
  Modes 284, workspace tools 40, appearance 124, wallpaper/utilities 1,379,
  account allowlist 89, window geometry 32, capture/QR 12 and synthetic media 12.
  Python helper suite and CI steps include the new feature policy suites.
  Per-release GitHub and local test results are reported separately.
- Initial feature-build PID 69168 had exactly one enabled media-key interceptor
  after cold launch, and the user reported HUD working. Before the 2.9.0 update,
  PID 96158 also passed Restart HUD and closing Settings with exactly one enabled
  interceptor. A real 2.9.0 Sparkle update/relaunch and physical-key check are
  separate final release steps and must not be inferred from these results.
- Preserved: HUD on, Dock icon hidden, System theme, seasonal switching off,
  clipboard recording off, Notes/Devices/OCR on, Tools/Wallpapers visible,
  System tab off, external presentation style and Home order/visibility.
  Temporary library bookmark cleared; timers/Keep Awake stopped. Accounts off.
- Only generated harmless PNGs and a user-selected Preview test window were
  used for new capture testing. Recording stopped/finalized. No actual audio
  route/microphone mute, other app positions, user notes/clipboard, calendar
  events, desktop wallpaper or notification permission was changed for tests.
- Window-layout live testing is not complete. The earlier test stopped when the
  Mac locked; no windows were moved or saved layouts created by that test.
- Tools windows intentionally use capture exclusion; white automated window
  screenshots are not visual QA evidence. Appearance Settings/editor screenshots
  were visually checked. Notched hardware, smallest-window/light/high-contrast
  matrix, macOS 14 compatibility, DisplayLink and resource profiling remain.
- Existing concurrency/deprecation and MediaRemoteAdapter deployment-target
  warnings remain. No Apple certification, notarization, complete production
  readiness or all-30-feature completion is claimed.

## Entry points

- App-local ⇧⌘K → Commands; native Tools menu / menu-bar extra.
- Workspace Tools → calculator, snippets, Quicklinks, clocks, countdown,
  truthful music queue capability and module catalogue.
- Capture Studio → markup, optional library, recording and media export.
- Windows & Workspaces → explicit app/window actions and saved layouts.
- Settings → Appearance → new themes and Saved Appearances.

No hidden recording, shell-evaluated expressions, executable themes or arbitrary
action URLs. Preserve identity, HUD trust, private storage, permissions and saved
preferences. Native glass belongs on controls/navigation, not every content tile.

## 2.9.2 compatibility follow-up

Build 295 raises the minimum to macOS 15 to match the linked media framework.
The old macOS 14 deployment warning above describes the historical feature build;
it is not the advertised requirement for this release. Candidate archive,
installer and future publisher checks now agree on the minimum. The complete
hardware/macOS/DisplayLink/accessibility matrix remains separate from this
metadata correction. See [the 2.9.2 report](releases/2.9.2.md).
