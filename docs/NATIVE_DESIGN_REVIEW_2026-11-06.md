# Native Mac design pass — local verification

The user approved the recommended Native Mac direction on November 5, then requested calendar refinements, Home tile transparency and an Original option on November 6. The installed local preview is Notchscape 2.9.5/build320. Nothing in this pass was pushed, released or added to the updater feed.

## Implemented

- Appearance is a native overview with focused Themes & Colors, Home Layout, App Icon and Effects & Mirror pages. Player styling is grouped under Media. Existing routes remain searchable, with parent context and working back navigation. The settings tour covers the focused pages without adding more chapters.
- Home uses quiet standard-material content surfaces. Glass remains on controls/navigation. The idle music tile has a compact neutral Not Playing state; configured controls remain available and a zero-duration seek bar is hidden.
- Calendar has seven complete date columns, consistent small day numbers, secondary weekday/year typography, one selected-date circle and a Today outline when another date is selected. Existing date navigation, events and layout dimensions remain.
- Appearance → Home Layout offers Original/Refined tile styles and a native 0–100% transparency slider. Only Music, Calendar and Quick Actions backgrounds fade. Text/buttons do not fade; Weather retains its sky. Original removes the new backgrounds while preserving layout and date-clipping fixes. Reduce Transparency and Increase Contrast keep refined surfaces opaque. Invalid saved slider values are bounded safely.
- Live AI summaries use readable activity descriptions while preserving original detail for diagnostics. Dock Workspace, Shelf and tour cards use consistent content styling and spacing. Disabled native switches are visibly desaturated/dimmed.
- The visualizer editor uses native-size controls, rejects invalid URLs before saving and removes selections without forced indexing. Seasonal icon previews use consistent rounded masks.

## Verified

- Signed Release wrapper completed with identity, nested-helper, current local provisioning, branding, Sparkle key and accounts-disabled gates passing. The 271 source/config inputs matched the frozen snapshot throughout the final build. Installed binary matches the verified candidate; deep strict code-signature verification passed.
- 109 workflow/release-helper tests, 1,504 utilities/settings-search checks and 918 customization-policy checks passed. The preceding build319 pass also ran 915 glass-policy and 95 tour-policy checks. Independent AI presentation fixtures passed 29 checks.
- Actual installed-app review covered Home, calendar/date selection, Live, Shelf, Dock Workspace and scrolling, Appearance and its focused pages, disabled Live Activities controls, invalid visualizer save state, and tour Next/Back/Skip. The new calendar header/date-cell fixture also rendered at compact/standard widths in light/dark appearance.
- Build320 was visually inspected at default opacity, 50% tile transparency and Original mode. The slider updated its accessible percentage and disabled correctly in Original mode. Test choices were removed/restored while the app was closed. All 55 allowlisted preferences matched the pre-test snapshot after the final relaunch.
- HUD runtime metadata passed after cold launch, Restart HUD, closing Settings and final local relaunch. The user confirmed the physical volume-key indicator appears inside Notchscape on build319 and again on final build320.
- Recoverable installed319 backup: `../notchscape-native-redesign-2026-11-06/rollback.noindex/before320-build319.app`. Build318 backup is retained in the prior November5 staging folder. Logs, source hashes, preference snapshots and install record are outside the source checkout in those staging folders.

## Boundaries and remaining work

This is local verification, not hosted CI, a public release or a real Sparkle update-path test. Public archives/feed were untouched. Active playback, every theme/display configuration, external hardware, live VoiceOver and the full accessibility/motion matrix were not retested in this pass. Screenshots cannot prove physical-notch occlusion; prior hardware geometry was preserved.

No Face authentication, camera enrollment, vault/password operation, clipboard recording, file sharing, wallpaper application or optional-feature enablement was performed. The renewed Face Vault Personal Team profile is still for this Mac/local development only, expiring November13 at13:17:01UTC; it is not a public-distribution solution. Main/helper signing identities and the update key were preserved. Compiler deprecation/concurrency warnings remain; this is not a warning-free build.

Separate audit findings still need scoped follow-up: keyboard-backlight HUD drag forwarding, calendar permission-aware empty state, duplicate accessible marquee text and audio-spectrum timer teardown. They were not mixed into this visual pass.

## Tools and design references

Used Serena project activation, semantic symbol/pattern searches and focused editing; installed Apple Design, SwiftUI Pro/Expert guidance; Apple Docs MCP for current native Slider and Liquid Glass guidance; the required signed Xcode CLI wrapper; and native accessibility controls with targeted screenshots for visual inspection. MobileBuildMCP did not expose the required macOS signed-build workflow. No simulator, web UI, paid generation, new dependency or production service was introduced.

The earlier direction study used 21st.dev metadata and connected Figma. Native SwiftUI previews were used for approval because Figma's SF-font rendering failed. No web component code was imported into this SwiftUI/AppKit application. Context7/separate Xcode MCP were not exposed during tool discovery. Apple references: [Settings HIG](https://developer.apple.com/design/human-interface-guidelines/settings), [Materials HIG](https://developer.apple.com/design/human-interface-guidelines/materials), [Liquid Glass implementation](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views), [Slider](https://developer.apple.com/documentation/swiftui/slider).
