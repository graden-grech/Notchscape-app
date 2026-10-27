# Optional local tools

Settings → Tools controls the new modules. All capture/recording features and the
Tools notch tab are off by default. A menu-bar **Open Tools…** command is always
available. The notch offers compact previews/actions; the separate native Tools
window handles keyboard editing and search, because the notch panels deliberately
do not take keyboard focus. The existing Home layout and sizing are unchanged.

## Privacy and storage

- Clipboard and notes use AES-GCM encrypted storage in Application Support under
  `theboringteam.boringnotch/PrivateTools`. A separate, device-only Keychain key is
  used. Account credentials and account sync are not accessed or changed.
- Missing keys, corrupt snapshots, or Keychain errors fail closed; the app does
  not replace unreadable history with a fresh empty snapshot.
- Clipboard recording checks `changeCount` once per second only after opt-in.
  Opening/enabling/unlocking skips pre-existing clipboard contents. Recording
  pauses while locked; a manual Pause survives lock/unlock.
- Concealed, transient and auto-generated clipboard types, known password-manager
  apps and user-entered excluded bundle IDs are skipped. This is best effort:
  unmarked sensitive copies from other apps can still be recorded.
- History is limited to 150 items and 12 MB including pins, 2 MB per item,
  500 KB text per copy, and 1/7/30-day retention for unpinned entries. Pins bypass
  age limits, not storage caps. TIFF copies are converted off-main to a bounded
  1200-pixel PNG. Copying an entry does not synthesize a paste into another app.
- Notes are bounded to 100 notes / 50,000 characters each. Saves are debounced;
  normal Quit flushes pending changes and reports errors instead of dropping them.
- Turning a module off does not delete its saved contents. Destructive UI actions
  require confirmation. No Notchscape account is required. Content stays local
  unless explicitly sent/synced to Apple Notes using the options below.
- The Tools window is excluded from screen sharing and closed on lock. The
  existing locked notch still uses only its isolated lock-symbol hierarchy.

## Apple Notes (optional)

The Notes editor offers **Save to Apple Notes** / **Sync Note** for one note.
Settings → Tools → Apple Notes offers Connect and an off-by-default automatic
two-way sync switch. Connect creates or reuses one non-shared `Boring Notch`
folder in Notes' default account, then pins the account and folder by stable ID.
Other folders are not read. If that account is iCloud, Apple's Notes service
handles cross-device sync; Notchscape does not implement iCloud networking.

macOS Automation consent is requested only by an explicit user action.
Background work never prompts or launches Notes. When enabled and unlocked,
automatic sync runs every minute while Notes is running, plus a two-second
debounce after local edits. Scripts run serially on a utility queue with bounded
Apple-event timeouts, not the UI thread. Disabling Notes/sync or locking the Mac
invalidates pending results; an already-sent event can finish in Notes.

This is text-only sync, not a full Notes editor. Attachments, locked/shared notes,
rich text/checklists/tables/links, notes above 50,000 characters, and folders above
200 notes are skipped rather than stripped or truncated. The app's 100-note cap
still applies. Each linked note keeps its last-common text inside the encrypted
local vault. A three-way comparison pulls remote-only edits, pushes local-only
edits after rechecking the remote HTML, and keeps a full local conflict copy for
review if both sides changed. Conflict copies are not automatically re-uploaded.
Apple Notes has no transactional compare-and-swap API; the final comparison
reduces but cannot eliminate a concurrent-edit race at the exact write instant.

Deletions never propagate: deleting a local note leaves its Notes copy intact and
stores an encrypted ignore ID so it is not immediately imported again. A moved
or deleted remote note leaves its local copy intact and is reported, not silently
recreated. Disconnect stops sync and removes links, preserving notes in both
apps; reconnecting is an explicit action. Script failures never log note bodies,
shell commands are not used, and all text is escaped before script compilation.

`tests/AppleNotesScriptTests.swift` compiles all production scripts without sending
events to Notes, and locally evaluates literal-only parser round trips to test
injection safety. Policy tests cover old note decoding, text bounds, formatting
protection, and every three-way resolution. Live permission, export/import, edits
in both directions and conflict behavior must be tested separately with a harmless
note; compiler success alone does not establish working sync.

## Devices

IOBluetooth lists paired devices and connects only after a Connect action.
Core Audio lists real output-capable devices and changes the default output only
after selection. The device sampler runs on a utility queue, only while the
Devices view is visible, with a 30-second refresh and a manual refresh button.

Connection/disconnection alerts are a separate opt-in using native macOS
notifications. Notification permission is requested only when that setting is
enabled. Event-driven Bluetooth subscriptions stop when alerts/devices are off
or the Mac locks; no background scan or permanent polling is added. Previously
delivered notifications remain subject to the user's macOS preview settings.

