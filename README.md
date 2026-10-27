<p align="center">
  <img src="Notchscape/Assets.xcassets/AppIcon.appiconset/notch-stage-icon2%2010.png" alt="Notchscape icon" width="128" />
</p>

# Notchscape

Your Mac, together. Music, calendar, weather, wallpapers and useful local tools
in one native macOS workspace, at the top of your display.

Published by **Notchscape**. Maintained by [Graden Grech](https://github.com/graden-grech).

[![Build and test](https://github.com/graden-grech/Notchscape-app/actions/workflows/cicd.yml/badge.svg)](https://github.com/graden-grech/Notchscape-app/actions/workflows/cicd.yml)
[![Security checks](https://github.com/graden-grech/Notchscape-app/actions/workflows/codeql.yml/badge.svg)](https://github.com/graden-grech/Notchscape-app/actions/workflows/codeql.yml)

## One workspace

- A configurable notch or floating island, with per-display visibility.
- Music controls, calendar and reminders, location-aware weather, and a file shelf.
- Local Codex and Claude Code activity, with distinct completion and usage-limit states.
- Optional volume and brightness HUDs, battery controls, and system monitoring.
- Seasonal themes, matching icons, custom accent colors and Home layout controls.
- 328 wallpapers adapted from MacScapes and credited sources, with theme matching,
  favorites, previews, display selection and optional rotation.
- Eight temporary workspace Modes, with one-click End/Restore and a manual-end
  Presentation privacy mode. [Mode behavior and limits](docs/WORKSPACE_MODES.md).
- Local Quick Notes, optional Apple Notes sync, clipboard history and text recognition.
- Searchable Settings and a consistent, native control language.
- An optional six-chapter Settings tour, with Skip and replay from General or Help.

See the [latest release](https://github.com/graden-grech/Notchscape-app/releases/latest)
for the current public download and verification status. **2.9.3 (296)** moves
publishing and updates to this new standalone repository, retaining the guided
setup, White House scenes/icons and other app features. See the
[migration and release notes](docs/releases/2.9.3.md). Accounts remain disabled;
no app account is required.

## Download and updates

[Public releases](https://github.com/graden-grech/Notchscape-app/releases)
include version-specific notes and known testing limits. Version 2.9.3 requires
Apple silicon and macOS 15 or later, matching its linked media framework. Native Liquid Glass is
available on macOS 26 or later; earlier systems use lighter standard materials.

The app is development-signed with its existing identity, **not notarized**.
Review the release notes before installing. If macOS blocks a download you
trust, review it in System Settings → Privacy & Security. This project does not
recommend disabling Gatekeeper or globally changing system security settings.

Automatic updates continue through this repository's signed Sparkle feed. The
active repository is **graden-grech/Notchscape-app**, created with fresh history.
The earlier **graden-grech/Notchscape** repository remains available for legacy
downloads and migration updates. Its older rename redirects are preserved.
The app's internal identity and
signing trust remain stable to preserve settings and permissions. New downloads
use **Notchscape.app**; older installations need a tested rename migration.
A source push is not an app release; signed archives and the update
feed are published separately. See the [update destination and rename policy](docs/UPDATES_AND_REPOSITORY_RENAME.md).

Existing standalone MacScapes users need a one-time installation of a released
combined app, not a cross-bundle automatic replacement. See the
[migration and updater policy](docs/MACSCAPES_MIGRATION.md).

## Build and verify

Open `Notchscape.xcodeproj` in Xcode 26 or later. The project, executable,
app bundle, source folders and installer use the Notchscape product name.
For trusted local builds, follow [AGENTS.md](AGENTS.md) and the
[HUD release checklist](docs/HUD_RELEASE_CHECKS.md). Do not install an unsigned
CI build over a permission-approved app.

```sh
git clone https://github.com/graden-grech/Notchscape-app.git
    cd Notchscape-app
open Notchscape.xcodeproj
python3 -m unittest discover -s .github/scripts/tests -q
```

Fresh-device onboarding, full VoiceOver coverage, external-display/DisplayLink
behavior and all supported macOS versions require further device testing. The
experimental lock-screen dropdown uses inherited private SkyLight integration.
Commercial distribution also needs review of weather/artwork provider rights.

## Help and contributions

[Report a bug or suggest an improvement](https://github.com/graden-grech/Notchscape-app/issues).
See [CONTRIBUTING.md](CONTRIBUTING.md) for the contribution and verification process.
Optional inherited publishing jobs remain opt-in; see
[GitHub automation setup](docs/custom-fork-ci.md).

## License and acknowledgments

Notchscape is distributed under the GNU GPL v3. Original-source and dependency
acknowledgments are preserved in the legal notices. See
[open-source notices](docs/ATTRIBUTION.md), the
[GNU GPL v3 license](LICENSE), and [third-party licenses](THIRD_PARTY_LICENSES).
