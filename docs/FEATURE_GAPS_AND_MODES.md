# Feature gaps and whole-app Modes

Research snapshot: 21 October 2026. The 30 candidate gaps below are proposals,
not implemented features or a claim to cover every competing product. Compared
against the current source and official product documentation. Cost estimates
are engineering judgments; partial coverage is identified rather than counted
as an entirely absent feature.

Implementation has advanced since this research snapshot. See the current
[implementation and verification tracker](FEATURE_IMPLEMENTATION_TRACKER.md)
for what is installed, tested, blocked or still a roadmap item. The proposal
tables below must not be read as an all-features-complete claim.

## Implementation status

- Workspace Modes: temporary overrides are connected in source and the signed
  local build. 284 native policy checks pass; Presentation hiding and Gaming's
  low-impact/restore behavior passed local UI checks. See the exact implemented
  behavior in [Workspace Modes](WORKSPACE_MODES.md). The broader bundle table below
  remains a roadmap, not a claim that every suggested override is connected.
- Wallpaper browsing: Match Current Theme and Surprise Preview are added in
  source. They filter or preview only; desktop changes still require Apply.
  Theme-filter empty states, credits/Surprise Preview, Space images and overflow
  navigation passed installed-build UI checks. This is not a public binary release.
- Existing themes: System, Fall, Halloween, Christmas, neutral Winter, Easter,
  and grouped Star Wars Jedi/Dark Side/character palettes. Automatic seasons,
  hemisphere selection, optional holidays, custom accents, and icon matching
  already exist. No new AppTheme variants are implemented in this pass.
- The existing face's unmanaged blink timer has been replaced in source with a
  cancellable, motion-aware task. Targeted typechecking and the integrated signed
  build passed; exact live blink timing remains untested. No new animated Easter
  eggs are implemented.

Existing lyrics, reminders, basic countdowns, OCR, clipboard history, image
conversion/resizing, background removal, Create PDF, ZIP, and quick app/Shortcut
actions are deliberately excluded from the list of new features.

## 24 useful gaps

| Feature | Gap / user benefit | Cost |
| --- | --- | --- |
| Command palette | Search and run app actions, beyond searching Settings sections. | Medium |
| Calculator and conversions | Local arithmetic, units, dates; no code execution or shell eval. | Low–medium |
| Text snippets | Reusable text with explicit Copy; automatic expansion is a separate permission-sensitive feature. | Medium |
| Named Quicklinks | URL, folder, and search templates, not just app/Shortcut buttons. | Low–medium |
| Color formats and swatches | Extend the existing hex sampler with RGB/HSL/Swift formats and saved colors. | Low |
| Stopwatch and laps | Elapsed time rather than a countdown. | Low |
| Focus cycles | Work/break rounds and pause/resume beyond the current 25-minute timer. | Medium |
| Pinned event countdown | Choose an event and see its time remaining rather than only next-event alerts. | Medium |
| Music Up Next | Real player-provided queue; unavailable when the player cannot supply one. | Medium–high |
| Watched download folders | User-selected folders instead of only Downloads; scoped bookmarks and bounded events. | Medium |
| QR/barcode recognition | Add local Vision barcode recognition to the existing text capture workflow. | Low–medium |
| Screenshot markup | Arrows, crop, text and destructive redaction, not only OCR. | Medium–high |
| Searchable capture library | Opt-in folders and local OCR with retention/storage controls. | Medium–high |
| Screen recording | Explicit capture selection, trim and export, with bounded resource use. | High |
| Audio/video/GIF conversion | Extend Shelf beyond the already-supported image conversions. | High |
| Preferred audio-device order | Event-driven automatic device choice beyond manual output selection. | Medium |
| Microphone mute and input choice | Capability-aware input controls, not just observing microphone use or muting output. | Medium |
| Accessory low-battery alerts | Deduplicated thresholds beyond existing battery readings and connection alerts. | Low–medium |
| Timed Keep Awake | Public power assertion, visible expiry and release on quit. | Low–medium |
| Window positioning | Keyboard/action-driven move and resize; requires Accessibility. | Medium–high |
| Saved window workspaces | Restore an arrangement across displays without closing apps or discarding work. | High |
| App/window switcher | Optional previews; no hidden/locked background capture. | High |
| Network throughput | Aggregate speed/history; no packet or content collection. | Medium |
| Memory pressure and disk activity | More useful than only memory-used and storage-capacity percentages. | Medium |

