# Notchscape Native UI Audit — 2026-11-12

## Scope and limits

This was a source-first design and accessibility review of the native macOS SwiftUI application. It does not claim that every page was opened or visually verified. No camera, authentication, Face Unlock vault, personal data, or permission flow was operated. No browser automation or Instagram content was opened.

The active app is SwiftUI/AppKit. Native SwiftUI controls and Apple platform conventions are the appropriate implementation path; web-only component libraries are not a fit for the app UI.

## Screens and components covered

- Main notch composition and navigation structure: `ContentView`, `NotchscapeHeader`, `NotchHomeView`, `TabSelectionView`, and the Live/System dashboard structures.
- Settings shell and navigation: `SettingsView`, its destination index/search model, sidebar rows, subpage links, and `SettingsWindowController`.
- Settings content: General, Appearance overview, Weather, Sports team selection, Dock Workspace, Tools, and Settings Tour.
- Other core utility surfaces: Shelf empty/drop view and the top-level onboarding flow.
- Structural inventory found additional Wallpaper, Add-ons, Calendar, Media, AI Agent, Face Unlock, and productivity pages. Those leaf pages were not all inspected deeply.

## Design direction

Keep one coherent native Mac foundation: a standard resizable Settings window with a real sidebar and titlebar, native grouped forms for preferences, native semantic colors and SF Symbols, and one theme accent used consistently. Keep theme art as a restrained contextual accent. Reserve Liquid Glass for navigation and interactive controls; use standard materials for content previews and tiles. This follows Apple's macOS, layout, Settings, sidebar, materials, button, and accessibility guidance while preserving Notchscape's theme options.

## Findings and work status

1. **Settings navigation needs the standard sidebar affordance.** The initial source review found `.sidebarToggle` removed from the split view. The root workstream is restoring the native control; preserve it or provide a matching View-menu command.
2. **Keep search in the sidebar.** A live review of the pre-build-330 Settings window found the search control was large and floated at the top of the detail column, leaving no clear page heading. Root is moving `.searchable` to sidebar placement and restoring native title/toolbar behavior. The title visibility in `SettingsWindowController` was changed to `.visible`; this source change still needs live verification.
3. **General is too much for one page.** It combines performance, menu-bar modules, startup/Dock, display selection and sizing, notch behavior, and gestures. The first section is a tour link even though onboarding already contains the tour. Root is simplifying the long helper copy, removing the permanently disabled media-gesture switch, and moving the tour link out of the common controls.
4. **Settings page links need native feedback.** `SettingsSubpageLink` used a plain-style button without a visible press/hover treatment. Root is adding shared native feedback while retaining the existing destinations and behavior.
5. **Tools controls were globally undersized.** `WorkspaceToolsView` applied `.controlSize(.small)` to the entire feature view. Changed the overall size to `.regular`; the existing compact switch style remains local to switches.
6. **Dock app icons could be stretched.** Dock Workspace resized app icons into a square frame without an aspect-fit mode. Added `.scaledToFit()` so icons retain their proportions.
7. **Good existing patterns to preserve:** Weather includes loading/failure states and reduced-motion/transparency/contrast handling. Sports includes league filtering, team search, favorites, and loading/error/empty states. The tour has Back, Next, Skip, progress, and does not mutate settings. Shelf has a clear empty state and drop feedback. The system dashboard starts and stops sampling with view visibility.

## Tool and reference record

- **Used and responding:** Serena semantic search/symbol inspection; token_optimizer smart read/search; Apple Docs MCP (`NavigationSplitView` documentation); installed Apple Design, Foundations, Interaction, Materials, and SwiftUI Expert skills; the installed Apple HIG reference pages for macOS, layout, Settings, sidebars, toolbars, buttons, toggles, materials, typography, color, and accessibility.
- **Available but not applicable to this native UI pass:** 21st.dev MCP (web-oriented components). No linked Figma design was identified or used.
- **Not found in the current tool catalog:** CodeRabbit and Context7. Broad Apple Docs search queries returned no results; the specific NavigationSplitView page was retrieved directly.
- **Not invoked because they did not fit this source-only native UI review:** Playwright, Chrome DevTools, MobileBuildMCP/Xcode MCP, Sentry, and Supabase. No test suite or build was run by this audit agent.

## Verification still needed

Root inspected the running General and Appearance Settings screens before the pending build-330 Settings flow. This audit agent did not use UI automation. Before calling the visual audit complete, inspect the new build on the actual Settings window for: sidebar collapse/search placement, visible page title, titlebar spacing and traffic-light clearance, regular-sized Tools controls, and undistorted Dock icons. Then check the remaining leaf pages and accessibility settings (increased contrast, reduced transparency/motion, and larger text). HUD and updater checks remain release work, separate from this visual audit.
