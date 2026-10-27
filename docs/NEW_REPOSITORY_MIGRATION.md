# Fresh Notchscape repository

On October 27, 2026, the owner requested a completely new repository after
GitHub Support closed ticket #4906127 without confirming a repair of the old
repository's contributor sidebar. The old contributors API listed only the
owner, while a previous homepage screenshot showed 52.

The new active repository is **graden-grech/Notchscape-app**. It was created as
an empty public repository with a new repository ID and no fork relationship.
Its initial source is a tracked-files snapshot, with a new root commit authored
by `graden-grech`. Previous commits, branches and tags are not imported. Original
licenses, source/dependency notices and artwork provenance remain in the files.

## App and updates

- The product, installed filename and publisher label remain **Notchscape**.
- Version **2.9.3/build 296** embeds the new repository's canonical Sparkle feed.
- The existing app/helper identity, Apple signing requirement, update public key
  and dedicated Keychain signing account remain unchanged.
- The earlier Notchscape repository keeps its historical releases and public
  feeds. Its migration item points to the signed new-repository archive.
- Old `boringNotch-custom` rename redirects still lead to that compatibility
  repository. Reusing that old name, deleting it, or making it private would
  break existing unauthenticated clients.
- Once migrated, later updates come from Notchscape-app. Older historical feed
  entries retain their original URLs and bytes.

New app releases are published only to **Notchscape-app**. The legacy repository
is retained for compatibility; it is not the active development destination.
The new contributor graph is GitHub-computed and must be checked after the
initial push; removing required source credits is not part of this migration.

## Verification boundaries

Verify the new repository is standalone and its default-branch authors are the
owner. Test a public download, independent archive signature, old-feed to new-app
Sparkle update, new-feed check, preferences and HUD. Preserve all older releases.
Source push, release publication and feed activation remain separate actions.
Release-specific results are recorded in verification assets and
[2.9.3 notes](releases/2.9.3.md).
