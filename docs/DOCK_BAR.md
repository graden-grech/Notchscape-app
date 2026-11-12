# Dock Bar local preview

The native SwiftUI/AppKit Dock Bar remains optional under Settings → Dock. Its compact live-widget direction uses the public product categories at https://cooldock.app/ and the earlier Glasswave reference, with original implementation and existing Notchscape providers. No competitor code or assets are included.

## Widgets and navigation

The six-item starter and existing saved widget identities remain unchanged. Weather and System are optional additions from +. Adding a widget now reveals its page and opens its controls. Stack mode exposes every hidden instance through a native menu, with meaningful accessible labels. Pages retains stable geometry. Existing app pins, clock zones, timer actions, calculator, media and calendar actions remain available.

Weather reuses the existing location choice, permission gate, in-flight coalescing and 15-minute cache. The Dock checks eligibility at most once per minute using its existing clock task; it adds no timer or permission prompt. Unknown/unconfigured conditions show Set Up. Old cached observations are labelled Last known. System uses one demand-counted sampling lease only while a System face or expanded card is visible; off-page and suspended content release it. Invalid readings show an em dash.

The shared surface uses native macOS 26 Liquid Glass and the existing standard-material/opaque accessibility and low-impact fallbacks. Compact usage bars are simple native vector shapes; expanded readings use native ProgressView. Content tiles add no separate glass layer.

## Reversible native Dock hiding

Keep macOS Dock hidden is default-off for new installs. The current user explicitly requested this behavior, so their new option is enabled while their original Dock Bar enabled state/layout are preserved.

The signed existing Dock helper has a separate directly launched guardian mode before AppKit application initialization. It journals only current-user AnyHost autohide and autohide-delay values, preserving types and absence, before applying auto-hide plus a finite 3,600-second reveal delay. It refuses managed or per-host overrides. The guardian restores owned values on bar suspension, explicit recovery, normal quit, input EOF and parent exit; manual changes win. A locked atomic journal permits next-launch recovery. Only a verified current-user Apple Dock process is refreshed, once per actual preference transition.

Apple presentationOptions apply to the active app, so they cannot implement this background behavior across arbitrary apps. The reveal-delay preference is an undocumented compatibility workaround. System commands can reveal Dock; this is not a guarantee of universal permanent suppression. Killing both the app and its guardian or shutting down the machine can defer recovery until the next launch.

## Local verification — build 324

The signed wrapper and incoming-copy gates passed; 274 source/config hashes remained stable during the build. Main/helper identities, the Sparkle key and accounts-disabled flag were preserved. The existing Face helper profile remains local-only through 13 November 2026; this build is not a public distribution.

362,108 Dock geometry/state assertions and 13,263 injected visibility/recovery assertions passed. The specialist also ran 616 existing Dock-widget assertions and strict Swift 6 helper/controller checks. Actual installed controls, Stack access, setup navigation, native glass and display placement were visually inspected. Synthetic compact faces were reviewed at 32/48-point sizes in light and dark appearances.

Build 324 passed real preference apply, explicit recovery, normal quit, relaunch and force-quit recovery, restoring both original Dock values/absence exactly. Build 323 also established cross-app persistence in Activity Monitor and that the guardian does not register as a separate Dock app. All 68 previously checked app preferences were restored after temporary tests; the new hiding choice is deliberate. Cold, Restart HUD, Settings-close and final-relaunch tap checks passed. The user confirmed the physical volume HUD on 11 November.

No new public archive, update feed, hosted CI, permission grant or broad hardware claim is included. Real forecast retrieval remains unverified because the existing location permission is not configured. Performance sampling was brief, not an Instruments profile. A later report that enabling Dock opens Calendar is under separate investigation; it has not been reproduced or declared fixed.

Tooling: Serena semantic inspection, Apple Docs, focused compiler checks, native accessibility controls, necessary app captures, and one full-display compositor inspection. No screenshot-driven product implementation or external service setup was used.
