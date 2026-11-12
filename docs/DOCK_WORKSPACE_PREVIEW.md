# Dock Workspace local preview

2 November 2026. This is an independent native Notchscape implementation inspired by the public utility categories at https://glasswave.app/dock (currently https://zincwolf.app/dock). No competitor code, binary, artwork or interface assets were imported.

## What this increment does

For the separate workspace, enable **Settings → Dock → Use Dock Workspace**, then choose **Open Workspace**. The same workspace is reachable from the Notchscape menu, Tools menu or Commands. It starts off, and opening it while disabled takes you to its settings without enabling it. Nothing opens automatically at launch, unlock or wake.

A separate rounded native panel shows chosen apps/folders and five card types: Clock, This Week, Battery, System and Now Playing. Choose up to 24 pins explicitly using the macOS file picker. Drag pins/cards to reorder or use their Move Earlier/Move Later menu commands. Removing a pin keeps the original app/folder. The calendar card is a date strip, not an event-permission request. Now Playing shares Core's music provider; the System card shares Core's demand-counted sampler. No new camera/clipboard/location/screen-capture access is requested by Dock.

The native panel stays within the target screen's visible frame, above the existing system Dock. It doesn't change global Dock preferences, take over system keyboard shortcuts or claim replacement-Dock behavior. Materials and glass controls share the app's accent and system accessibility/performance preferences. Clock updates occur at minute boundaries; the System lease exists only while Dock is open and that card is enabled. Closing, lock, sleep, user switch and Presentation stop transient content/provider demand. User-selected layout persists; there is no automatic reopen.

Pins use bounded local bookmarks, resolved without UI/mounting. Replaced/missing/incompatible targets are refused. Corrupt/future layouts remain preserved and read-only. Picker callbacks are generation/identity fenced. Icon rendering never rewrites bookmarks or publishes during view evaluation.

## Session compatibility correction

Build 306's real live test found the supplemental CGSSessionScreenIsLocked key absent on the unlocked desktop; requiring that key made Open Dock falsely refuse. Build 307 uses one tested eligibility policy for Dock and optional Menu Bar items. It requires the public on-console/login-complete fields and exact current/effective/session UID match; optional lock true or malformed data denies access, and absent optional lock data permits the otherwise valid session. Lock-notification, sleep, active-session and Presentation fences remain. This is ordinary app surface eligibility, not credential authorization. Face/broker/unlock policy is untouched.

## Add-ons and remaining boundaries

The native Add-ons catalog has Features, Theme Packs and Installed categories, search, a Dock feature card and detail sheets describing actual availability, requirements and privacy. Included features open their settings; browsing does not enable anything. Desktop Widgets and Developer Tools remain unpublished. Face remains a local preview only with the existing device-bound development profile.

This Dock code is still included in the app. A real separate downloadable executable,47-widget parity, magnifying replacement Dock/folder stack/browser, downloadable/removable resource packs and actual WidgetKit extension are not delivered by this increment. No fake Download or Uninstall controls are shown. No public release/update-feed change is authorized in this pass.

## Validation

Signed-build, live UI, settings-preservation and HUD results are recorded separately in the parent work checkpoint ../notchscape-glasswave-next-2026-11-02/LOCAL_VERIFICATION_307.json after completion. Pure tests cover 33,611 layout/reorder/privacy/session/geometry assertions, including missing optional session flag. Isolated native Swift 6 complete concurrency typecheck passed; final combined-app checks remain independent. An actual hardware key and lock/sleep/alternate-user/displays require their own coverage; don't infer them from synthetic fixtures.


Installed build 308 passed eight alternating live scroll passes with all five
cards, panel close/reopen, and bookmark launch of only the harmless test folder.
Native Add-ons details and glass controls were inspected. A short three-sample
process check showed 0.0%, 0.2% and 1.7% CPU at about 90 MB, not a broad profile.
All 51 allowlisted settings were preserved after restoring only two Dock test
keys. Cold launch, Restart HUD, Settings close and final relaunch each retained
one enabled media-key tap. The human confirmed the actual volume HUD inside
Notchscape. No new release or public updater test was performed.

## Later Dock Bar increment

The separate horizontal bar, optional Weather/System faces, Stack navigation and reversible native-Dock hiding are documented in [Dock Bar local preview](DOCK_BAR.md). The earlier sections describe the original Workspace increment.