Battery percentages come from published IORegistry properties and the built-in
System Information Bluetooth report, matched by exact Bluetooth address. The
report runs once on opening Devices when its five-minute cache expires, or on
manual refresh (at most once per 30 seconds), off-main with a six-second timeout.
It is never part of the periodic sampler. Only addresses and validated battery
numbers are retained in memory, not serial numbers or the raw report.
macOS/hardware do **not** always publish AirPods per-earbud or
case values through this path. Missing readings are explicitly unavailable, never
guessed; universal AirPods battery support is not claimed. No private Bluetooth
selectors, discovery scans, Bluetooth cache scraping or system-setting resets.

## AI dashboard

Live lists every retained current activity, its state/detail and elapsed time,
plus existing optional outcome history. Open Codex launches Codex; Open Terminal
opens the Terminal app, not a guaranteed exact Claude session.

Available usage is separately opt-in. While Live is visible, it checks up to the
8 newest Codex `.jsonl` session tails (256 KiB each) from the past 7 days. Only
explicit `token_count` usage/rate-limit fields are retained in memory. There is
no credential/OAuth access, API request or transcript display. The code supports
optional formats rather than claiming a stable public Codex log API. Source
timestamp and 'Last reported' distinguish stale data from a live guarantee.

Hooks can supply `usage.remaining_percent`, `usage.resets_at` (Unix seconds), and
`usage.total_tokens`. Claude quota is unavailable unless its hook supplies those
fields. `UsageUpdate` updates metrics only, never task state. Existing advisory
versus actual quota-failure rules remain. Usage readings do not fabricate cost,
reset times, completion or interruption. The bridge is loopback-only with bounded
request size and connection lifetime.

## Text capture

Apple Vision handles image selection and region captures entirely on device.
Choosing an image requires no Screen Recording access. A region capture requests
that permission only after a user action, then uses macOS's interactive region
picker. Escape cancels; no background capture, continuous stream, automatic copy
or upload. The temporary region image is removed after recognition, and results
clear on lock. Recognition/file size is bounded; image quality affects accuracy.
The capture shortcut has no default assignment, to avoid taking another app's
shortcut. Disabled modules do not keep their global shortcuts registered.

## Appearance and validation

Home supports right-click → Edit Home, with in-place tile dragging and a Done
control. The menu stays open while editing. Appearance → Home layout also offers
drag handles, native visibility switches, and accessible earlier/later buttons.
Reordering preserves the single shared seasonal scene rather than moving or
duplicating its backdrop. The five navigation tabs have stable identities and a
single draggable native-glass selection bubble; tap/VoiceOver selection remains
available. Reduce Motion/Transparency and low-impact fallbacks remain supported.

Settings and Tools use native unified title bars and standard macOS window
rounding, not custom traffic-light positions or rectangular window masks. The
Settings sidebar uses compact system-symbol badges. The Performance page uses
small labeled values/progress bars and a shared native glass control container.
No always-running graph or animation timer was introduced.

Weather adds the macOS location-purpose key and signed location capability. A
first grant requires an explicit Use My Location action; on macOS the one-shot
location service presents consent. Background appearances do not prompt. Requests
are deduplicated/cancellable, stale completions cannot replace a newer selection,
successful forecasts cache for 15 minutes, and active tiles refresh on that cadence.
Only location coordinates rounded to two decimal places are sent to Open-Meteo;
they are not persisted. Manual city selection remains available. Sky-colored cards
are content surfaces; glass is used for controls. The settings include provider
attribution. Open-Meteo's public endpoint is for non-commercial use; monetizing
distribution requires a suitable provider licence/endpoint before release.

Easter has a generated photographic-style scene and matching transparent icon;
asset locations and exact built-in-generation prompts are in `easter-assets.json`.
Automatic Western/Gregorian Easter is separately opt-in and uses the real annual
date, from Palm Sunday through Easter Monday. Existing neutral winter/seasonal
choices and manual accent/icon overrides remain. Empty media metadata is blank;
the UI says Not Playing instead of inventing a song/artist.

New Settings use the existing grouped forms, system fonts, SF Symbols, native
small switches, theme/custom accent, and OS-native controls. Glass stays on the
navigation/control plane, not over full content tiles. The optional fifth tab
shares one 140-point selector so the header remains within its existing
budget; the HUD, battery header, Home width and animations are preserved.

Standalone regression: compile `ProductivityModels.swift` with
`tests/ProductivityPolicyTests.swift`. `tests/TextRecognitionSmoke.swift` generates
and recognizes a harmless fixture without reading the screen. Signed-build,
live UI, persistence, physical Bluetooth hardware, true screen-capture permission,
lock transitions, accessibility and HUD/update checks must be reported separately.

AI activity labels prefer explicit chat-title metadata, then a matching local
Codex session-index/state-database title or Claude dedicated title record. A
working folder is only a fallback; root/empty folders display “Codex chat” or
“Claude Code chat”, never `/`. Lookups match the exact session ID, run off the UI
actor, use bounded reads and a short cache, and never modify provider data. These
optional metadata formats are best-effort, not a guaranteed provider API. Names
stay local (and enter local outcome history only when that feature is enabled).
Missing titles are not invented from prompt/tool content. The compact island
keeps its provider icon; clicking it reveals the chat title. Standalone regression:
compile `AgentChatTitle.swift` with `tests/AgentChatTitleTests.swift`.
