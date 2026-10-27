# Notchscape distribution readiness

Publisher brand: **Notchscape**. This is a product/publisher label, not a claim
that a company or copyright registration has been obtained. Legal provenance
and third-party notices remain in [ATTRIBUTION.md](ATTRIBUTION.md), LICENSE and
THIRD_PARTY_LICENSES. Routine UI and download branding use Notchscape.

The active project from October 27 is the newly created standalone
`graden-grech/Notchscape-app` repository. New releases use its canonical feed;
the previous `graden-grech/Notchscape` repository remains public for downloads
and signed migration updates. See [the migration record](NEW_REPOSITORY_MIGRATION.md).

## 2.9.1 branding correction

- Project: `Notchscape.xcodeproj`; scheme: `Notchscape`.
- Source directories: `Notchscape` and `NotchscapeHelper`.
- Downloaded app: `Notchscape.app`; main executable: `Notchscape`.
- Helper product: `NotchscapeHelper.xpc`.
- Installer/download names: `Notchscape.zip` / `Notchscape.dmg`.
- About, onboarding, menu accessibility labels and localized product strings use
  Notchscape. Unused original logo assets and the original welcome audio were
  removed; these can be recovered from Git history.
- Restart opens the currently running bundle, not whichever older duplicate
  Launch Services resolves for its compatibility identifier.
- Only explicit reconnection in Apple Notes adopts/renames the app’s legacy
  dedicated folder; stored folder IDs and existing notes are not discarded.

The old bundle identifier, data directories, credentials domain, update signing
account and existing signature requirements are compatibility identifiers, not
customer-facing branding. Do not change them through a search-and-replace:
that can disconnect existing data and invalidate authenticated updates.

## Required release checks

1. Build through `build_custom_signed_app.sh` against a trusted previous app.
2. Run Python workflow/branding/archive tests and affected Swift tests.
3. Package through `package_notchscape_release.sh`. Inspect the extracted app,
   then run signing and branding checks again on that extracted copy.
4. Sign a new archive with the existing Sparkle key and independently verify it.
5. Verify a fresh download and a real legacy-install update/relaunch separately.
   Stock Sparkle preserves the existing install path; a new archive name does
   not establish that the old app on disk was renamed. Test the migration before
   claiming this is solved for existing installations.
6. Verify HUD/permissions, selected settings, one running app, login item and
   update checks after migration. Never reset TCC or weaken security checks.
7. Publish only with fresh user approval. Do not replace any published ZIP.

The signed local 2.9.2/build 293 preview and shared-installer structural test are
recorded in [the preview report](releases/2.9.2-preview.md). They do not change
the public release or establish a new Sparkle update test. Installer production
requirements are recorded in [shared installation](SHARED_INSTALLATION.md).

## Remaining production blockers

The current signing identity is Apple Development, not Developer ID distribution,
and the app is not notarized. Proper broadly trusted macOS distribution needs
Developer ID/notarization access and a planned signing-permission transition.
Do not describe a successful local build as fully production ready.

The supported-version, physical-notch/external-display/DisplayLink,
accessibility, artwork/provider-rights and fresh-device testing limits in
[FEATURE_IMPLEMENTATION_TRACKER.md](FEATURE_IMPLEMENTATION_TRACKER.md) also
remain separate from this branding correction.

Version 2.9.2/build 295 raises all app/helper/project deployment targets to
macOS 15, matching the linked MediaRemoteAdapter. Archive validation rejects
lower or missing minimum-OS metadata, the native installer rejects older target
volumes and the future Homebrew publisher declares Sequoia. Only the new feed
item uses that minimum; historical releases retain their metadata. This resolves
the advertised-minimum mismatch, not the full supported-version test matrix.

## GitHub contributor sidebar mismatch

On 24 October 2026, the homepage screenshot showed **52 Contributors**, while
GitHub's contributors API returned only `graden-grech` with seven contributions.
The public default branch had seven commits, all by that account, and no parent
repository. The original history archive was private and archived.

This is a display/statistics mismatch, not proof that additional people have
repository write access. If it persists after GitHub's refresh window, the
repository owner needs GitHub Support to investigate its cached sidebar. Do not
rewrite history again, delete compatibility release tags, remove legal notices,
or recreate the repository as a purported cache fix.

Suggested support request:

> The homepage for graden-grech/Notchscape displays 52 contributors. Its current
> default branch has seven commits by graden-grech, and the contributors REST
> endpoint returns that one account. Please investigate and refresh the homepage
> contributor sidebar/statistics. The mismatch is visible in my 24 October
> screenshot. Older release assets must remain available for existing updaters.

On 26 October, the authorized Support ticket #4906127 had been closed with a
self-service response referring to Community, Docs and Skills. No cache repair
was confirmed. The contributors API still returned exactly `graden-grech`;
that API result does not verify the homepage sidebar refreshed. The old failed
build email was already in recoverable Trash; no further deletion was needed.
No new support message, public discussion, history rewrite or release mutation
was made during this follow-up check.
