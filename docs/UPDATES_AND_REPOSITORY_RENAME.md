# Active update destination and compatibility archives

## Active repository from October 27, 2026

The active project is now [graden-grech/Notchscape-app](https://github.com/graden-grech/Notchscape-app),
a newly created standalone repository with fresh Git history. New source and
releases use its `personal` remote and `main` branch. New app builds use:

`https://raw.githubusercontent.com/graden-grech/Notchscape-app/main/appcast.xml`

The earlier `graden-grech/Notchscape` repository remains publicly available for
historical downloads and the signed 2.9.3 migration feed. Existing clients fetch
that new archive from the new repository; installed 2.9.3 then checks the new feed.
Keep its `boringNotch-custom` rename redirect available too. No signing key,
bundle/helper identity, preference domain or permission reset is part of this move.

See [the fresh-repository migration](NEW_REPOSITORY_MIGRATION.md). Historical
commit references in older artwork/release reports refer to the retained legacy
history, not this new Git root. Consumed assets and their prompt/hash manifests
are included in the new source snapshot.

## Historical October 21 repository rename

The public project is now [graden-grech/Notchscape](https://github.com/graden-grech/Notchscape).
It is the same repository, not a copy. Repository history, issues, release tags,
release asset IDs and download bytes were preserved by the rename on 21 October
2026. Graden Grech maintains this edition; original licenses and credits remain.

## Historical publication paths

- **Source:** `personal` → `https://github.com/graden-grech/Notchscape.git`, branch `main`.
- **App releases:** versioned, signed archives under this repository's Releases.
- **Canonical Sparkle feed:** `https://raw.githubusercontent.com/graden-grech/Notchscape/main/appcast.xml`.

A source push does not publish a new app build or add a feed item. A binary
release requires its own approval, new version/build, trusted signing and update
key, immutable archive, and runtime/update testing. Never replace an already
published archive. Existing release filenames may retain their compatibility
names; renaming or deleting those assets would break their published URLs.

## Compatibility paths must remain available

Existing installed versions use:

`https://raw.githubusercontent.com/graden-grech/boringNotch-custom/main/appcast.xml`

Historical feed enclosures also use download URLs under
`https://github.com/graden-grech/boringNotch-custom/releases/`.
After the rename, anonymous checks verified that both old and new raw-feed URLs
return HTTP200 with identical bytes, the old repository page redirects to
Notchscape, and old and new 2.8.4 archive URLs return identical 21,818,606-byte
downloads. Their SHA256 and Ed25519 signature were independently verified.
These compatibility paths are intentionally retained, not abandoned branding.

**Never create another repository named `boringNotch-custom` under this owner.**
GitHub warns that reusing the old name removes rename redirects. Do not make the
Notchscape repository private while installed users require unauthenticated
updates. Repeat old/new feed and download checks before each release; today's
reachability does not guarantee future availability.

## What is private, and what must stay public

- Full prior Git history is backed up in the private, archived
  `graden-grech/boringNotch-custom-history-archive`, with Actions disabled.
- Withdrawn Windows installers are preserved in private
  `graden-grech/macscapes-windows-private`; no Windows update is published here.
- The minimal public `graden-grech/macscapes-updates` Mac feed/artifacts remain
  needed by existing standalone MacScapes installations. Do not make them
  private or redirect a different-bundle app onto Notchscape's archive. Follow
  the [one-time MacScapes migration](MACSCAPES_MIGRATION.md).
- Older signed Notchscape/compatibility releases stay public while feed items
  and installed clients refer to them. They are not disposable duplicates.
- The unfinished account preview remains an unpublished draft; public app
  account features remain disabled.

## What rename verification does not prove

HTTP reachability, matching hashes and a valid Ed25519 signature establish that
the preserved archive can still be fetched and authenticated. They do not prove
a real Sparkle install/relaunch, HUD permission survival, every macOS version,
or external-display behavior. A newly approved binary release still needs the
separate [HUD/update release checks](HUD_RELEASE_CHECKS.md), a trusted-identity
comparison, and a real supported update from an older installed version.

The repository rename did not change the app bundle identifier, helper
identifiers, signing requirement, preference/Keychain domains or update public
key. The 2.9.1 branding correction changes the executable, source/project names,
helper product filename and downloadable wrapper to Notchscape. Existing
installation-path migration must be verified separately: the current Sparkle
framework replaces an existing host at its existing path. Do not claim that a
branded ZIP alone renames every previous installation.
