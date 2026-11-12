# Core and downloadable add-ons: architecture proposal

2 November 2026. Proposal only; this document does not implement a Store, downloadable code, or distribution signing. It builds on the verified inventories in [the Glasswave/reels audit](GLASSWAVE_REELS_AUDIT_2026-11-02.md). Feature toggles in the current binary are not downloadable add-ons. A downloadable theme can be genuine optional content even when its renderer is included in Core; that does not mean its renderer was removed from the binary.

## Product boundary

Use one native Store called **Add-ons**, one settings hierarchy, and a common accent/type/material system. Clearly label Included, Download, Installed, Enabled, Update Available, Requires Access, Unsupported and Not Available for Distribution. Do not show a working Download button for catalog-only placeholders. The Store should disclose download size, installed size, compatibility, data retained on removal and permission needs before activation. Acquisition should not activate camera, clipboard history, location, account sync or background agents.

| Capability / exact competitor scope | Core or optional recommendation | Dependency and truthful removal boundary |
| --- | --- | --- |
| Basic Notch/Dynamic Island, music, calendar, shelf, HUDs; lifecycle, updater, account-free use, local preferences, Modes and privacy/lock policy | Core | Always included. The basic Notch is not removable as Island Extras. Keep the trusted signing/update identity and user's base settings. Accounts remain disabled unless separately ready and requested. |
| Add-ons catalog, verified downloader, installation journal, integrity verification, safe native controls and diagnostics | Core | The minimal product. A catalog card alone is not a module. No arbitrary command strings, remote JavaScript or executable theme content. |
| Island Extras: notes, timers, AI status, sports and advanced dashboard pages | Optional Island Extras; the basic Notch/Island stays in Core | Current monolithic source already implements much of this. A real optional-code version needs a separately packaged signed component; hiding its tab does not remove its binary bytes. Core music/calendar/shelf/HUDs remain usable without the Extras. |
| Replacement Dock: launcher/magnification, folder/Trash cards, 47 utility-widget surfaces, pages/stacks | Dock add-on, first priority | Separate signed native component. User-initiated, explicit fallback/quit restoration. Never silently replace macOS Dock settings or hijack unrelated apps. Existing hidden Dock-icon preference is not this feature. |
| Desktop/Notification Center widgets: exact 56 types in audit | Widgets add-on, first priority | Must be actual WidgetKit extension(s), normally inside a separately signed host app with compatible shared snapshots. A Core toggle cannot install/remove an embedded signed extension independently. Native gallery registration, supported update timelines and signing require separate validation. |
| Half/corner/fill/center plus 42-action precision/grid/drag/layout system | Windows add-on | The explicit geometry/Undo increment can be developed in the existing binary first, but it must be labeled Included until code is separately packaged. AX consent only when requested. Global edge-drag hooks and monitor auto-restore are separate off-by-default switches. |
| Encrypted history, boards/search/transforms/preview/stack and explicit paste | Clipboard add-on | Own collection service and UI; share only narrowly requested data with Island/Core. Off remains off after download. Removing code must stop polling and close previews; encrypted history is retained unless the user separately chooses Delete Data. |
| CPU/RAM/disk/network/battery; 33 optional menu items | System & Menu Bar add-on | Share one ref-counted sampler per source. Each menu item independently off by default; no sampling solely because a catalog preview is visible. Disable removes status items and cancels sampling. |
| Git/GitHub checks/reviews/contributions, dev servers, containers, simulator state, endpoints and user commands | Developer add-on(s) | Split read-only local sources from authenticated/network/user-script execution. No credentials in catalog manifests. CLI paths and process arguments validated; no shell interpolation. Explicit endpoint hosts and bounded opt-in probes. |
| Face convenience unlock, camera selection, enrollment, broker and private data | Face add-on; distribution unavailable until properly signed | Current seven-day Personal Team broker is local testing only. Store must not advertise a public working install. Downloading must not enroll a face, store a password or grant camera/Accessibility. Not Apple Face ID; no FileVault first-login bypass. |
| Halloween/Christmas/Easter/fall/winter and future seasonal scenes, icon variants and details | Optional Holiday/Seasonal resource packs | Real downloadable image/icon/metadata files; Core includes the bounded native renderer. Uninstall removes pack assets/caches and falls back gracefully. No code, scripts, forced holidays or automatic date rules unless explicitly enabled. |
| Civic/White House imagery and matching accents | Optional Civic resource pack | Same safe resource contract; neutrally described, no endorsement claim. White House/Capitol/Supreme Court scenes currently exist; additional original Treasury/Pentagon/Executive Office art is prepared outside Core at AddOnPacks/CivicCollection. Pack downloads remain unpublished. Separate from default branding/onboarding. Removing the pack falls back without changing user preference history. |
| Other themed/franchise-inspired art | Optional licensed/original resource packs | Rights/source review independent of technical packaging. Do not copy competitor artwork or imply a franchise license. Existing blocked image request is not retried by a downloader. |
| Wallpaper catalog, local favorites/rotation and platform archives | Wallpapers add-on plus separately downloadable image packs | Provider adapter can be packaged; image bytes genuinely optional already. Removing downloaded content must not delete original user images or change their current desktop automatically. Retain catalog references/favorites independently. |
| Capture/OCR/markup/silent recording/media conversion | Capture add-on | Large model/library/cache bytes can be optional. Permission only at the user's action, no capture on install/enable. Disable stops capture, invalidates callbacks and clears private transient search/image buffers. User-selected exports remain user files. |
| Tools: calculator/converter, notes, clocks/countdowns, color, snippets, links, QR creation, dictionary, counter, breathing/progress | Small Tools add-on or Included subset | Keep shared primitive renderers in Core only if useful; name the bundled subset honestly. Optional download must remove actual payload bytes. Photos/Contacts-based tools request their own access, not one global “all permissions” prompt. |
| Screen Time database-derived six widgets; fan control, private Dock integration | Unsupported/later investigation | Do not scrape macOS private Screen Time databases or promise portable writable fan control. A transparent opt-in own-session focus/break tracker is a different capability. Public APIs and release requirements must be verified individually. |