Official examples: [Vorssaint](https://vorssaint.com/),
[Atoll](https://github.com/Ebullioscopic/Atoll),
[DynamicLake DynaDrop](https://www.dynamiclake.com/dynadrop), and Raycast's
[search](https://manual.raycast.com/search-bar),
[calculator](https://manual.raycast.com/calculator),
[snippets](https://manual.raycast.com/snippets),
[Quicklinks](https://manual.raycast.com/quicklinks),
[screenshots](https://manual.raycast.com/screenshots), and
[window management](https://manual.raycast.com/window-management).

## Six additional candidate gaps

These extend the original shortlist to 30; they are not authorization to build
all six or to add more top-level pages.

| Feature | Current coverage / useful extension | Cost and limits | Official example |
| --- | --- | --- | --- |
| Saved theme editor | Custom accent exists, but not named, reusable palettes with a full preview. | Medium. Use supported appearance tokens and contrast checks, not executable themes or arbitrary CSS. | [Raycast Theme Studio](https://manual.raycast.com/themes), a Pro feature. |
| Portable appearance/layout presets | Account sync is disabled; there is no local appearance/layout import-export workflow. | Medium. Versioned, bounded JSON allowlist; preview changes and preserve an Undo snapshot. Exclude credentials, clipboard, notes, permissions, location, and machine-specific display identities. | [Raycast Import & Export](https://manual.raycast.com/import-export). |
| Pinned floating scratchpad | Quick Notes exists in Tools, not as a separately pinned note. | Medium. Reuse encrypted note storage; explicit pin/close, accessible window controls, and immediate hiding when locked or presenting. | [Vorssaint Scratchpad](https://vorssaint.com/). |
| Feature catalogue and lifecycle | Many toggles and some stop paths exist; no unified module catalogue/unload lifecycle. | Medium-high. Audit observers, timers, resources, and dependencies first. Do not claim zero resource use merely because a tab is hidden. | [Vorssaint modular features](https://vorssaint.com/). |
| Finder Quick Actions | Existing conversion/PDF/ZIP tools require entering Shelf. | Medium. Reuse those backends from a user-initiated Finder entry point; operate only on selected files and create new output. This is an access improvement, not a new converter. | [DynamicLake DynaDrop](https://www.dynamiclake.com/dynadrop). |
| Public action automation | The app can run Apple Shortcuts, but does not expose its own action catalogue through App Intents or safe action deeplinks. | Medium. Reuse a shared action registry for Start/End Mode and Open Home. Do not accept arbitrary shell commands or enable privacy-sensitive features remotely. | [Raycast action deeplinks](https://manual.raycast.com/search-bar); implementation foundation: [Apple App Shortcuts](https://developer.apple.com/documentation/appintents/app-shortcuts). |

## One switch, several effective settings

Existing Activity Profiles only filter closed-notch activities. A whole-app
Modes system should extend that foundation, not create conflicting profile
systems. Workspace Modes integration is underway; verify each override before
describing a preset as complete. Study should not start a timer without an
explicit action, and Modes must not change macOS Focus or other apps silently.

| Mode | Suggested effective settings |
| --- | --- |
| Work | Focus activity filter, calendar/actions prominent, quiet sports/weather alerts, music override off. |
| Study | Work layout, optional music, focus timer preview, fewer interruptions. |
| Presentation | Pause clipboard recording, close private Tools, hide sensitive tiles/activities, music override off; capture exclusion is not a security boundary. |
| Gaming | Low-impact rendering, no hover opening, quiet nonessential activities; never alter HUD permission grants. |
| Travel | Low impact, external-display presentation off, battery prominent, wallpaper rotation paused; preserve location consent. |
| Creative | Music-first priority, color/capture tools easy to reach, quiet AI completion. |
| Developer | AI-first priority, System available, coding actions, no automatic transcript collection. |
| Minimal | Fewer tabs, restrained effects, minimal activities, click/shortcut opening. |

Design requirements:

- One active Mode, visible active-state pill, preview of changes, easy End/Restore.
- Optional durations: until ended, 30 minutes, one hour, or until app quits.
  Presentation must require an explicit end rather than automatically revealing
  private content while a screen share might still be running.
- Apply an effective-settings overlay; do not permanently rewrite many Defaults.
- Preserve manual changes made during a Mode; do not restore stale snapshots.
- Lock-screen privacy, explicit feature-off switches and permissions always win.
- Never silently enable recording, location/camera/mic capture, accounts or syncing.
- Pause clipboard through an independent mode-pause reason, preserving a user's
  own pause. Guard every private-window entry point, not only initial activation.
- Reconcile expiry on wake and clock changes. Keep the displayed end and actual
  duration consistent; cancel the old expiry task when another Mode replaces it.
- If a Mode hides the current tab, fall back to Home. Restore behavior from the
  latest real preferences instead of restoring an old selected-tab snapshot.
- Add app/power/display automation only later, with visible priority and reason.

## Theme roadmap: cohesive content, consistent controls

The existing schedule maps spring and summer to System. The first two proposals
fill that real seasonal gap; the others are optional aesthetic choices, not new
utility features. None of these AppTheme variants is implemented yet.

| Proposed theme | Direction | Priority |
| --- | --- | --- |
| Spring Bloom | Neutral blossoms and greenery; separate from Easter for people who do not celebrate it. | First |
| Summer Coast | Quiet coastal landscape with restrained blue accents. | First |
| Night Sky | Original still star field and deep navy; no continuously moving particles. | Later |
| Botanical | Calm foliage, useful all year rather than tied to a holiday. | Later |
| Desert Dusk | Original landscape, independent of licensed franchise imagery. | Later |
| Graphite | Restrained, nondecorative option; semantic success/warning/error colors remain distinct. | Later |

Every theme should use one shared recipe: seamless Home panorama, restrained
accent tokens, optional matching icon, and suggested wallpaper collection. Keep
the layout and action positions consistent. Reserve quiet space behind text and
keep the tree/pumpkin/scene subject prominent without a separate pasted-on image.
Do not promise licensed artwork, copy competitor assets, or substitute online
character photos. The unavailable Vader scene remains unavailable; no further
generation retry is part of this roadmap.

Apple separates the glass control/navigation layer from the content layer.
Keep photographs and information tiles on the latter; standard components adopt
native material behavior. Do not turn each theme into a different glass system.
See [Materials](https://developer.apple.com/design/human-interface-guidelines/materials)
and [Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/liquid-glass).

Useful controls to design next, not yet implemented:

- Preview the same theme on Home and representative Settings controls before
  applying it. Include light/dark and increased-contrast checks.
- Favorite themes, return to System, and an optional Use Until Tomorrow override
  that does not permanently disable an existing seasonal schedule.
- Show the next scheduled change with a plain-language date. Keep holiday
  participation optional and preserve independent custom accents/icons.
- Later, add paired day/night artwork using the clock, without requesting
  location. Follow macOS's native light/dark interface preference rather than
  creating a competing appearance switch: [Apple Dark Mode](https://developer.apple.com/design/human-interface-guidelines/dark-mode).
- Later, offer theme-linked wallpaper rotation as a separate explicit opt-in.
  Match Current Theme already filters the browser; it must not silently acquire
  the different meaning of changing the desktop automatically.

Scheduling should use local Calendar boundaries with DST/time-zone tests. The
existing manager observes wake and clock changes; explicitly handle time-zone
changes before adding custom schedules. Manual theme choices, temporary rules,
seasonal rules, and custom accent/icon choices need one visible priority policy.

## Optional Easter eggs and delight

The following are design proposals, not an Apple requirement or implemented
features. The exception is Surprise Preview, which is now present in wallpaper
browsing source and leaves the desktop unchanged.

| Idea | Safe, coherent behavior | Status |
| --- | --- | --- |
| About: Hello | A logo interaction reveals a brief original greeting; also expose an accessible Extras action so discovery does not require a mouse gesture. | Proposed |
| Seasonal details | Explicitly preview a warm-tree-light variant or friendly pumpkin detail in the same full scene; return to the normal scene immediately. | Proposed; requires original assets |
| Surprise landscape | Preview a curated landscape with source information; keep Apply explicit and Undo available after an application. | Added in source; live verification separate |
| App anniversary | Optional local install-anniversary artwork; no birthday, account, or telemetry collection. | Proposed |
| Focus-session flourish | One brief symbol transition after a genuinely completed focus session; never reuse the AI completion badge for a timer. | Proposed |

Use one discoverable Playful Details preference and Preview action. Keep extras
optional, dismissible, keyboard/VoiceOver reachable, silent by default, and
inactive when locked or presenting. Avoid always-on snow/fire/particles,
flashing, surprise desktop changes, or hidden changes to real settings. No
important feature should require discovering an Easter egg.

[Apple Motion](https://developer.apple.com/design/human-interface-guidelines/motion)
recommends purposeful motion that does not overshadow work and lets people opt
out or cancel. Use a static alternative under Reduce Motion/low-impact mode,
with no sleeping animation loop when disabled. Pause work when views disappear;
do not recreate the previous unmanaged face timer.

## Accessibility and performance acceptance criteria

- Preserve native compact controls, standard icons, stable action placement, and
  semantic labels across all themes and modes. Decorative artwork should not
  intercept input or become meaningless VoiceOver content.
- Check Reduce Motion, Reduce Transparency, Increase Contrast, keyboard access,
  and VoiceOver. AppPerformanceManager currently observes the first two; custom
  theme colors and effects still need the remaining audit.
- Do not rely on accent color alone for selection or success/error state. Keep
  checkmarks, distinct glyphs, labels, and sufficient text/background contrast.
- Guard custom symbol effects directly against reduced-motion policy; do not
  assume a parent transaction suppresses every animation mechanism.
- Use one cancellable animation task, no idle particle renderer or hidden
  capture loop, bounded image decoding/cache, and visible-only monitoring.
- Verify at actual size on notched and notchless displays and at the smallest
  supported Settings/wallpaper window size. A clean compile is not visual QA.

Primary guidance: [Apple accessibility testing](https://developer.apple.com/documentation/accessibility/testing-system-accessibility-features-in-your-app),
[Differentiate Without Color](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/differentiate-without-color-alone-evaluation-criteria/),
and [rendering efficiency](https://developer.apple.com/documentation/xcode/improving-your-app-s-rendering-efficiency).
These are acceptance criteria, not a claim of Apple certification or a completed
whole-app accessibility audit.

## Recommended order and limits

1. Modes and a shared action registry.
2. Command palette, calculator and Quicklinks using that registry.
3. Stopwatch, richer focus sessions and chosen-event countdowns.
4. Preferred audio, microphone controls and accessory battery alerts.
5. QR recognition, followed by capture markup/library.

Defer per-app volume mixing, universal external-monitor brightness, continuous
window-region watching, arbitrary plugin code and system notification mirroring.
These need separate permission, privacy, compatibility and performance designs.
Do not claim universal public APIs for third-party iPhone Live Activities or fans.

Relevant Apple APIs: [power assertions](https://developer.apple.com/documentation/iokit/1557134-iopmassertioncreatewithname),
[Vision barcodes](https://developer.apple.com/documentation/vision/vndetectbarcodesrequest),
[ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit), and
[Core Audio taps](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps).
Audio capture/taps are building blocks, not a finished per-app mixer.

All additions should share the same native grouped Settings, compact controls,
SF Symbols, accessibility behavior and glass-on-navigation/control treatment.