## Two supported package kinds

**Resource pack:** signed manifest plus bounded images/icons/JSON and optional known safe fonts. This is the easiest genuine download/removal path now. Theme renderer code remains installed and must be labeled accordingly. Validate file type by decoding, maximum file count/size/pixel dimensions, normalized relative paths, no symlinks/traversal, no external references. Avoid executing remote HTML, JavaScript, shell files or dynamic libraries from a resource pack.

**Executable feature component:** separate signed app/XPC service with a stable versioned protocol and minimum Core/OS version, using normal macOS security boundaries. A component can own a module window/panel; Core may render a bounded data snapshot when appropriate. Do not load an unsigned Swift bundle into the permission-approved Core process. This boundary needs a deliberate build/sign/release path before the Store can promise removal of feature code. Downloadable executable code is a different product/distribution concern from a resource pack or App Store in-app purchase; do not conflate them.

The current development signing/broker limits mean resource packs can be designed sooner than generally distributable executable add-ons. Do not weaken the identity gate or publish a seven-day profile to make a card appear installable. Existing HUD trust and Sparkle archive identity remain independent acceptance gates.

## Package metadata and trust

- Stable module ID, package kind, version, minimum Core/OS, CPU architectures, dependencies, declared capabilities, compressed/expanded bytes, file hashes, package URL and signing identity/manifest signature.
- Download only from explicitly trusted HTTPS origins; validate every redirect. Verify a signed release manifest, content hash, expected code signature/Team/bundle identity where code is present, and compatibility before activation. A checksum alone is not publisher authentication. Keep update keys independent of feature data.
- Atomic staging → verification → installed-version promotion with a transaction journal and last known working version. Failed installs leave the previous version intact and delete only the transaction's temporary files.
- Dependency resolver and native permission explainer, not a remote instruction interpreter. Granting one module access does not authorize unrelated collection or broaden Core permissions. No secrets, credentials, prompts, clipboard text, faces or precise location in package requests or diagnostics.
- Shared-data APIs must check both endpoint identity and active capability. Use read-only bounded snapshots where possible. Do not let any installed component enumerate all notes/history/face data merely because its signature is trusted.

## Lifecycle and privacy contract

Every module follows Downloaded → Installed → Disabled → Enabled → Active/Suspended. Download and install never imply enabled. Active acquisition requires a visible consumer or explicitly enabled background function. Lock, screen sleep, Presentation and user switch produce the same privacy outcome across Island, Dock, widgets, menu panels and child processes.

Disable must cancel tasks/timers/observers, unregister owned hotkeys/event hooks, stop camera/microphone/capture, release Keep Awake/power assertions and security-scoped bookmarks, remove status items, close private windows and invalidate pending results with generation tokens. Resume must recheck capability and privacy before publishing. No work should continue behind a missing tab solely because a singleton once started.

Native widgets are a separate process: write a redacted locked/Presentation snapshot, invalidate/reload appropriately, and never assume an in-process SwiftUI privacy overlay hides an existing WidgetKit snapshot. Live widget refresh follows [Apple's WidgetKit lifecycle](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date), not a permanent two-second loop.

Only one shared sampler/session per source. Ref-count visible consumers; stop when the last releases. Never double the camera, clipboard poller or network sampler because Island and Dock are both installed. New modules must pass synthetic lifecycle tests before permission-based live testing is considered.

## Disable, remove download and delete data are different

| Action | What happens | What remains |
| --- | --- | --- |
| Disable | End owned work and UI; preserve installed payload | Settings, payload and saved data; macOS privacy grants are not reset |
| Remove Download | Disable first, wait for stop/close acknowledgement, then remove only the verified owned package/cache paths | User-created files, encrypted history, notes, favorites and base settings unless separately chosen |
| Delete Module Data | Separate specific destructive action with explicit confirmation | Other modules, unrelated files/preferences and Core updater/HUD identity |

For Face, explain the difference between removing its executable and deleting encrypted credentials/face enrollment. Do not retain a still-running credential broker after removal. For themes, removing the active pack uses a built-in fallback. For wallpaper, keep the desktop already applied and offer an explicit alternative; removing a thumbnail cache must not undo the user's desktop.

The Store should report both removed bytes and retained-data bytes. A switch that hides a feature but removes zero package bytes must say Disable, never Uninstall. A feature compiled into Core should say Included with App, even if optional at runtime.

## Suggested delivery sequence and proof

1. Resource-pack format and a small original Holiday pack: verify download, offline install/reopen, corrupt hash rejection, cancelled download cleanup, fallback after removal and actual before/after bytes. Do not turn the theme on automatically.
2. Core/module protocol, then Dock and Island Extras as native signed optional components. Keep the basic Notch/Island with music/calendar/shelf/HUDs in Core. Define who owns panels, shared providers and lock/Presentation behavior before splitting files into artifacts.
3. Widgets host/extension with snapshots and compatibility/distribution validation; start with a few useful widget types, and track the other 56 by actual behavior, not just matching names.
4. Clipboard, precision Windows and optional System/MenuBar modules; retain current user data and trusted Core identity through the migration. Face stays distribution-blocked until a valid distribution solution exists.
5. Release checks separately prove source/build, signed packages, public catalog availability, download/install/disable/remove, old-version migration, updater and real HUD behavior. A prepared Store is not a published functioning marketplace.

Useful official references: [Apple Liquid Glass](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views), [WidgetKit](https://developer.apple.com/documentation/widgetkit), [XPC](https://developer.apple.com/documentation/xpc), [Hardened Runtime](https://developer.apple.com/documentation/security/hardened-runtime), [notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution), and [app extensions](https://developer.apple.com/app-extensions/). These are architecture references, not a claim that the current project has all corresponding entitlements or distribution credentials.
